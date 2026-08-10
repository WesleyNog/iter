/// Quanto tempo faz, do jeito que o mural escreve.
///
/// Estava dentro do `PostCard` como método privado, e saiu de lá quando o
/// comentário passou a precisar da mesma frase. É o mesmo motivo de
/// `profileDisplay.dart` existir: a regra copiada em dois lugares já divergiu
/// uma vez neste projeto.
library;

/// `agora`, `há 12min`, `há 3h`, `há 2d`, `06/08`.
///
/// A data cheia só quando o item sai da semana — "há 43d" não diz nada que
/// `06/08` não diga melhor.
///
/// [reference] existe para o teste não depender do relógio, como o
/// `sortByDate` da lista de rotas.
String relativeWhen(DateTime at, {DateTime? reference}) {
  final diff = (reference ?? DateTime.now()).difference(at);

  // Diferença negativa é relógio adiantado ou carimbo do servidor ainda não
  // confirmado, e "agora" é a leitura certa dos dois — nunca "há -3min".
  if (diff.inMinutes < 1) return 'agora';
  if (diff.inMinutes < 60) return 'há ${diff.inMinutes}min';
  if (diff.inHours < 24) return 'há ${diff.inHours}h';
  if (diff.inDays < 7) return 'há ${diff.inDays}d';

  final day = at.day.toString().padLeft(2, '0');
  final month = at.month.toString().padLeft(2, '0');
  return '$day/$month';
}
