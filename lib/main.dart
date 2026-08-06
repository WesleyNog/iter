import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:iter/firebase_options.dart';
import 'package:iter/screens/addIter.dart';
import 'package:iter/screens/home.dart';
import 'package:iter/screens/login.dart';

void configLoading() {
  EasyLoading.instance
    ..loadingStyle = EasyLoadingStyle.dark
    ..indicatorType = EasyLoadingIndicatorType.fadingCircle
    ..indicatorSize = 45.0
    ..radius = 10.0
    ..dismissOnTap = false
    ..userInteractions = false;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A chave da OpenWeather vem daqui. O `.env` é asset declarado no pubspec,
  // mas fica fora do git: quem clonar o projeto sem ele sobe o app do mesmo
  // jeito — só o clima é que fica "sem dado", em vez de derrubar a inicialização.
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('Não foi possível carregar o .env: $e');
  }

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  configLoading();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Iter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const AuthGate(),
      routes: {
        '/addIter': (context) {
          final user = ModalRoute.of(context)!.settings.arguments as User;
          return AddIter(user: user);
        },
      },
      // Obrigatório: instala o overlay usado pelo EasyLoading.
      builder: EasyLoading.init(),
    );
  }
}

/// Escolhe a tela inicial a partir do estado do Firebase Auth.
///
/// A sessão é persistida pelo próprio firebase_auth, então quem já entrou cai
/// direto na Home ao abrir o app. Como é um [StreamBuilder], o login e o logout
/// trocam a tela sozinhos — nenhuma das duas telas precisa navegar na mão.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Enquanto o Firebase restaura a sessão salva no dispositivo.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) return const LoginScreen();

        return HomeScreen(user: user);
      },
    );
  }
}
