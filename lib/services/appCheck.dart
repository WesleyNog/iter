import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// App Check: a prova de que quem escreve é **este app**, e não um script.
///
/// É a resposta para a coisa que `amigos.md` marcou como "faça antes do app sair
/// do seu celular": `posts`, `comments`, `likes`, `gastop`, `reports`,
/// `nicknames` e `profiles` aceitam escrita de qualquer conta autenticada, e
/// criar conta no Firebase é de graça. Com as notificações no ar, o custo de
/// abuso deixou de ser cota e passou a ser **a tela de bloqueio de todo mundo**,
/// paga pelo dono no Blaze.
///
/// **Nada aqui impõe coisa nenhuma.** A imposição é um interruptor no console,
/// por produto, e ligá-la antes da métrica mostrar os aparelhos verificados
/// derruba o app inteiro. Ver `docs/specs/notificacoes.md`.
class AppCheckService {
  /// Liga o App Check. Chamado de `main()`, depois do `Firebase.initializeApp`.
  ///
  /// **Envolvido em try/catch porque roda antes do `runApp`.** Uma exceção aqui
  /// não daria erro na tela: daria tela preta, sem mensagem, antes de existir
  /// árvore de widgets. Nenhum recurso do app depende desta chamada dar certo —
  /// enquanto a imposição estiver desligada, falhar aqui não muda nada.
  static Future<void> ativar() async {
    try {
      await FirebaseAppCheck.instance.activate(
        // **`providerAndroid`/`providerApple`, e não `androidProvider`/
        // `appleProvider`.** Os dois antigos estão `@Deprecated` no pacote, e
        // toda a documentação e todo tutorial ainda mostram a forma velha.
        //
        // Misturar as duas formas é o pior erro possível aqui: passar um
        // parâmetro antigo junto com um novo instala **em silêncio** o provedor
        // de depuração — que, num binário de release com o token registrado no
        // console, contorna o App Check inteiro. Nunca passe os dois.
        providerAndroid: _debug
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
        providerApple: _debug
            ? const AppleDebugProvider()
            : const AppleAppAttestProvider(),
      );

      await _sonda();
    } catch (e) {
      debugPrint('appcheck: não foi possível ativar: $e');
    }
  }

  /// **`kReleaseMode` invertido, e não `kDebugMode`.**
  ///
  /// `kDebugMode` é **falso em profile**, então `flutter run --profile` cairia
  /// no Play Integrity e falharia a atestação — sem sintoma, porque a falha só
  /// aparece quando a imposição está ligada. Perfil e depuração são os dois
  /// modos em que o app roda na mão do desenvolvedor, e os dois precisam do
  /// token de depuração registrado.
  ///
  /// O que garante que o provedor de depuração não vá para o release não é o
  /// Gradle — a classe está no binário dos dois jeitos. É esta linha, e só ela.
  static bool get _debug => !kReleaseMode;

  /// Pergunta ao App Check se a atestação **de fato** funcionou.
  ///
  /// Existe porque `activate()` **não dá sinal nenhum de sucesso**: ele instala
  /// a fábrica de provedor e devolve, sem buscar atestação. A atestação só
  /// acontece, preguiçosamente, na primeira requisição a um produto do Firebase.
  /// "O app subiu e não deu erro" não é evidência de coisa alguma — dá para
  /// passar meses achando que está pronto para impor e descobrir no dia do
  /// clique que nunca esteve.
  ///
  /// Só em debug: em release não há para onde mostrar, e a métrica do console é
  /// a fonte de verdade. O token é buscado de qualquer forma na primeira
  /// escrita, então isto não acrescenta trabalho, só o antecipa.
  static Future<void> _sonda() async {
    if (kReleaseMode) return;

    try {
      final token = await FirebaseAppCheck.instance.getToken();
      debugPrint(
        token == null || token.isEmpty
            ? 'appcheck: SEM token — a atestação falhou. Com a imposição '
                  'ligada, toda escrita no Firestore seria negada.'
            : 'appcheck: token obtido (${token.length} chars). Atestação OK.',
      );
    } catch (e) {
      // O caso mais comum em debug: o token de depuração deste aparelho ainda
      // não foi registrado no console. Procure no logcat a linha do SDK nativo
      // com o UUID e cadastre em App Check → Apps → Gerenciar tokens de
      // depuração.
      debugPrint('appcheck: atestação falhou: $e');
    }
  }
}
