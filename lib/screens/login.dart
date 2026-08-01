import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:iter/services/authService.dart';
import 'package:iter/widget/notificationPush.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);

    try {
      // Sem await: o show() só completa quando o overlay é apresentado, e o
      // login não pode ficar esperando isso.
      EasyLoading.show(status: 'Entrando').ignore();
      final userCredential = await GoogleSignInService.signInWithGoogle();
      if (!mounted) return;

      // Usuário fechou a janela do Google: não é erro, só volta pra tela.
      if (userCredential == null) return;

      // Não navega: o AuthGate troca para a Home ao receber o novo estado.
      showNotification(
        context: context,
        type: 'success',
        msg: 'Login realizado com sucesso!',
      );
    } catch (e) {
      debugPrint('Erro no login com Google: $e');
      if (!mounted) return;
      showNotification(
        context: context,
        type: 'error',
        // Em debug mostra a causa real; em release, mensagem genérica.
        msg: kDebugMode
            ? 'Falha no login: $e'
            : 'Não foi possível entrar com o Google. Tente novamente.',
      );
    } finally {
      // Fora do `mounted`: no login que dá certo esta tela é desmontada pelo
      // AuthGate, e a máscara ficaria travando a Home para sempre.
      await EasyLoading.dismiss();
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue.shade100,
              Colors.white,
              Colors.white,
              Colors.white,
              Colors.blue.shade100,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/Icon/ITER.png',
                        width: 150,
                        height: 150,
                      ),
                      const SizedBox(height: 50),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Bem-vindo ao',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          Text(
                            ' ITER',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Simplifique rotas. Otimize resultados.',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 120),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              elevation: 3,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: Colors.grey.shade100,
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.asset(
                                  'assets/logo/google.png',
                                  width: 30,
                                  height: 30,
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'Entrar com Google',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                            onPressed: _isLoading ? null : _handleGoogleSignIn,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              elevation: 3,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: Colors.grey.shade100,
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.apple,
                                  size: 40,
                                  color: Colors.black,
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'Entrar com Apple',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  width: 60,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: Colors.greenAccent.shade100,
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: Colors.green.shade600,
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    'Em Breve',
                                    style: TextStyle(
                                      color: Colors.green.shade600,
                                      fontSize: 10,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                            onPressed: () => showNotification(
                              context: context,
                              type: 'alert',
                              msg: 'Em Breve',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  '© 2026 Iter. Todos os direitos reservados.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
