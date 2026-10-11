import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/Utils/routeStyle.dart';
import 'package:iter/controller/postController.dart';
import 'package:iter/model/post.dart';
import 'package:iter/services/postImage.dart';
import 'package:iter/Utils/profileDisplay.dart';
import 'package:iter/model/publicProfile.dart';
import 'package:iter/widget/glassSurface.dart';
import 'package:iter/widget/notificationPush.dart';
import 'package:iter/widget/profileAvatar.dart';
import 'package:iter/widget/sectionCard.dart';
import 'package:iter/widget/segmentedSelector.dart';
import 'package:uuid/uuid.dart';

/// Publicar no mural: texto, foto opcional e a empresa da rota.
///
/// O limite de 500 caracteres é o mesmo da regra de segurança — o contador na
/// tela existe para o usuário não escrever 600 e descobrir no `permission
/// denied`. Ver `docs/specs/amigos.md`.
///
/// **A empresa é opcional e incentivada.** Publicar sem ela pergunta antes —
/// o logo no post é o que diz de qual operação se está falando, e o dono pediu
/// que a marcação fosse sempre lembrada. A pergunta nunca bloqueia: "Publicar
/// sem empresa" segue em frente.
class AddPost extends StatefulWidget {
  const AddPost({
    super.key,
    required this.uid,
    this.me,
    this.startWithPhoto = false,
  });

  final String uid;

  /// O próprio perfil público, para o cabeçalho "quem está publicando". Vem do
  /// mapa de perfis do mural; `null` desenha a inicial genérica.
  final PublicProfile? me;

  /// Abre já escolhendo a foto — o botão de câmera do compositor do mural.
  /// Quem toca na câmera quer a foto primeiro; o texto vem depois, se vier.
  final bool startWithPhoto;

  @override
  State<AddPost> createState() => _AddPostState();
}

class _AddPostState extends State<AddPost> {
  static const int maxLength = 500;

  final _controller = TextEditingController();
  XFile? _image;
  Company? _company;
  bool _sending = false;

  /// O trilho de empresas em destaque, depois de "Marcar empresa" no aviso.
  /// Some ao escolher uma.
  bool _nudgeCompany = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    // Depois do primeiro quadro: a folha de câmera/galeria precisa da tela
    // montada embaixo dela.
    if (widget.startWithPhoto) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pick();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Post vazio não é post. Foto sozinha vale — foi pedido assim.
  bool get _canSend =>
      !_sending && (_controller.text.trim().isNotEmpty || _image != null);

  /// Escolhe a origem da foto numa folha — só no atalho da câmera do mural,
  /// que não sabe se a pessoa quer tirar ou escolher. Dentro da tela, os dois
  /// botões do rodapé já são a escolha.
  Future<void> _pick() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sourceTile(
                context,
                icon: Icons.photo_camera_outlined,
                label: 'Tirar foto',
                source: ImageSource.camera,
              ),
              _sourceTile(
                context,
                icon: Icons.photo_library_outlined,
                label: 'Escolher da galeria',
                source: ImageSource.gallery,
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;
    await _pickFrom(source);
  }

  Widget _sourceTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required ImageSource source,
  }) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, size: 20, color: GlassIndicator.accent),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
      onTap: () => Navigator.of(context).pop(source),
    );
  }

  Future<void> _pickFrom(ImageSource source) async {
    try {
      final file = await PostImage.pick(source);
      if (file == null || !mounted) return;
      setState(() => _image = file);
    } catch (e) {
      debugPrint('feed: não foi possível abrir a foto: $e');
      if (!mounted) return;
      showNotification(
        context: context,
        type: 'error',
        msg: 'Não foi possível abrir a foto.',
      );
    }
  }

  /// O toque em Publicar: sem empresa marcada, pergunta antes.
  ///
  /// "Marcar empresa" volta para a tela com o trilho em destaque e o teclado
  /// fechado — senão o trilho fica escondido atrás dele, justamente onde a
  /// pessoa acabou de ser mandada.
  Future<void> _onPublish() async {
    if (!_canSend) return;

    if (_company == null) {
      final publishAnyway = await askPublishWithoutCompany(context);
      if (!mounted) return;
      if (publishAnyway != true) {
        if (publishAnyway == false) {
          FocusScope.of(context).unfocus();
          setState(() => _nudgeCompany = true);
        }
        return;
      }
    }

    await _send();
  }

  Future<void> _send() async {
    if (!_canSend) return;
    setState(() => _sending = true);

    final id = const Uuid().v4();

    try {
      // A imagem sobe **antes** do documento: um caminho apontando para objeto
      // inexistente é pior que um post sem foto. Falhar aqui deixa o post por
      // publicar, que é o lado barato de errar.
      String? path;
      if (_image != null) {
        path = await PostImage.upload(
          uid: widget.uid,
          postId: id,
          file: _image!,
        );
      }

      await PostController.publish(
        Post(
          id: id,
          uid: widget.uid,
          text: _controller.text.trim(),
          company: _company,
          imagePath: path,
          createdAt: DateTime.now(),
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on TimeoutException catch (e) {
      debugPrint('feed: upload estourou o prazo: $e');
      if (!mounted) return;
      setState(() => _sending = false);
      // Prazo estourado quase sempre é sinal ruim, e é uma instrução
      // diferente de "tente de novo": o texto continua aqui, e publicar sem a
      // foto é uma saída de verdade.
      showNotification(
        context: context,
        type: 'error',
        msg:
            'A foto demorou demais. Tente com sinal melhor, ou publique '
            'só o texto.',
      );
    } catch (e) {
      debugPrint('feed: não foi possível publicar: $e');
      if (!mounted) return;
      setState(() => _sending = false);
      showNotification(
        context: context,
        type: 'error',
        msg: 'Não foi possível publicar. Tente de novo.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nova publicação'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            // Pílula azul e não um `TextButton`: era a única ação da tela e
            // parecia um rótulo cinza no canto.
            child: FilledButton(
              key: const ValueKey('publicar'),
              onPressed: _canSend ? _onPublish : null,
              style: FilledButton.styleFrom(
                backgroundColor: GlassIndicator.accent,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                minimumSize: const Size(0, 38),
              ),
              child: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Publicar'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _composerCard(),
          const SizedBox(height: 24),
          _companySection(),
        ],
      ),
    );
  }

  /// O post como ele vai sair: quem publica, o texto, a foto e, no rodapé, as
  /// ferramentas — no mesmo card branco do mural.
  Widget _composerCard() {
    final me = widget.me;
    final left = maxLength - _controller.text.characters.length;

    return DecoratedBox(
      decoration: SectionCard.decoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                ProfileAvatar(profile: me, radius: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName(me),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // O mural é global — a regra lista `posts` para qualquer
                      // conta. Dizer isso antes de publicar é o mínimo.
                      Row(
                        children: [
                          Icon(
                            Icons.public,
                            size: 13,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Aparece no mural para todos',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              key: const ValueKey('texto-post'),
              controller: _controller,
              autofocus: !widget.startWithPhoto,
              minLines: 4,
              maxLines: 10,
              maxLength: maxLength,
              style: const TextStyle(fontSize: 16, height: 1.4),
              decoration: InputDecoration(
                hintText: composerPrompt(me),
                hintStyle: TextStyle(color: Colors.grey.shade500),
                border: InputBorder.none,
                // O contador mora no rodapé do card, ao lado das ferramentas.
                counterText: '',
              ),
            ),
          ),
          if (_image != null) _imagePreview(),
          const Divider(
            height: 1,
            thickness: 1,
            indent: 16,
            endIndent: 16,
            color: Color(0xFFEEE9F2),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
            child: Row(
              children: [
                IconButton(
                  key: const ValueKey('foto-camera'),
                  tooltip: 'Tirar foto',
                  icon: Icon(
                    Icons.photo_camera_outlined,
                    color: GlassIndicator.accent,
                  ),
                  onPressed: () => _pickFrom(ImageSource.camera),
                ),
                IconButton(
                  key: const ValueKey('escolher-foto'),
                  tooltip: 'Escolher da galeria',
                  icon: Icon(
                    Icons.photo_library_outlined,
                    color: GlassIndicator.accent,
                  ),
                  onPressed: () => _pickFrom(ImageSource.gallery),
                ),
                const Spacer(),
                // O teto da regra à vista, para não virar surpresa no envio.
                // Laranja nos últimos 50: é quando ele passa a importar.
                Text(
                  '$left',
                  key: const ValueKey('restantes'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: left < 50
                        ? Colors.orange.shade800
                        : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imagePreview() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Stack(
        alignment: Alignment.topRight,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(
              File(_image!.path),
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                key: const ValueKey('remover-foto'),
                tooltip: 'Remover foto',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => setState(() => _image = null),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A empresa: o trilho de logos da Lista, mas de escolha única.
  ///
  /// Logos e não nomes — é como as empresas aparecem no resto do app, e é o
  /// selo que o post vai levar. Tocar na marcada desmarca: o vínculo é
  /// opcional, e sem isso não haveria como voltar atrás.
  Widget _companySection() {
    final nudge = _nudgeCompany && _company == null;
    final accent = GlassIndicator.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            nudge ? 'TOQUE NA EMPRESA DA ROTA' : 'EMPRESA DA ROTA',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: nudge ? accent : Colors.grey.shade600,
            ),
          ),
        ),
        // O contorno azul é o "é aqui" de quem voltou do aviso. Some quando
        // uma empresa é escolhida.
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: nudge ? accent : Colors.transparent,
              width: 2,
            ),
          ),
          child: SegmentedSelector<Company?>(
            keyPrefix: 'empresa',
            tone: SegmentedTone.glass,
            selected: _company,
            onChanged: (company) => setState(() {
              _company = _company == company ? null : company;
              _nudgeCompany = false;
            }),
            segments: [
              for (final company in Company.values)
                SegmentOption<Company?>(
                  value: company,
                  label: companyLabel(company),
                  keySuffix: company.name,
                  child: Image.asset(
                    companyLogo(company),
                    height: 20,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Text(companyLabel(company)),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            'Opcional — o logo vai no post e diz de qual operação você está '
            'falando.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
        ),
      ],
    );
  }
}

/// O aviso de publicar sem empresa. `true` publica assim mesmo, `false` volta
/// para marcar, `null` é o aviso dispensado — nada acontece.
///
/// Fora da tela, como função, para ter teste: publicar de verdade chama o
/// Firestore, e o que importa aqui é a pergunta e as duas saídas.
Future<bool?> askPublishWithoutCompany(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      // Branco, como o resto do mural: o padrão do Material 3 é o lilás.
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      icon: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.local_shipping_outlined,
          color: GlassIndicator.accent,
          size: 26,
        ),
      ),
      title: const Text('Publicar sem a empresa?'),
      content: const Text(
        'O logo da empresa vai no post e mostra de qual operação você está '
        'falando. Quer voltar e marcar?',
        textAlign: TextAlign.center,
      ),
      // Os dois rótulos não cabem lado a lado, e o `OverflowBar` empilhava
      // desalinhado. Empilhados de propósito, na largura toda: o caminho que
      // se quer incentivar em cima, cheio; o outro embaixo, discreto.
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              key: const ValueKey('marcar-empresa'),
              onPressed: () => Navigator.of(context).pop(false),
              style: FilledButton.styleFrom(
                backgroundColor: GlassIndicator.accent,
                minimumSize: const Size.fromHeight(46),
              ),
              child: const Text('Marcar empresa'),
            ),
            const SizedBox(height: 6),
            TextButton(
              key: const ValueKey('publicar-sem-empresa'),
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade700,
                minimumSize: const Size.fromHeight(44),
              ),
              child: const Text('Publicar sem empresa'),
            ),
          ],
        ),
      ],
    ),
  );
}
