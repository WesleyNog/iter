import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:iter/Utils/monthStats.dart';
import 'package:iter/Utils/profileDisplay.dart';
import 'package:iter/Utils/ranking.dart';
import 'package:iter/Utils/routeStyle.dart';
import 'package:iter/Utils/routeTime.dart';
import 'package:iter/controller/profileController.dart';
import 'package:iter/model/publicProfile.dart';
import 'package:iter/widget/segmentedSelector.dart';

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
  });

  final String uid;
  final List<String> friends;
  final Map<String, PublicProfile?> profiles;
  final double bottomGap;

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
    _load();
  }

  @override
  void didUpdateWidget(RankingTab old) {
    super.didUpdateWidget(old);
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
    return Column(
      children: [
        _monthBar(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: SegmentedSelector<RankCriterion>(
            keyPrefix: 'criterio',
            selected: _criterion,
            onChanged: (c) => setState(() => _criterion = c),
            segments: [
              for (final c in RankCriterion.values)
                SegmentOption(value: c, label: c.label, keySuffix: c.name),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _criterion.hint,
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _monthBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            key: const ValueKey('mes-anterior'),
            icon: const Icon(Icons.chevron_left),
            onPressed: _canGoBack
                ? () => _goTo(DateTime(_month.year, _month.month - 1))
                : null,
          ),
          SizedBox(
            width: 170,
            child: Text(
              '${monthLabel(_month.month).toUpperCase()} ${_month.year}',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.6,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('mes-seguinte'),
            icon: const Icon(Icons.chevron_right),
            onPressed: _canGoForward
                ? () => _goTo(DateTime(_month.year, _month.month + 1))
                : null,
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading && _buckets == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed) {
      return _aviso('Não foi possível carregar o ranking.');
    }

    final buckets = _buckets;
    if (buckets == null) return const SizedBox.shrink();

    if (widget.friends.isEmpty) {
      return _aviso(
        'Adicione amigos para comparar. Por enquanto o ranking só tem você.',
      );
    }

    final rows = rankBy(_criterion, buckets);
    final disputa = rows.where((r) => r.ranked).toList();
    final fora = rows.where((r) => !r.ranked).toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, widget.bottomGap),
      children: [
        if (disputa.isEmpty)
          _aviso(
            'Ninguém tem $minimumRoutes rotas neste mês ainda — sem amostra '
            'não dá para comparar.',
          )
        else
          for (var i = 0; i < disputa.length; i++) _linha(disputa[i], i + 1),
        if (fora.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            'AINDA SEM AMOSTRA',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          for (final row in fora) _linha(row, null),
        ],
      ],
    );
  }

  Widget _linha(RankRow row, int? position) {
    final isMe = row.uid == widget.uid;
    final profile = widget.profiles[row.uid];
    final name = displayName(profile);

    return Container(
      key: ValueKey('rank-${row.uid}'),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        // A própria linha destacada: o usuário pediu para aparecer no ranking,
        // e achar-se numa lista de vinte não pode depender de ler os nomes.
        color: isMe ? Colors.blue.shade50 : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: position != null && position <= 3
                ? Image.asset(
                    position == 1
                        ? 'assets/images/OURO-MEDAL.png'
                        : position == 2
                        ? 'assets/images/PRATA-MEDAL.png'
                        : 'assets/images/BRONZE-MEDAL.png',
                    width: 25,
                    height: 25,
                  )
                : Text(
                    position == null ? '—' : '$position',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: position == null
                          ? Colors.grey.shade400
                          : Colors.grey.shade700,
                    ),
                  ),
          ),
          const SizedBox(width: 4),
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.blue.shade50,
            // Cacheado em disco: os mesmos avatares reaparecem a cada visita.
            backgroundImage: hasPhoto(profile?.photoUrl)
                ? CachedNetworkImageProvider(profile!.photoUrl!)
                : null,
            child: hasPhoto(profile?.photoUrl)
                ? null
                : Text(
                    displayInitial(name),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isMe ? '$name (você)' : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isMe ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _format(row.value),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              // A amostra ao lado do número, sempre: "1,4%" de 40 rotas e de
              // 2 rotas são o mesmo texto e não são a mesma informação.
              Text(
                row.routes == 1 ? '1 rota' : '${row.routes} rotas',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _format(double? value) {
    if (value == null) return '—';

    return switch (_criterion) {
      RankCriterion.rotas => value.toInt().toString(),
      // O mesmo "4h22" do card da rota e do dialog de perfil.
      RankCriterion.tempo => RouteTime.formatMinutes(value.round()),
      RankCriterion.insucesso =>
        '${value.toStringAsFixed(1).replaceAll('.', ',')}%',
    };
  }

  Widget _aviso(String message) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey.shade700),
      ),
    );
  }
}
