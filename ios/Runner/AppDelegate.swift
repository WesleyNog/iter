import Flutter
import UIKit

// Sem este import o `FLTFirebaseMessagingPlugin` não existe em Swift, e o build
// para com "Cannot find 'FLTFirebaseMessagingPlugin' in scope". O exemplo do
// README do firebase_messaging traz o import só na versão Objective-C; a versão
// Swift, que é a que se copia, vem sem ele.
import firebase_messaging

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // **Obrigatório neste projeto por causa do ciclo de vida UIScene.**
    //
    // Apps que adotam UIScene — este adotou: existe `SceneDelegate.swift` e o
    // delegate é `FlutterImplicitEngineDelegate` — registram os plugins do
    // Flutter *depois* que este método retorna. Só que a Apple exige o
    // `UNUserNotificationCenter.delegate` configurado **antes** disso. Sem esta
    // linha o delegate fica nulo e o `onMessage` nunca dispara no iOS: o recurso
    // sobe verde em teste de Android e fica mudo no iPhone.
    //
    // A linha entra **dentro** do método que já existia, e não substituindo-o.
    // Copiar o método do README por cima apagaria o
    // `FlutterImplicitEngineDelegate` e o `didInitializeImplicitFlutterEngine`
    // abaixo — e aí nenhum plugin registra, o app morre em
    // `MissingPluginException` no primeiro `Firebase.initializeApp()`, e parece
    // regressão do Firebase quando é o AppDelegate.
    //
    // É inofensiva enquanto o push do iOS não estiver ligado: configurar um
    // delegate não exige entitlement, chave APNs nem conta paga.
    FLTFirebaseMessagingPlugin.configureNotificationCenterDelegate()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // O canal de OCR do leitor de pacotes (`TextReader.swift`). Aqui, junto dos
    // plugins, porque com UIScene é aqui que o engine existe — registrar em
    // `didFinishLaunchingWithOptions` encontraria o engine ainda por criar.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IterTextReader") {
      TextReader.register(with: registrar.messenger())
    }
  }
}
