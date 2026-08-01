import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:iter/model/users.dart';
import 'package:iter/services/firebase.dart';

/// Acesso ao perfil salvo em `user/{uid}`.
///
/// O documento é criado no primeiro login por [GoogleSignInService]; aqui só
/// lemos e atualizamos. Devolve `null` quando o documento ainda não existe.
class UserController {
  static CollectionReference<Map<String, dynamic>> get _collection =>
      FirestoreService.instance.collection('user');

  /// Acompanha o perfil em tempo real — edições refletem sozinhas na tela.
  static Stream<Users?> watch(String uid) {
    return _collection.doc(uid).snapshots().map(_toUser);
  }

  /// Leitura única, para quando não faz sentido manter o listener aberto.
  static Future<Users?> fetch(String uid) async {
    return _toUser(await _collection.doc(uid).get());
  }

  /// Grava apenas os campos informados, carimbando `updatedAt`.
  static Future<void> update(String uid, Map<String, dynamic> fields) {
    return _collection.doc(uid).update({
      ...fields,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  static Users? _toUser(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return data == null ? null : Users.fromMap(data);
  }
}
