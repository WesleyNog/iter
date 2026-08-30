import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:iter/Utils/pushTarget.dart';
import 'package:iter/services/firebase.dart';

/// As notificações push do lado do app.
///
/// **Não confundir com `widget/notificationPush.dart`**, que apesar do nome é o
/// toast interno (`showNotification`) usado por meia dúzia de telas. Este aqui
/// é o push de verdade: o que chega com o app fechado.
///
/// Por enquanto cuida só do **toque** — para onde ele leva. O registro do token
/// e o pedido de permissão entram na tarefa A7. Ver `docs/specs/notificacoes.md`.
class PushMessaging {
  PushMessaging._();

  static final PushMessaging instance = PushMessaging._();

  /// O toque que ainda não foi consumido.
  ///
  /// Um `ValueNotifier` e não uma navegação direta porque, com o app **morto**,
  /// o toque chega antes de existir qualquer `Navigator`: o `AuthGate` ainda
  /// nem resolveu a sessão. A intenção fica estacionada aqui e é consumida
  /// quando a tela que sabe o que fazer com ela montar.
  ///
  /// O valor é um objeto com **identidade** — ver `NotificationTarget`. Dois
  /// convites seguidos produzem alvos de conteúdo igual, e é a identidade que
  /// faz o segundo contar como evento novo.
  final ValueNotifier<NotificationTarget?> target = ValueNotifier(null);

  StreamSubscription<RemoteMessage>? _abertura;
  StreamSubscription<String>? _rotacao;

  bool _ligado = false;

  /// O id do documento gravado nesta sessão — `sha256(token)`.
  ///
  /// Guardado em memória porque é o que o **logout** precisa, e o uid sozinho
  /// não serve: o id é o hash do token, e buscar o token no meio da saída da
  /// conta seria rede na hora errada. É isso que deixa
  /// `GoogleSignInService.signOut()` continuar sem parâmetro nenhum.
  String? _ultimoDocId;

  static CollectionReference<Map<String, dynamic>> get _tokens =>
      FirestoreService.instance.collection('fcmTokens');

  /// O que o app mostra quando a notificação chega com ele **aberto**.
  ///
  /// Nem Android nem iOS desenham a notificação do sistema em primeiro plano, e
  /// quem desenha aqui é o toast que o app já tem. Este stream entrega o texto
  /// já separado do alvo para que a tela não precise importar
  /// `firebase_messaging` só para ler um título.
  Stream<({String? titulo, String? corpo, NotificationTarget? alvo})>
  get emPrimeiroPlano => FirebaseMessaging.onMessage.map(
    (message) => (
      titulo: message.notification?.title,
      corpo: message.notification?.body,
      alvo: NotificationTarget.fromData(message.data),
    ),
  );

  /// Liga os dois caminhos do toque. Chamado de `main()`, uma vez.
  ///
  /// **`getInitialMessage()` aqui e não na `HomeScreen`**, que é o exemplo da
  /// documentação. Ele **consome** a mensagem, e consumir tarde é o bug do
  /// celular emprestado: se só a Home chamasse, um toque que abre o app
  /// deslogado deixaria a mensagem viva no processo, e a Home de **outra
  /// pessoa** que entrasse depois a consumiria. É o mesmo problema que a chave
  /// de `fcmTokens` fecha do outro lado.
  ///
  /// Não bloqueia o primeiro quadro: quem chama não espera. Se a resposta
  /// chegar depois de a Home montar, o `ValueNotifier` avisa — é para isso que
  /// ele existe.
  Future<void> ligarToques() async {
    if (_ligado) return;
    _ligado = true;

    // App em segundo plano: o toque traz o app para a frente.
    _abertura = FirebaseMessaging.onMessageOpenedApp.listen(
      _estacionar,
      onError: (Object e) => debugPrint('push: onMessageOpenedApp falhou: $e'),
    );

    try {
      // App morto: o toque é o que abriu o processo.
      final inicial = await FirebaseMessaging.instance.getInitialMessage();
      if (inicial != null) _estacionar(inicial);
    } catch (e) {
      // Um toque perdido não pode impedir o app de subir.
      debugPrint('push: getInitialMessage falhou: $e');
    }
  }

  void _estacionar(RemoteMessage message) {
    final alvo = NotificationTarget.fromData(message.data);

    // `null` é "não sei para onde ir" — tipo ausente ou desconhecido. Escolher
    // uma tela seria jogar o usuário num lugar sem relação com o aviso que ele
    // tocou; não fazer nada deixa o app onde ele já estava.
    if (alvo == null) {
      debugPrint('push: mensagem sem destino reconhecível: ${message.data}');
      return;
    }

    target.value = alvo;
  }

  /// Marca o toque como atendido.
  ///
  /// Sem isto a intenção vira parâmetro grudento: a aba Amigos é **desmontada**
  /// a cada troca de aba (`home.dart` é `body: screens[current]`, não
  /// `IndexedStack`), então toda visita futura remontaria a tela e reaplicaria
  /// o deep link antigo, jogando o usuário de volta para uma notificação de
  /// ontem.
  void consumir() => target.value = null;

  /// Descarta o que sobrou de outra sessão.
  ///
  /// Chamado pela `LoginScreen`. O ponto é o `initState` dela e **não** o
  /// `build` do `AuthGate`: aquele `build` é puro, e mexer no notifier de lá
  /// seria escrita durante a construção da árvore.
  ///
  /// Sem isto, um toque recebido enquanto ninguém estava logado fica pendurado,
  /// e quem entrar depois — dias depois, ou outra pessoa no mesmo aparelho —
  /// cai numa tela por causa de um aviso que não é dela.
  void descartarPendente() => target.value = null;

  /// Registra este aparelho para receber notificações de [uid].
  ///
  /// Chamado na **abertura do app** (`HomeScreen.initState`), nunca no login —
  /// a lição que `user/{uid}` deixou congelado desde o primeiro dia:
  /// `signInWithGoogle()` só roda quando a `LoginScreen` o chama, e quem tem
  /// sessão restaurada cai direto na Home. Pendurar no login seria garantir que
  /// nenhum usuário existente jamais registrasse token.
  ///
  /// Silencioso por desenho: nada na tela depende disto, e um toast de erro na
  /// abertura seria ruído sobre algo que o motorista não resolve.
  Future<void> registrarAparelho(String uid) async {
    try {
      // O diálogo do sistema. No Android 13+ é ele que pede
      // `POST_NOTIFICATIONS`; no iOS é o único tiro que o app tem — negado
      // aqui, só volta pelos Ajustes do aparelho.
      await FirebaseMessaging.instance.requestPermission();

      final token = await _tokenDoAparelho();
      if (token == null) return;

      await _gravar(uid: uid, token: token);

      // O token roda sozinho (reinstalação, restauração de backup, limpeza de
      // dados). A assinatura mora aqui, no serviço, e **não** na Home, que é
      // desmontada e remontada; o handler lê o usuário da hora de gravar.
      _rotacao ??= FirebaseMessaging.instance.onTokenRefresh.listen(
        (novo) {
          // O usuário da hora, e não o de quando a assinatura nasceu: o
          // `AuthGate` troca a tela sem trocar o processo, então esta escuta
          // sobrevive a um logout seguido de login de outra conta.
          final atual = FirebaseAuth.instance.currentUser?.uid;
          if (atual == null) return;
          _gravar(uid: atual, token: novo);
        },
        onError: (Object e) => debugPrint('push: onTokenRefresh falhou: $e'),
      );
    } catch (e) {
      debugPrint('push: não foi possível registrar o aparelho: $e');
    }
  }

  /// **Registra mesmo com a permissão negada, e isso é decisão.**
  ///
  /// O contrário — sair cedo quando o usuário recusa — cria um estado morto e
  /// silencioso: quem depois liga as notificações nos Ajustes do aparelho
  /// continua sem receber nada, porque ninguém gravou o token, e só descobre no
  /// dia em que reabrir o app por outro motivo. O preço de registrar é algumas
  /// mensagens enviadas para um aparelho que não as desenha; o preço de não
  /// registrar é uma feature que não volta sozinha.
  ///
  /// No iOS o token do FCM **não existe** antes de o token do APNs chegar, e
  /// ele chega pela rede, alguns instantes depois do `requestPermission`. Sem
  /// esta espera, a primeira abertura num iPhone recém-instalado estoura
  /// `apns-token-not-set`, nenhum documento é gravado, e só passa a funcionar
  /// depois de fechar e reabrir o app — o pior modo de falha possível para uma
  /// feature cujo critério de aceite é "o celular acende".
  Future<String?> _tokenDoAparelho() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final apns = await _esperarApns();
      if (apns == null) {
        // Não é erro definitivo: a próxima abertura tenta de novo.
        debugPrint('push: token do APNs não chegou; tentaremos na próxima vez');
        return null;
      }
    }
    return FirebaseMessaging.instance.getToken();
  }

  /// Dez tentativas de meio segundo. Cinco segundos é muito mais do que o APNs
  /// costuma levar e muito menos do que o usuário nota, já que nada na tela
  /// espera por isto.
  Future<String?> _esperarApns() async {
    for (var tentativa = 0; tentativa < 10; tentativa++) {
      final apns = await FirebaseMessaging.instance.getAPNSToken();
      if (apns != null) return apns;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return null;
  }

  Future<void> _gravar({required String uid, required String token}) async {
    // O id é o **sha256 do token**, não o token cru: o Google trata o token
    // como string opaca e não promete alfabeto nenhum, e um `/` faria um id
    // inválido — falha silenciosa e permanente naquele aparelho. Ver a regra em
    // `firestore.rules`.
    final id = sha256.convert(utf8.encode(token)).toString();

    // O token anterior desta sessão vira lixo no instante em que o novo é
    // gravado — e a rotação (`onTokenRefresh`) é o caminho **normal**, não a
    // exceção. Sem apagar, cada rotação deixa um documento vivo apontando para
    // um aparelho que já não responde, e o servidor paga um envio por ele até a
    // varredura de velhos existir.
    //
    // Só o que esta sessão conhece: um processo novo nasce sem `_ultimoDocId`,
    // e o órfão de ontem é problema da varredura, não deste caminho.
    final anterior = _ultimoDocId;

    try {
      await _tokens.doc(id).set({
        'token': token,
        'uid': uid,
        'platform': defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
        // **Carimbo do servidor, fugindo do padrão da casa de propósito.** Todo
        // `updatedAt` deste app é string ISO; a regra deste aqui compara com
        // `request.time`, e é o único campo que a varredura de token velho vai
        // ler. Escrito em ISO, toda gravação volta `permission-denied` — e, como
        // este caminho é silencioso, o app subiria verde sem receber nada.
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _ultimoDocId = id;

      if (anterior != null && anterior != id) {
        // Melhor esforço: falhar aqui custa um documento órfão, não a feature.
        try {
          await _tokens.doc(anterior).delete();
        } catch (e) {
          debugPrint('push: token anterior não removido: $e');
        }
      }
    } catch (e) {
      debugPrint('push: token não gravado: $e');
    }
  }

  /// Retira este aparelho.
  ///
  /// Chamado por `GoogleSignInService.signOut()` **antes** do
  /// `FirebaseAuth.signOut()`: depois dele `request.auth` é nulo e a regra de
  /// dono nega o delete, deixando o token vivo para sempre — e o próximo
  /// usuário deste celular herdaria as notificações do anterior.
  ///
  /// Melhor esforço com prazo: um delete que não foi **não pode** impedir a
  /// saída da conta. A rede de segurança de verdade é a chave de `fcmTokens`,
  /// que faz o login do próximo dono tomar o aparelho de qualquer jeito.
  Future<void> desregistrarAparelho() async {
    final id = _ultimoDocId;
    _ultimoDocId = null;

    await _rotacao?.cancel();
    _rotacao = null;

    if (id == null) return;

    try {
      await _tokens.doc(id).delete().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('push: token não removido no logout: $e');
    }
  }

  @visibleForTesting
  Future<void> desligar() async {
    await _abertura?.cancel();
    _abertura = null;
    await _rotacao?.cancel();
    _rotacao = null;
    _ultimoDocId = null;
    _ligado = false;
    target.value = null;
  }
}
