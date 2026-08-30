package com.mna.iter

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        criarCanalDeNotificacao()
    }

    /**
     * Cria o canal em que as notificações do iter são desenhadas.
     *
     * O `meta-data default_notification_channel_id` do manifesto **aponta** para
     * um canal; ele não cria nenhum. Sem esta função, o SDK do Firebase inventa
     * o `fcm_fallback_notification_channel` com `IMPORTANCE_DEFAULT`, que apenas
     * **toca som**: não abre banner e não acende a tela. É o requisito da
     * feature falhando com o resto do código certo. De quebra, o canal do
     * fallback aparece nos Ajustes do aparelho como "Miscellaneous", em inglês,
     * num app inteiro em português — o AAR só traz `values/` sem tradução.
     *
     * Aqui e não no Dart porque o canal precisa existir **antes** da primeira
     * mensagem chegar, inclusive com o app fechado, e a `Activity` é o que
     * sempre rodou antes: o token só é gravado com a Home montada.
     *
     * Chamar de novo com o mesmo id é no-op — `createNotificationChannel` é
     * idempotente —, então não há o que proteger contra a segunda abertura.
     *
     * Ver `docs/specs/notificacoes.md`.
     */
    private fun criarCanalDeNotificacao() {
        // `NotificationChannel` é API 26 e o `minSdk` do projeto é 24. Sem esta
        // porta, os dois aparelhos que ainda rodam Android 7 morrem aqui.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val gerenciador = getSystemService(NotificationManager::class.java) ?: return

        gerenciador.createNotificationChannel(
            NotificationChannel(
                CANAL_SOCIAL,
                "Amigos",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Convites, ranking e reações às suas publicações."
            },
        )
    }

    companion object {
        /**
         * O mesmo valor do `default_notification_channel_id` no
         * `AndroidManifest.xml` — os dois mudam juntos ou nenhum muda.
         *
         * **Trocar este id, ou a importância, depois do primeiro aparelho ter
         * instalado é irreversível por deploy:** o app não pode alterar a
         * importância de um canal já criado, só o usuário nos Ajustes. Corrigir
         * exigiria um id novo mais `deleteNotificationChannel` do antigo.
         */
        private const val CANAL_SOCIAL = "iter_social"
    }
}
