/**
 * O classificador — a única parte da moderação que fala com o mundo.
 *
 * Gemini via **Vertex AI**, não via chave do AI Studio: autentica com a
 * service account da própria Function (nenhuma chave em disco), o conteúdo
 * fica com o processador que o app já usa, e no Vertex não treina modelo.
 * Pré-requisitos de console (feitos em 2026-10-03): `aiplatform.googleapis.com`
 * ativada; o papel vem da service account padrão do projeto.
 *
 * A região do modelo é independente da região da Function: `global` roteia
 * para onde o modelo está, com a Function em `southamerica-east1` — LGPD não
 * exige residência, exige processamento lícito, e o processador é o mesmo.
 *
 * **No emulador, o classificador é de mentira** — determinístico, dirigido
 * por marcadores no texto (`[[grave:ameaca]]`). Não é o padrão FCM da casa
 * (lá o emulador fala com o serviço real): o FCM responde de graça a token
 * inválido; aqui cada chamada custa e exige credencial que o emulador não
 * tem. Produção nunca define `FUNCTIONS_EMULATOR`/`FIRESTORE_EMULATOR_HOST`,
 * então o falso é inalcançável fora do teste.
 *
 * Contrato de saída (quem consome é `veredito.js`):
 *   { categorias: [{categoria, confianca}] }  resposta normal
 *   { bloqueio: '<razão>' }                   o Vertex recusou a entrada
 *   { invalida: true }                        respondeu fora da forma
 * Falha de transporte (rede, quota, auth) **lança** — o retry da plataforma
 * é quem re-tenta, e remover por falha nunca acontece porque a decisão nem
 * chega a existir.
 */

import { GoogleGenAI } from '@google/genai';

import { bucket } from './firebase.js';
import { AMBIGUAS, GRAVES } from './veredito.js';

const MODELO = 'gemini-2.5-flash-lite';

const EMULADO = process.env.FUNCTIONS_EMULATOR === 'true'
  || Boolean(process.env.FIRESTORE_EMULATOR_HOST);

/**
 * As definições que o modelo recebe — em pt-BR, como o conteúdo que julga.
 * `sexual-explicito` é o teor adulto; envolvendo menores é SEMPRE
 * `sexual-menores`, e a instrução diz isso com todas as letras porque é a
 * fronteira que não pode borrar.
 */
const INSTRUCAO = `Você é o filtro de moderação de um app brasileiro de
entregadores com um mural social. Analise a publicação (texto e, quando
houver, imagem) e aponte APENAS as categorias presentes, com a confiança:

- "sexual-menores": qualquer teor sexual envolvendo menores de idade, ou
  aliciamento de menores. Envolvendo menores é sempre esta categoria, nunca
  "sexual-explicito".
- "ameaca": ameaça direta de violência contra pessoa ou grupo.
- "racismo": racismo ou ofensa discriminatória (raça, origem, religião,
  orientação sexual). Gíria pesada ou palavrão SEM alvo discriminatório não é.
- "golpe": esquema para enganar e tomar dinheiro (pirâmide, phishing,
  falso emprego).
- "sexual-explicito": teor sexual explícito entre adultos.

Publicação limpa = lista vazia. Não invente categoria fora da lista.`;

const SCHEMA = {
  type: 'OBJECT',
  properties: {
    categorias: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          categoria: { type: 'STRING', enum: [...GRAVES, ...AMBIGUAS] },
          confianca: { type: 'NUMBER' },
        },
        required: ['categoria', 'confianca'],
      },
    },
  },
  required: ['categorias'],
};

/**
 * `BLOCK_NONE` nas quatro categorias configuráveis, e não é contradição: o
 * classificador precisa VER o conteúdo hostil para julgá-lo — um filtro que
 * desmaia diante do que veio julgar não julga nada. O bloqueio que sobra é o
 * irredutível do Google (`PROHIBITED_CONTENT`), e esse virou sinal: é o
 * filtro de maior precisão da casa disparando sobre a pior categoria.
 */
const SEGURANCA = [
  'HARM_CATEGORY_HARASSMENT',
  'HARM_CATEGORY_HATE_SPEECH',
  'HARM_CATEGORY_SEXUALLY_EXPLICIT',
  'HARM_CATEGORY_DANGEROUS_CONTENT',
].map((category) => ({ category, threshold: 'BLOCK_NONE' }));

let cliente;
function genai() {
  cliente ??= new GoogleGenAI({
    vertexai: true,
    project: process.env.GCLOUD_PROJECT ?? 'iter-mn',
    location: 'global',
  });
  return cliente;
}

/**
 * Classifica `{ texto, imagePath }`. A imagem é baixada aqui — e não em
 * `moderacao.js` — porque o download só existe para o classificador real:
 * o de mentira ignora, e o emulador não exercita um caminho que não usaria.
 */
export async function classificar({ texto, imagePath = null }) {
  if (EMULADO) return classificarDeMentira(texto);

  const parts = [{ text: texto || '(publicação sem texto)' }];

  if (imagePath) {
    const arquivo = bucket().file(imagePath);
    // `exists` e não try/catch no download: autor pode ter apagado a foto
    // entre o post e a análise — segue só com o texto. Qualquer outra falha
    // (rede, permissão) lança, e o retry re-tenta com a foto no lugar.
    const [existe] = await arquivo.exists();
    if (existe) {
      const [meta] = await arquivo.getMetadata();
      const [bytes] = await arquivo.download();
      parts.push({
        inlineData: {
          mimeType: meta.contentType ?? 'image/jpeg',
          data: bytes.toString('base64'),
        },
      });
    }
  }

  const resposta = await genai().models.generateContent({
    model: MODELO,
    contents: [{ role: 'user', parts }],
    config: {
      systemInstruction: INSTRUCAO,
      temperature: 0,
      responseMimeType: 'application/json',
      responseSchema: SCHEMA,
      safetySettings: SEGURANCA,
    },
  });

  const bloqueio = resposta?.promptFeedback?.blockReason;
  if (bloqueio) return { bloqueio };

  const fim = resposta?.candidates?.[0]?.finishReason;
  if (fim === 'PROHIBITED_CONTENT' || fim === 'SAFETY' || fim === 'BLOCKLIST') {
    return { bloqueio: fim };
  }

  try {
    const corpo = JSON.parse(resposta.text);
    if (!Array.isArray(corpo?.categorias)) return { invalida: true };
    return { categorias: corpo.categorias };
  } catch {
    return { invalida: true };
  }
}

/**
 * O classificador do emulador: lê a decisão de um marcador no texto.
 *
 *   [[grave:ameaca]]      grave com confiança acima do corte
 *   [[fraco:ameaca]]      grave ABAIXO do corte — tem de virar denúncia
 *   [[suspeito:racismo]]  ambígua com confiança alta — denúncia mesmo assim
 *   [[bloqueado]]         PROHIBITED_CONTENT — remove
 *   [[bloqueado:safety]]  bloqueio genérico — denúncia
 *   [[invalido]]          resposta fora da forma
 *   [[erro]]              transporte caiu: LANÇA, e o post fica de pé
 *   (sem marcador)        publicação limpa
 */
function classificarDeMentira(texto) {
  const m = (texto ?? '').match(/\[\[([a-z-]+)(?::([a-z-]+))?\]\]/);
  if (!m) return { categorias: [] };
  const [, tipo, detalhe] = m;
  switch (tipo) {
    case 'grave': return { categorias: [{ categoria: detalhe, confianca: 0.95 }] };
    case 'fraco': return { categorias: [{ categoria: detalhe, confianca: 0.6 }] };
    case 'suspeito': return { categorias: [{ categoria: detalhe, confianca: 0.9 }] };
    case 'bloqueado':
      return { bloqueio: detalhe === 'safety' ? 'SAFETY' : 'PROHIBITED_CONTENT' };
    case 'invalido': return { invalida: true };
    case 'erro': throw new Error('classificador de mentira: fora do ar');
    default: return { categorias: [] };
  }
}
