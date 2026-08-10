/// A regra de pagamento da rota que acabou antes de começar.
///
/// Tudo aqui é função pura sobre o que veio do banco — sem Firestore, sem
/// `BuildContext`, testável sem mock nenhum. Quem busca o documento é
/// `NoRouteRuleController`; quem faz a conta em centavos é
/// [NoRoutePayment.paidValue]. Ver `docs/specs/sem-rota.md`.
library;

import 'package:iter/model/newRouteModal.dart';

/// O percentual do documento `norouterule/{empresa}`, ou `null` quando **não há
/// regra**.
///
/// `null` cobre documento ausente, campo ausente, valor que não é número e valor
/// fora de 1 a 100. Os três casos levam à mesma decisão — o formulário recusa e
/// manda cadastrar — e nenhum deles pode virar um número inventado: 100%
/// superestima o ganho, que é sempre o lado que engana, e 0% zera o valor e de
/// quebra apaga a provisão, porque `provisionFor` desiste em `value <= 0`.
///
/// O teto de 100 pega o erro de digitação que quadruplicaria o pagamento (400 em
/// vez de 40). O piso de 1 é o que torna "regra de 0%" e "documento quebrado"
/// indistinguíveis de propósito: o cliente não tem como saber qual dos dois é.
///
/// Percentual fracionário (`42.5`) é recusado em vez de truncado — truncar
/// gravaria 42% congelado em toda rota sem ninguém ter conferido.
int? readPercent(Map<String, dynamic>? data) {
  if (data == null) return null;

  final raw = data['percent'];
  if (raw is! num) return null;

  // `40.0 == 40` é verdadeiro em Dart, então isto aceita o double redondo que o
  // Firestore devolve e recusa só o percentual com casa decimal de verdade.
  if (raw != raw.toInt()) return null;

  final percent = raw.toInt();
  return percent >= 1 && percent <= 100 ? percent : null;
}

/// Decide o pagamento da Sem Rota quando a rota é salva.
///
/// É a irmã de `resolveProvision`, com a mesma tabela e o mesmo motivo — o pilar
/// do app é que o passado não se reescreve:
///
/// | situação | resultado |
/// |---|---|
/// | status não é `semRota` | `null` — deixou de ser uma ida perdida |
/// | valor cheio não positivo | `null` — o chamador recusa antes, com frase própria |
/// | sem bloco anterior | aplica a regra de **hoje** |
/// | mesma empresa | **mantém o percentual**, recalcula sobre o valor informado |
/// | empresa mudou | aplica a regra de **hoje**, da empresa nova |
/// | sem percentual em lugar nenhum | `null` — e o chamador recusa o save |
///
/// A quarta linha é a que importa: corrigir o valor de uma ida de junho não pode
/// restampar o percentual de hoje. A quinta é a única exceção, e é óbvia — o
/// percentual do Mercado Livre não descreve uma ida da Amazon.
///
/// [existingCompany] é a empresa da rota **como está gravada**, não a escolhida
/// agora. O bloco não guarda a empresa de propósito: a rota já a tem, e um campo
/// duplicado é um campo que um dia discorda do outro.
///
/// Um `percent` congelado inválido (documento corrompido à mão) cai na regra de
/// hoje em vez de travar a rota — recusar ali deixaria o dono sem como corrigir
/// o próprio documento.
NoRoutePayment? resolveNoRoutePayment({
  required StatusRoute status,
  required Company company,
  required double grossValue,
  required NoRoutePayment? existing,
  required Company? existingCompany,
  required int? currentPercent,
  DateTime? now,
}) {
  if (status != StatusRoute.semRota) return null;
  if (grossValue <= 0) return null;

  final frozen = existing != null && existingCompany == company
      ? _validPercent(existing.percent)
      : null;

  final percent = frozen ?? _validPercent(currentPercent);
  if (percent == null) return null;

  return NoRoutePayment(
    grossValue: grossValue,
    percent: percent,
    // Mantendo o percentual, mantém-se o carimbo: senão a rota de junho passaria
    // a dizer que foi recalculada hoje, que é justamente o que não aconteceu.
    appliedAt: frozen != null
        ? existing!.appliedAt
        : (now ?? DateTime.now()).toIso8601String(),
  );
}

int? _validPercent(int? percent) =>
    percent != null && percent >= 1 && percent <= 100 ? percent : null;
