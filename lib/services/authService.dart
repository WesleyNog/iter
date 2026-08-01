import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:iter/controller/nicknameController.dart';
import 'package:iter/model/users.dart';
import 'package:iter/services/firebase.dart';

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
    try {
      await initSignIn();
      await _googleSignIn.signOut();
      await _auth.signOut();
    } catch (e) {
      debugPrint('Erro ao sair: $e');
      rethrow;
    }
  }

  // Get current user
  static User? getCurrentUser() {
    return _auth.currentUser;
  }
}
