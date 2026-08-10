import 'package:iter/Utils/noRouteRule.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/services/firebase.dart';

/// A coleção **global** `norouterule`: quanto cada empresa paga por uma rota que
/// acabou antes de começar.
///
/// É a segunda coleção compartilhada do app e a primeira que é **configuração de
/// negócio**, não dado de usuário. `gastop` é gravável porque quem passa no
/// posto relata o preço; aqui ninguém relata nada — quem edita é o dono, no
/// console, e `firestore.rules` fecha a escrita para todo cliente. Ver
/// `docs/specs/sem-rota.md`.
class NoRouteRuleController {
  /// O percentual da empresa, ou `null` quando **não há regra cadastrada**.
  ///
  /// **Lança** quando a leitura falha — sem rede, sem permissão, regra não
  /// deployada. Essa é a diferença que o método existe para preservar: a
  /// primeira leitura de `norouterule` num aparelho nunca vem do cache, então
  /// offline o `get` volta `unavailable`. Colapsar isso em `null` mandaria o
  /// entregador sem sinal cadastrar no console uma regra que já está lá — o
  /// mesmo pecado que o default de 100% cometeria.
  ///
  /// O id do documento é `Company.name`, o mesmo texto que `NewRouteModal.toMap`
  /// grava em `company`: leitura por id conhecido, sem query e sem índice.
  static Future<int?> fetchPercent(Company company) async {
    final snapshot = await FirestoreService.instance
        .collection('norouterule')
        .doc(company.name)
        .get();

    // `data()` é null quando o documento não existe, e `readPercent` trata isso
    // como "sem regra" — igual a campo ausente ou percentual fora de 1..100.
    return readPercent(snapshot.data());
  }
}
