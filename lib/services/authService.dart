import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:iter/model/users.dart';
import 'package:iter/services/firebase.dart';
import 'package:uuid/uuid.dart';

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
      print(googleUser);

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

  // Cria o documento user/{uid} no primeiro login
  static Future<void> _createUserIfNeeded(User user) async {
    final doc = firestore.collection('user').doc(user.uid);
    final register = await doc.get();
    final name = user.displayName ?? '';
    final nickname = name.contains(' ')
        ? '${name.substring(0, name.indexOf(' '))}-${Uuid().v4().substring(0, 4)}'
        : name;
    if (register.exists) return;

    final String now = DateTime.now().toIso8601String();
    final newUser = Users(
      id: user.uid,
      name: name,
      nickName: nickname,
      email: user.email ?? '',
      phone: user.phoneNumber ?? '',
      birthDate: '',
      cpf: '',
      photoUrl: user.photoURL ?? '',
      createdAt: now,
      updatedAt: now,
    );

    await doc.set(newUser.toMap());
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
