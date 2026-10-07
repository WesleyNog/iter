import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/packageLabel.dart';

/// Converte a posição normalizada (topo, esquerda, largura, altura em fração
/// da imagem) para pixels, que é o espaço dos cantos do QR.
OcrLine Function(String, double, double, double, double) _on(Size size) =>
    (text, top, left, width, height) => OcrLine(
      text,
      Rect.fromLTWH(
        left * size.width,
        top * size.height,
        width * size.width,
        height * size.height,
      ),
    );

// As duas fotos do pedido, lidas em 2026-10-06 pelo Vision da Apple — OCR no
// aparelho, do mesmo tipo do app — depois da compressão do WhatsApp. O texto
// está como o OCR devolveu, com os erros dele ("CEF.", "Complemeato",
// "António"): é contra eles que o parser tem de funcionar.

/// Saco plástico, 720×1280. O bairro quebra para a linha de baixo.
const _foto1Size = Size(720, 1280);
const _foto1Qr = [
  Offset(465, 839),
  Offset(668, 849),
  Offset(670, 1060),
  Offset(460, 1047),
];
List<OcrLine> _foto1() {
  final l = _on(_foto1Size);
  return [
    l(
      'Bianca Aparecida Machado de de Alencar B #233106843',
      .12,
      .25,
      .59,
      .04,
    ),
    // O remetente também tem rua, vírgula e um bairro que está na lista.
    l('Rodovia Presidente Dutra 4674, Centro', .14, .25, .42, .04),
    l('São João de Meriti, BR-RJ - 25510000', .17, .25, .41, .03),
    l('Venda: 2000018013208702', .18, .24, .30, .03),
    l('FRJ02', .20, .19, .13, .03),
    l('Despachar: seg 24/ago, antes das 14:30', .22, .48, .48, .03),
    l('47806623578', .35, .52, .24, .03),
    l('3', .41, .17, .11, .09),
    l('SCE1', .42, .30, .46, .09),
    l('05:00', .46, .83, .12, .03),
    l('FRJ02 > XSP9 > SCE1 > 52', .54, .40, .41, .03),
    l('TER 01/09/2026', .60, .17, .30, .03),
    l('NF: 39106', .61, .49, .19, .03),
    l('IGOR LEAL ALBUQUERQUE DE PAULA', .63, .11, .45, .03),
    l('PESSOA (LEALIGOR75)', .65, .11, .27, .02),
    l('Endereço: Rua Pereira de Miranda 575,', .67, .10, .48, .03),
    l('Papicu', .69, .10, .08, .02),
    l('CEP: 60175045', .73, .09, .21, .02),
    l('Cidade de destino: Fortaleza, Ceará', .75, .09, .44, .03),
    l('Complemento: apto 72 torre 4', .79, .08, .38, .03),
    l('R', .85, .77, .03, .02),
  ];
}

/// Caixa de papelão, 899×1599, impressão gasta. Os cantos do QR vêm do
/// detector do OpenCV — ele achou o QR, mas não conseguiu decodificar.
const _foto2Size = Size(899, 1599);
const _foto2Qr = [
  Offset(680, 852),
  Offset(799, 842),
  Offset(810, 960),
  Offset(692, 968),
];
List<OcrLine> _foto2() {
  final l = _on(_foto2Size);
  return [
    l('Rubens', .11, .15, .08, .01),
    l('Momira 2081320053', .10, .23, .22, .02),
    l('Rodovia BR', .11, .15, .12, .01),
    l('-101 Sul 5275, Distrilo Industrial Diper', .10, .27, .39, .02),
    l('Cabo de Santo Agostinho, BR-PE 54503900', .12, .15, .47, .03),
    l('Venda: 2000018165336636', .14, .15, .28, .03),
    l('MLEPED1', .17, .05, .18, .03),
    l('47878868074', .28, .44, .23, .03),
    l('51 SCE1', .35, .08, .58, .10),
    l('06:00', .37, .76, .11, .02),
    l('FPEU1 > SCE1 > 11', .46, .41, .26, .03),
    l('NF: 993044', .49, .53, .19, .03),
    l('SEG 31/08/2026', .50, .17, .26, .03),
    l('Emilio Gress (EMILIOGRESS)', .52, .10, .42, .04),
    l('Endereço: Avenida António Justa 3330, Meireles', .55, .10, .55, .04),
    l('CEF. 60165090', .60, .11, .20, .03),
    l('Cidade de destino: Fortaleza, Ceara', .61, .11, .41, .03),
    l('R', .62, .82, .03, .02),
    l('Complemeato: apartamento 1700', .63, .11, .38, .04),
    l('DANFE', .71, .19, .02, .03),
    l('SIMPLIFICADO', .70, .20, .03, .07),
    l('Chaue', .77, .12, .06, .01),
  ];
}

List<OcrLine> _without(List<OcrLine> lines, String text) =>
    lines.where((line) => line.text != text).toList();

List<OcrLine> _replacing(List<OcrLine> lines, String text, String by) => [
  for (final line in lines) line.text == text ? OcrLine(by, line.box) : line,
];

LabelRead _read(List<OcrLine> lines, {List<Offset> qr = _foto1Qr}) =>
    readLabel(shipmentId: '47806623578', qrCorners: qr, lines: lines);

void main() {
  group('shipmentIdFromQr', () {
    test('o QR da etiqueta dá o número do envio', () {
      expect(shipmentIdFromQr('{"id":"47806623578","t":"lm"}'), '47806623578');
    });

    test('id numérico também vale', () {
      expect(shipmentIdFromQr('{"id":47806623578}'), '47806623578');
    });

    test('o QR do convite do iter não é etiqueta', () {
      expect(shipmentIdFromQr('iter://amigo/meu-yzwy'), isNull);
    });

    test('JSON sem id, com id que não é número, ou que não é objeto', () {
      expect(shipmentIdFromQr('{"t":"lm"}'), isNull);
      expect(shipmentIdFromQr('{"id":"abc123"}'), isNull);
      expect(shipmentIdFromQr('[47806623578]'), isNull);
      expect(shipmentIdFromQr(''), isNull);
    });
  });

  group('foto 1 — bairro na linha de baixo', () {
    test('Papicu, residencial, parada pelo CEP e pelo número', () {
      final read = _read(_foto1());

      expect(read.bairro, 'Papicu');
      expect(read.rawBairro, 'Papicu');
      expect(read.type, PackageType.residencial);
      expect(read.stopKey, '60175045 575');
    });

    test('sem a letra, o tipo é nulo — nunca residencial', () {
      expect(_read(_without(_foto1(), 'R')).type, isNull);
    });

    test('letra solta fora da tarja não vira tipo', () {
      final l = _on(_foto1Size);
      // Na altura do "3" da caixa preta, longe do QR.
      final read = _read([..._foto1(), l('A', .41, .20, .03, .03)]);

      expect(read.type, PackageType.residencial);
    });

    test('duas letras diferentes na tarja é ambiguidade', () {
      final l = _on(_foto1Size);
      final read = _read([..._foto1(), l('A', .85, .82, .03, .02)]);

      expect(read.type, isNull);
    });

    test('borda da tarja lida como pontuação ainda é a letra', () {
      final read = _read(_replacing(_foto1(), 'R', '|R.'));

      expect(read.type, PackageType.residencial);
    });

    test('sem os cantos do QR não há onde procurar a letra', () {
      expect(_read(_foto1(), qr: const []).type, isNull);
    });

    test(
      'sem o rótulo "Endereço", o endereço do remetente não vira bairro',
      () {
        final lines = _foto1()
            .where((line) => !line.text.startsWith('Endereço'))
            .toList();
        final read = _read(_without(lines, 'Papicu'));

        // "Rodovia Presidente Dutra 4674, Centro" tem vírgula e "Centro" está
        // na lista — e não é para onde o pacote vai.
        expect(read.bairro, isNull);
        expect(read.rawBairro, isNull);
        expect(read.stopKey, isNull);
      },
    );
  });

  group('foto 2 — impressão gasta', () {
    test('Meireles, residencial, CEP lido mesmo como "CEF."', () {
      final read = _read(_foto2(), qr: _foto2Qr);

      expect(read.bairro, 'Meireles');
      expect(read.type, PackageType.residencial);
      expect(read.stopKey, '60165090 3330');
    });

    test('letra grudada na linha vizinha vale pela posição da palavra', () {
      final l = _on(_foto2Size);
      final letter = l('R', .62, .82, .03, .02);
      final lines = [
        for (final line in _without(_foto2(), 'R'))
          if (line.text.startsWith('Cidade de destino'))
            OcrLine(
              'Cidade de destino: Fortaleza, Ceara R',
              Rect.fromLTRB(
                line.box.left,
                line.box.top,
                letter.box.right,
                letter.box.bottom,
              ),
              elements: [l('Cidade', .61, .11, .08, .03), letter],
            )
          else
            line,
      ];

      expect(_read(lines, qr: _foto2Qr).type, PackageType.residencial);
    });
  });

  group('endereço', () {
    List<OcrLine> withAddress(String first, String? second) {
      final l = _on(_foto1Size);
      final lines = _foto1()
          .where((line) => line.text != 'Papicu')
          .map(
            (line) => line.text.startsWith('Endereço')
                ? l(first, .67, .10, .48, .03)
                : line,
          )
          .toList();
      return [if (second != null) l(second, .69, .10, .20, .02), ...lines];
    }

    test('bairro fora da lista fica nulo, e o lido vai para a revisão', () {
      final read = _read(
        withAddress('Endereço: Rua Pereira de Miranda 575,', 'Água Fria'),
      );

      expect(read.bairro, isNull);
      expect(read.rawBairro, 'Água Fria');
    });

    test(
      '"Cidade 2000" na linha de baixo é o bairro, não o fim do endereço',
      () {
        final read = _read(
          withAddress('Endereço: Rua Tal 100,', 'Cidade 2000'),
        );

        expect(read.bairro, 'Cidade 2000');
      },
    );

    test('"Centro" na linha de baixo não é confundido com "CEP"', () {
      final read = _read(withAddress('Endereço: Rua Tal 100,', 'Centro'));

      expect(read.bairro, 'Centro');
    });

    test('rótulo sem a cedilha ainda abre o endereço', () {
      final read = _read(
        withAddress('Enderego: Rua Pereira de Miranda 575, Papicu', null),
      );

      expect(read.bairro, 'Papicu');
      expect(read.stopKey, '60175045 575');
    });

    test('endereço sem número não agrupa parada', () {
      final read = _read(withAddress('Endereço: Rua Sem Saída S/N,', 'Papicu'));

      expect(read.bairro, 'Papicu');
      expect(read.stopKey, isNull);
    });

    test('sem a linha do CEP não agrupa parada', () {
      final read = _read(_without(_foto1(), 'CEP: 60175045'));

      expect(read.bairro, 'Papicu');
      expect(read.stopKey, isNull);
    });
  });

  group('matchBairro', () {
    test('igual depois de normalizar', () {
      expect(matchBairro('PAPICU'), 'Papicu');
      expect(matchBairro('Dionisio Torres'), 'Dionísio Torres');
    });

    test('uma letra trocada pelo OCR', () {
      expect(matchBairro('Meirelles'), 'Meireles');
    });

    test('dois bairros dentro da tolerância é nenhum', () {
      // Praia do Futuro I e II ficam a uma letra um do outro.
      expect(matchBairro('Praia do Futuro Il'), isNull);
      // Sem o numeral, o I está mais perto — e escolher seria chutar.
      expect(matchBairro('Praia do Futuro'), isNull);
      // Damas e Dunas.
      expect(matchBairro('Dumas'), isNull);
    });

    test('fora da lista, ou vazio', () {
      expect(matchBairro('Água Fria'), isNull);
      expect(matchBairro(''), isNull);
      expect(matchBairro(' , '), isNull);
    });
  });

  test('cada tipo tem a sua letra', () {
    expect(PackageType.values.map(packageTypeLetter).toSet(), {'R', 'C', 'A'});
  });

  group('quando o OCR do aparelho perde a vírgula', () {
    test('vírgula lida como ponto: o bairro da linha de baixo vale', () {
      final read = _read(
        _replacing(
          _foto1(),
          'Endereço: Rua Pereira de Miranda 575,',
          'Endereço: Rua Pereira de Miranda 575.',
        ),
      );

      expect(read.bairro, 'Papicu');
      // O número sai da linha do rótulo.
      expect(read.stopKey, '60175045 575');
    });

    test('depois da vírgula não casa, mas a linha de baixo casa', () {
      // O Vision partiu a linha: a vírgula ficou junto de um pedaço do QR.
      final read = _read(
        _replacing(
          _foto1(),
          'Endereço: Rua Pereira de Miranda 575,',
          'Endereço: Rua Pereira de Miranda 575, Q8Zx',
        ),
      );

      expect(read.bairro, 'Papicu');
      expect(read.rawBairro, 'Papicu');
    });

    test('CEP ilegível dentro do bloco não vira o bairro bruto', () {
      final read = _read(
        _replacing(
          _replacing(
            _foto1(),
            'Endereço: Rua Pereira de Miranda 575,',
            'Endereço: Rua Pereira de Miranda 575.',
          ),
          'Papicu',
          'Papicuu Zx',
        ),
      );

      // Nada casa; o bruto é a linha logo abaixo do rótulo, não o "CEP" que
      // não encerrou o bloco.
      expect(read.bairro, isNull);
      expect(read.rawBairro, 'Papicuu Zx');
    });
  });

  group('a segunda olhada na tarja', () {
    test('a janela fica logo abaixo do QR e pega a tarja das duas fotos', () {
      final l1 = _on(_foto1Size);
      final l2 = _on(_foto2Size);

      expect(
        letterWindow(
          _foto1Qr,
        )!.contains(l1('R', .85, .77, .03, .02).box.center),
        isTrue,
      );
      expect(
        letterWindow(
          _foto2Qr,
        )!.contains(l2('R', .62, .82, .03, .02).box.center),
        isTrue,
      );
      expect(letterWindow(const []), isNull);
    });

    test('no recorte, uma letra só é o tipo', () {
      const box = Rect.fromLTWH(0, 0, 40, 50);
      expect(letterIn(const [OcrLine('R', box)]), PackageType.residencial);
      expect(letterIn(const [OcrLine('|A.', box)]), PackageType.agencia);
    });

    test('no recorte, duas letras diferentes ou nenhuma é nulo', () {
      const box = Rect.fromLTWH(0, 0, 40, 50);
      expect(letterIn(const [OcrLine('R', box), OcrLine('A', box)]), isNull);
      expect(letterIn(const [OcrLine('RA', box)]), isNull);
      expect(letterIn(const []), isNull);
    });

    test('withType preenche a letra e não apaga o resto', () {
      final read = _read(_without(_foto1(), 'R')).withType(PackageType.agencia);

      expect(read.type, PackageType.agencia);
      expect(read.bairro, 'Papicu');
      expect(read.stopKey, '60175045 575');
    });
  });
}
