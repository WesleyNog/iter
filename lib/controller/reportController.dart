import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:iter/model/report.dart';
import 'package:iter/services/firebase.dart';

/// Denúncia: `reports/{alvo}__{quem denunciou}`.
///
/// **Um controller só de escrita, e isso é o desenho.** A regra fecha `get` e
/// `list` para todo mundo, então não existe `watch` nem `fetch` aqui — quem
/// modera lê no console do Firebase, que é escrita e leitura de admin e não
/// passa pelas regras. Ver `docs/specs/amigos.md`.
class ReportController {
  static FirebaseFirestore get _db => FirestoreService.instance;

  static String get path => 'reports';

  static CollectionReference<Map<String, dynamic>> get _collection =>
      _db.collection(path);

  /// Envia a denúncia.
  ///
  /// `set` e não `add`: o id é `{alvo}__{quem}`, então denunciar duas vezes o
  /// mesmo alvo sobrescreve a primeira em vez de encher a fila de moderação —
  /// e a regra libera `create` e `update` sob a mesma condição justamente para
  /// que o segundo toque não volte como erro na cara de quem denuncia.
  static Future<void> send(Report report) =>
      _collection.doc(report.id).set(report.toCreateMap());
}
