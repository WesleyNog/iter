import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:iter/Utils/monthStats.dart';
import 'package:iter/Utils/ranking.dart';
import 'package:iter/controller/profileController.dart';
import 'package:iter/model/publicProfile.dart';
import 'package:iter/widget/rankingBoard.dart';

/// O ranking entre amigos, mês a mês.
///
/// Lê `profiles/{uid}/stats/{yyyy-MM}` de cada um — as rotas do amigo são
/// ilegíveis por regra, e é para isso que o balde existe. O próprio usuário
/// entra na lista pela **mesma** porta que os amigos: duas fontes para o mesmo
/// número é a armadilha que `VehicleController.activeFrom()` existe para
/// evitar. Ver `docs/specs/amigos.md`.
class RankingTab extends StatefulWidget {
  const RankingTab({
    super.key,
    required this.uid,
    required this.friends,
    required this.profiles,
    required this.bottomGap,
    this.initialCriterion,
  });

  final String uid;
  final List<String> friends;
  final Map<String, PublicProfile?> profiles;
  final double bottomGap;

  /// O critério que o toque numa notificação pediu, ou `null`.
  ///
  /// "Cleyton passou você em Ritmo" tem de abrir em **Ritmo**: cair no padrão
  /// obrigaria o usuário a procurar a disputa de que o aviso falava.
  final RankCriterion? initialCriterion;

  @override
  State<RankingTab> createState() => _RankingTabState();
}

class _RankingTabState extends State<RankingTab> {
  RankCriterion _criterion = RankCriterion.rotas;

  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late final DateTime _current = _month;

  Map<String, MonthStats>? _buckets;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // Antes do `_load()`: o critério não muda o que se busca (o balde do mês é
    // o mesmo para os três), mas deixa o primeiro quadro já na disputa certa.
    _aplicarCriterio();
    _load();
  }

  @override
  void didUpdateWidget(RankingTab old) {
    super.didUpdateWidget(old);

    // **`initState` não basta.** Quem chega de outra aba monta a tela e passa
    // por lá; quem **já estava** no Ranking quando o push chegou só passa por
    // aqui. Sem os dois, o deep link funciona em metade dos caminhos.
    //
    // Igualdade de valor serve neste caso, ao contrário do alvo em si: dois
    // avisos seguidos do mesmo critério não têm nada a fazer — a tela já está
    // nele. E é isso que impede o parâmetro de grudar quando o usuário troca de
    // critério na mão e a tela de cima reconstrói.
    if (old.initialCriterion != widget.initialCriterion) _aplicarCriterio();
    // Compara o **conjunto**, não o tamanho: remover a ana e aceitar a carla
    // no mesmo instante mantém o tamanho e troca quem disputa.
    if (!setEquals(old.friends.toSet(), widget.friends.toSet())) _load();
  }

  /// Um balde por participante. Não republica o próprio antes: quem mantém o
  /// balde do dono são a abertura do app e a gravação de rota, e refazer a
  /// conta aqui custaria baixar a coleção de rotas inteira a cada troca de mês.
  Future<void> _load() async {
    final month = monthKey(_month);
    final uids = rankingParticipants(widget.uid, widget.friends);

    setState(() {
      _loading = true;
      _failed = false;
    });

    try {
      final results = await Future.wait(
        uids.map((uid) => ProfileController.fetchMonth(uid, month)),
      );
      if (!mounted || monthKey(_month) != month) return;

      setState(() {
        _buckets = {
          // Balde ausente é mês parado, não erro: quem não rodou aparece com
          // zero em vez de sumir da lista.
          for (var i = 0; i < uids.length; i++)
            uids[i]: results[i] ?? const MonthStats(),
        };
        _loading = false;
      });
    } catch (e) {
      debugPrint('ranking: não foi possível ler os baldes: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _aplicarCriterio() {
    final pedido = widget.initialCriterion;
    if (pedido != null) _criterion = pedido;
  }

  void _goTo(DateTime month) {
    setState(() => _month = month);
    _load();
  }

  bool get _canGoForward => _month.isBefore(_current);

  /// A janela que `publish` mantém: doze meses. Mais para trás não existe
  /// balde, e a tela mostraria zeros que não são zeros.
  bool get _canGoBack {
    final oldest = DateTime(
      _current.year,
      _current.month - (ProfileController.windowMonths - 1),
    );
    return _month.isAfter(oldest);
  }

  @override
  Widget build(BuildContext context) {
    final buckets = _buckets;

    // Rola junto com a lista, cabeça incluída (decisão 3 da spec): a maior
    // lista de hoje tem cinco pessoas, e fixar a cabeça faria o card ocupar a
    // altura inteira mesmo com três linhas.
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 14, 16, widget.bottomGap),
      children: [
        RankingBoard(
          month: _month,
          criterion: _criterion,
          onCriterion: (c) => setState(() => _criterion = c),
          onPrevious: _canGoBack
              ? () => _goTo(DateTime(_month.year, _month.month - 1))
              : null,
          onNext: _canGoForward
              ? () => _goTo(DateTime(_month.year, _month.month + 1))
              : null,
          rows: buckets == null ? null : rankBy(_criterion, buckets),
          profiles: widget.profiles,
          me: widget.uid,
          hasFriends: widget.friends.isNotEmpty,
          // **Também com balde na tela.** Era aqui o mês errado: o carregamento
          // só aparecia sem balde nenhum, e ao trocar de mês os números do
          // anterior ficavam sob o título do novo até a rede responder.
          loading: _loading,
          failed: _failed,
          onRetry: _load,
        ),
      ],
    );
  }
}
