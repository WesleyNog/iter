import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:iter/controller/nicknameController.dart';
import 'package:iter/model/users.dart';
import 'package:iter/services/firebase.dart';
import 'package:iter/services/pushMessaging.dart';

// Google Sign-In Service Class
class GoogleSignInService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  static final firestore = FirestoreService.instance;
  static bool _isInitialized = false;

  // Initialize Google Sign-In
  //
  // Sem clientId/serverClientId: o plugin lê o client OAuth do
  // google-services.json (Android) e do GoogleService-Info.plist (iOS),
  // então não há ID de projeto fixo no código.
  static Future<void> initSignIn() async {
    if (_isInitialized) return;
    await _googleSignIn.initialize();
    _isInitialized = true;
  }

  /// Faz login com o Google e devolve a credencial do Firebase.
  ///
  /// Retorna `null` quando o usuário cancela o fluxo — qualquer outra falha
  /// é lançada para a tela tratar.
  static Future<UserCredential?> signInWithGoogle() async {
    await initSignIn();

    try {
      final GoogleSignInAccount googleUser = await _googleSignIn.authenticate();
      final String? idToken = googleUser.authentication.idToken;

      if (idToken == null) {
        throw FirebaseAuthException(
          code: 'missing-google-id-token',
          message:
              'O Google não devolveu o idToken. Confira o client OAuth do '
              'projeto (SHA-1 no Firebase / google-services.json).',
        );
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );

      final User? user = userCredential.user;
      if (user != null) {
        await _createUserIfNeeded(user);
      }

      return userCredential;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  // Cria o documento user/{uid} e reserva o apelido no primeiro login
  static Future<void> _createUserIfNeeded(User user) async {
    final doc = firestore.collection('user').doc(user.uid);
    final register = await doc.get();
    if (register.exists) return;

    final String now = DateTime.now().toIso8601String();
    final newUser = Users(
      id: user.uid,
      name: user.displayName ?? '',
      email: user.email ?? '',
      phone: user.phoneNumber ?? '',
      birthDate: '',
      cpf: '',
      photoUrl: user.photoURL ?? '',
      createdAt: now,
      updatedAt: now,
    );

    // O apelido sugerido pode já estar reservado. Nesse caso o `create` da
    // reserva é negado pelas regras, o batch inteiro é desfeito e sorteamos
    // outro sufixo — o documento do usuário nunca fica sem apelido.
    for (var attempt = 0; attempt < 5; attempt++) {
      final nickname = NicknameController.suggestFrom(
        displayName: user.displayName,
        email: user.email,
      );
      newUser.nickName = nickname;

      final batch = firestore.batch();
      batch.set(doc, newUser.toMap());
      batch.set(
        NicknameController.docFor(nickname),
        NicknameController.claimData(user.uid),
      );

      try {
        await batch.commit();
        return;
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
        debugPrint('Apelido "$nickname" indisponível, sorteando outro.');
      }
    }

    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'nickname-unavailable',
      message: 'Não foi possível reservar um apelido para este usuário.',
    );
  }

  // Sign out
  static Future<void> signOut() async {
    // **Antes de tudo, e fora do try que faz rethrow.**
    //
    // Depois do `_auth.signOut()` o `request.auth` é nulo e a regra de dono
    // nega o delete do token, que ficaria vivo para sempre — e o próximo
    // usuário deste celular herdaria as notificações do anterior.
    //
    // Fora do `try`: este método faz `rethrow`, e a tela mostra o erro. Uma
    // falha ao apagar o token — sem rede, por exemplo — não pode impedir
    // alguém de sair da própria conta. O método já engole a própria exceção e
    // tem prazo; a rede de segurança de verdade é a chave de `fcmTokens`, que
    // faz o login do próximo dono tomar o aparelho de qualquer jeito.
    await PushMessaging.instance.desregistrarAparelho();

    try {
      await initSignIn();
      await _googleSignIn.signOut();
      await _auth.signOut();
    } catch (e) {
      debugPrint('Erro ao sair: $e');
      rethrow;
    }
  }

  /// Exclui a conta de quem está logado. Ver `docs/specs/exclusao-de-conta.md`.
  ///
  /// Devolve `false` quando a pessoa desiste no seletor do Google — igual ao
  /// `null` de [signInWithGoogle]; qualquer outra falha é lançada para a tela.
  ///
  /// **Só apaga o usuário do Auth.** Rotas, perfil, amizades, fotos e o resto
  /// quem apaga é a Function `excluirConta`, que dispara com a exclusão — o
  /// cliente não tem permissão para metade daquilo, e não precisa ter.
  ///
  /// **Pede o Google de novo sempre**, em vez de tentar o `delete()` e reagir a
  /// `requires-recent-login`: a reautenticação é também a segunda confirmação
  /// de um gesto que não tem volta. Escolher outra conta Google no seletor dá
  /// `user-mismatch` no `reauthenticateWithCredential`, antes de apagar nada.
  static Future<bool> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: 'no-current-user');
    }

    await initSignIn();

    final GoogleSignInAccount googleUser;
    try {
      googleUser = await _googleSignIn.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      rethrow;
    }

    final idToken = googleUser.authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(code: 'missing-google-id-token');
    }

    await user.reauthenticateWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );

    // Antes do `delete()`, pela razão do `signOut`: depois dele não há
    // `request.auth` para a regra deixar apagar. A Function apaga os tokens de
    // todos os aparelhos de qualquer jeito; isto aqui desliga o listener de
    // rotação deste, para ele não tentar regravar um token sem dono.
    await PushMessaging.instance.desregistrarAparelho();

    await user.delete();

    // Revoga o acesso do iter à conta Google, para o próximo login pedir
    // consentimento de novo. Melhor esforço: a conta já não existe, e falhar
    // aqui não desfaz nada.
    try {
      await _googleSignIn.disconnect();
    } catch (e) {
      debugPrint('Conta excluída, mas o disconnect do Google falhou: $e');
    }

    return true;
  }

  // Get current user
  static User? getCurrentUser() {
    return _auth.currentUser;
  }
}
