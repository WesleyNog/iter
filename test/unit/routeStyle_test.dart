import 'package:flutter_test/flutter_test.dart';
import 'package:iter/Utils/routeStyle.dart';
import 'package:iter/model/newRouteModal.dart';

void main() {
  group('companyFromLabel — o caminho de volta', () {
    test('desfaz companyLabel para toda empresa', () {
      // Derivado, não uma segunda tabela: o teste percorre o enum inteiro, e
      // uma empresa nova entra aqui sozinha. Um par que existisse só de um
      // lado — rótulo sem volta — apareceria como logo faltando no dialog de
      // perfil, e em nenhum lugar antes disso.
      for (final company in Company.values) {
        expect(companyFromLabel(companyLabel(company)), company);
      }
    });

    test('rótulo que este app não conhece devolve null', () {
      // É o documento de carreira escrito por uma versão com uma empresa a
      // mais. `null` faz o dialog desenhar o texto, que é o que ele tem.
      expect(companyFromLabel('Loggi'), isNull);
      expect(companyFromLabel(''), isNull);
      // Sem casar por aproximação: "mercado livre" não é o rótulo gravado.
      expect(companyFromLabel('mercado livre'), isNull);
    });
  });
}
