/// A vitrine pública de um entregador: `profiles/{uid}`.
///
/// Existe porque `user/{uid}` guarda CPF, e-mail, telefone e data de
/// nascimento — aquele documento nunca abre. Aqui só entra o que o dialog de
/// perfil mostra, que é exatamente a tela onde alguém confirma "é essa a
/// pessoa?" antes de convidar.
///
/// **`name` e `photoUrl` vêm do `User` do FirebaseAuth, nunca de
/// `user/{uid}`.** Os campos daquele documento estão congelados desde o
/// primeiro login (`_createUserIfNeeded` volta cedo quando ele já existe) e
/// ninguém percebeu porque nenhuma tela os lê. Copiar de lá seria herdar foto
/// velha para sempre — ver `docs/specs/amigos.md`.
///
/// Quem lê devolve `PublicProfile?`, e `null` significa **"ainda não
/// publicado"** — não "não existe". É o estado de todo usuário anterior a
/// esta entrega que não reabriu o app, e a tela de busca tem de dizer isso em
/// vez de "ninguém usa esse apelido", que seria mentira. Mesma disciplina do
/// `getWeather`, que devolve `null` para "não deu para saber".
library;

/// As chaves que `firestore.rules` aceita em `profiles/{uid}`.
///
/// A regra tem `hasOnly` com esta lista: qualquer chave a mais é recusada na
/// escrita. É o que transforma "nunca gravar CPF na projeção" de convenção em
/// invariante — nenhum `publish()` futuro consegue vazar um campo por
/// descuido, porque o servidor recusa antes.
class PublicProfile {
  const PublicProfile({
    required this.uid,
    required this.name,
    required this.updatedAt,
    this.nickName,
    this.photoUrl,
  });

  final String uid;
  final String name;

  /// Cópia de exibição de `nicknames/{apelido}`, que continua sendo a fonte.
  ///
  /// A regra confere que a reserva é mesmo deste uid antes de aceitar a
  /// gravação: sem isso, qualquer um se publicaria como `@outrapessoa` e
  /// apareceria assim na lista de amigos alheia.
  final String? nickName;

  final String? photoUrl;

  /// ISO 8601. Carimbado por quem grava, não pelo modelo.
  final String updatedAt;

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'nickName': nickName,
      'photoUrl': photoUrl,
      'updatedAt': updatedAt,
    };
  }

  factory PublicProfile.fromMap(Map<String, dynamic> map) {
    return PublicProfile(
      uid: map['uid'] as String? ?? '',
      name: map['name'] as String? ?? '',
      nickName: map['nickName'] as String?,
      photoUrl: map['photoUrl'] as String?,
      updatedAt: map['updatedAt'] as String? ?? '',
    );
  }

}
