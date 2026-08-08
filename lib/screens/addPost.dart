import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:iter/model/newRouteModal.dart';
import 'package:iter/Utils/routeStyle.dart';
import 'package:iter/controller/postController.dart';
import 'package:iter/model/post.dart';
import 'package:iter/services/postImage.dart';
import 'package:iter/widget/notificationPush.dart';
import 'package:uuid/uuid.dart';

/// Publicar no mural: texto, foto opcional e a empresa da rota.
///
/// O limite de 500 caracteres é o mesmo da regra de segurança — o contador na
/// tela existe para o usuário não escrever 600 e descobrir no `permission
/// denied`. Ver `docs/specs/amigos.md`.
class AddPost extends StatefulWidget {
  const AddPost({super.key, required this.uid});

  final String uid;

  @override
  State<AddPost> createState() => _AddPostState();
}

class _AddPostState extends State<AddPost> {
  static const int maxLength = 500;

  final _controller = TextEditingController();
  XFile? _image;
  Company? _company;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Post vazio não é post. Foto sozinha vale — foi pedido assim.
  bool get _canSend =>
      !_sending && (_controller.text.trim().isNotEmpty || _image != null);

  Future<void> _pick() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

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
        msg: 'A foto demorou demais. Tente com sinal melhor, ou publique '
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
    final left = maxLength - _controller.text.characters.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Publicar'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              key: const ValueKey('publicar'),
              onPressed: _canSend ? _send : null,
              child: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Publicar'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 6,
            minLines: 3,
            maxLength: maxLength,
            decoration: InputDecoration(
              hintText: 'Como foi o dia?',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              // O contador do próprio campo, para o teto da regra não virar
              // surpresa no momento de publicar.
              counterText: '$left',
            ),
          ),
          const SizedBox(height: 12),
          _imageBlock(),
          const SizedBox(height: 20),
          Text(
            'VINCULAR A UMA EMPRESA',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          _companyPicker(),
        ],
      ),
    );
  }

  Widget _imageBlock() {
    final image = _image;

    if (image == null) {
      return OutlinedButton.icon(
        key: const ValueKey('escolher-foto'),
        onPressed: _pick,
        icon: const Icon(Icons.image_outlined),
        label: const Text('Adicionar foto'),
      );
    }

    return Stack(
      alignment: Alignment.topRight,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(image.path),
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(6),
          child: CircleAvatar(
            backgroundColor: Colors.black54,
            radius: 16,
            child: IconButton(
              key: const ValueKey('remover-foto'),
              padding: EdgeInsets.zero,
              iconSize: 18,
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => setState(() => _image = null),
            ),
          ),
        ),
      ],
    );
  }

  Widget _companyPicker() {
    return Wrap(
      spacing: 8,
      children: [
        for (final company in Company.values)
          ChoiceChip(
            key: ValueKey('empresa-${company.name}'),
            label: Text(companyLabel(company)),
            selected: _company == company,
            // Tocar de novo desmarca: o vínculo é opcional, e sem isso não
            // haveria como voltar atrás depois de escolher.
            onSelected: (on) =>
                setState(() => _company = on ? company : null),
          ),
      ],
    );
  }
}
