package com.mna.iter

import android.app.NotificationChannel
import android.app.NotificationManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import android.graphics.Rect
import android.net.Uri
import android.os.Build
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    /** Criado no primeiro uso: quem nunca abre o leitor não carrega o modelo. */
    private var reconhecedor: TextRecognizer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        criarCanalDeNotificacao()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANAL_OCR)
            .setMethodCallHandler { call, result ->
                val caminho = call.argument<String>("path")
                if (caminho == null) {
                    result.error("bad-args", "path ausente", null)
                    return@setMethodCallHandler
                }
                when (call.method) {
                    "read" -> lerTexto(caminho, result)
                    "readRegion" -> lerRecorte(
                        caminho,
                        call.argument<Number>("left")?.toDouble(),
                        call.argument<Number>("top")?.toDouble(),
                        call.argument<Number>("right")?.toDouble(),
                        call.argument<Number>("bottom")?.toDouble(),
                        call.argument<Boolean>("invert") ?: false,
                        maxOf(1, call.argument<Number>("scale")?.toInt() ?: 1),
                        result,
                    )
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        reconhecedor?.close()
        reconhecedor = null
        super.onDestroy()
    }

    /**
     * O lado Android do canal de OCR do leitor de pacotes — o contrato está em
     * `lib/services/textReader.dart`, e o lado iOS em `TextReader.swift`.
     *
     * O ML Kit já mede em pixels da imagem com a origem em cima à esquerda, o
     * mesmo espaço dos cantos do QR que o `mobile_scanner` devolve: aqui não há
     * conversão, só a tradução para mapa. O JPEG que chega já está em pé (o
     * plugin rotaciona antes de comprimir) e não tem EXIF de orientação.
     *
     * Os erros vão **sem mensagem**: a exceção de um motor de OCR pode carregar
     * o texto que ele leu, e o texto é o endereço de outra pessoa.
     */
    private fun lerTexto(caminho: String, result: MethodChannel.Result) {
        val imagem = try {
            InputImage.fromFilePath(this, Uri.fromFile(File(caminho)))
        } catch (e: Exception) {
            result.error("read-failed", null, null)
            return
        }

        reconhecer(imagem, result)
    }

    /**
     * O recorte da tarja da letra: branco sobre preto, ~12 px de altura no
     * quadro inteiro. Recortado, ampliado e invertido, vira uma letra preta do
     * tamanho em que o OCR lê letra solta. As posições da resposta são do
     * recorte ampliado — quem chama só lê o texto.
     */
    private fun lerRecorte(
        caminho: String,
        esquerda: Double?,
        topo: Double?,
        direita: Double?,
        base: Double?,
        inverter: Boolean,
        escala: Int,
        result: MethodChannel.Result,
    ) {
        if (esquerda == null || topo == null || direita == null || base == null) {
            result.error("bad-args", "recorte ausente", null)
            return
        }
        val inteira = BitmapFactory.decodeFile(caminho)
        if (inteira == null) {
            result.error("read-failed", null, null)
            return
        }

        val recorte = Rect(
            esquerda.toInt().coerceIn(0, inteira.width),
            topo.toInt().coerceIn(0, inteira.height),
            direita.toInt().coerceIn(0, inteira.width),
            base.toInt().coerceIn(0, inteira.height),
        )
        if (recorte.width() < 4 || recorte.height() < 4) {
            inteira.recycle()
            result.success(emptyList<Map<String, Any>>())
            return
        }

        val cortada = Bitmap.createBitmap(
            inteira, recorte.left, recorte.top, recorte.width(), recorte.height(),
        )
        val ampliada = Bitmap.createScaledBitmap(
            cortada, recorte.width() * escala, recorte.height() * escala, true,
        )
        val pronta = if (inverter) inverterCores(ampliada) else ampliada

        if (cortada !== inteira) inteira.recycle()
        if (ampliada !== cortada) cortada.recycle()
        if (pronta !== ampliada) ampliada.recycle()

        reconhecer(InputImage.fromBitmap(pronta, 0), result)
    }

    private fun inverterCores(origem: Bitmap): Bitmap {
        val destino = Bitmap.createBitmap(origem.width, origem.height, Bitmap.Config.ARGB_8888)
        val negativo = ColorMatrix(
            floatArrayOf(
                -1f, 0f, 0f, 0f, 255f,
                0f, -1f, 0f, 0f, 255f,
                0f, 0f, -1f, 0f, 255f,
                0f, 0f, 0f, 1f, 0f,
            ),
        )
        Canvas(destino).drawBitmap(
            origem, 0f, 0f, Paint().apply { colorFilter = ColorMatrixColorFilter(negativo) },
        )
        return destino
    }

    private fun reconhecer(imagem: InputImage, result: MethodChannel.Result) {
        val motor = reconhecedor
            ?: TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                .also { reconhecedor = it }

        motor.process(imagem)
            .addOnSuccessListener { texto ->
                result.success(
                    texto.textBlocks.flatMap { bloco ->
                        bloco.lines.mapNotNull { linha -> linhaParaMapa(linha) }
                    },
                )
            }
            .addOnFailureListener { result.error("ocr-failed", null, null) }
    }

    private fun linhaParaMapa(linha: Text.Line): Map<String, Any>? {
        val caixa = linha.boundingBox ?: return null
        return trechoParaMapa(linha.text, caixa) + mapOf(
            "elements" to linha.elements.mapNotNull { palavra ->
                palavra.boundingBox?.let { trechoParaMapa(palavra.text, it) }
            },
        )
    }

    private fun trechoParaMapa(texto: String, caixa: Rect): Map<String, Any> = mapOf(
        "text" to texto,
        "left" to caixa.left,
        "top" to caixa.top,
        "right" to caixa.right,
        "bottom" to caixa.bottom,
    )

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

        /** O mesmo nome de `TextReader.channel` em `lib/services/textReader.dart`. */
        private const val CANAL_OCR = "iter/ocr"
    }
}
