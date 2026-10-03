// Painel de moderação — ver docs/specs/painel-admin.md.
//
// Nenhuma checagem de "é admin" vive aqui, de propósito: quem decide é o
// `isAdmin()` do firestore.rules. A página só tenta ler a fila, e
// `permission-denied` vira "esta conta não tem acesso" — uma frase DIFERENTE
// de "fila vazia" e de "sem rede", pela mesma razão de o app não colapsar o
// null do getWeather em céu limpo.
//
// Todo texto denunciado entra no DOM por `textContent`, nunca por innerHTML:
// conteúdo denunciado é, por definição, o texto mais hostil do app.

import { initializeApp } from 'https://www.gstatic.com/firebasejs/12.3.0/firebase-app.js'
import {
  getAuth, GoogleAuthProvider, onAuthStateChanged,
  signInWithPopup, signInWithRedirect, signOut,
} from 'https://www.gstatic.com/firebasejs/12.3.0/firebase-auth.js'
import {
  getFirestore, collection, doc, getDoc, getDocs,
  writeBatch, setDoc, serverTimestamp,
} from 'https://www.gstatic.com/firebasejs/12.3.0/firebase-firestore.js'
import {
  getStorage, ref, getDownloadURL, deleteObject,
} from 'https://www.gstatic.com/firebasejs/12.3.0/firebase-storage.js'

// Config público por desenho (identifica o projeto, não autentica ninguém);
// gerado por `firebase apps:sdkconfig WEB`.
const app = initializeApp({
  apiKey: 'AIzaSyBlVm2bfbJS3WEA1VeOFjqtoBZy3FLfvVs',
  authDomain: 'iter-mn.firebaseapp.com',
  projectId: 'iter-mn',
  storageBucket: 'iter-mn.firebasestorage.app',
  messagingSenderId: '87511151381',
  appId: '1:87511151381:web:336e4e82ab8d469d6d6f1c',
})
const auth = getAuth(app)
const db = getFirestore(app)
const storage = getStorage(app)

const MOTIVOS = {
  spam: 'Spam',
  ofensa: 'Ofensa',
  improprio: 'Conteúdo impróprio',
  golpe: 'Golpe',
  outro: 'Outro',
  // Os motivos da moderação automática (`reports/{alvo}__maquina`).
  'sexual-menores': 'Teor sexual com menores',
  'ameaca': 'Ameaça',
  'racismo': 'Racismo',
  'sexual-explicito': 'Teor sexual explícito',
  'bloqueado-pelo-filtro': 'Bloqueado pelo filtro do Google',
  'resposta-invalida': 'Classificador respondeu fora da forma',
}

const secoes = ['entrar', 'carregando', 'sem-acesso', 'erro', 'vazio']
const $ = (id) => document.getElementById(id)

function mostrar(qual) {
  for (const id of secoes) $(id).classList.toggle('oculto', id !== qual)
  if (qual !== null && qual !== 'vazio') $('fila').replaceChildren()
}

$('botao-entrar').addEventListener('click', async () => {
  const provider = new GoogleAuthProvider()
  try {
    await signInWithPopup(auth, provider)
  } catch (e) {
    // Safari no iPhone bloqueia popup com frequência; o redirect cobre.
    if (e.code === 'auth/popup-blocked' || e.code === 'auth/popup-closed-by-user') {
      await signInWithRedirect(auth, provider)
    }
  }
})
$('sair').addEventListener('click', () => signOut(auth))
$('tentar-de-novo').addEventListener('click', () => carregarFila())

onAuthStateChanged(auth, (user) => {
  $('sair').classList.toggle('oculto', !user)
  if (!user) mostrar('entrar')
  else carregarFila()
})

// ── A fila ──────────────────────────────────────────────────────────────
//
// Pendente = `reports` menos os alvos com baixa em `moderation`. O id da
// denúncia é `{alvo}__{quem denunciou}`, e o agrupamento é por alvo: três
// denúncias do mesmo post são um cartão e uma decisão.

function parseAlvo(alvo) {
  if (alvo.startsWith('p_')) return { tipo: 'post', postId: alvo.slice(2) }
  const resto = alvo.slice(2)
  const corte = resto.indexOf('_') // ids de post não contêm `_`: o primeiro separa
  return { tipo: 'comentario', postId: resto.slice(0, corte), commentId: resto.slice(corte + 1) }
}

async function carregarFila() {
  mostrar('carregando')
  let denuncias, baixas
  try {
    ;[denuncias, baixas] = await Promise.all([
      getDocs(collection(db, 'reports')),
      getDocs(collection(db, 'moderation')),
    ])
  } catch (e) {
    mostrar(e.code === 'permission-denied' ? 'sem-acesso' : 'erro')
    return
  }

  const tratados = new Set(baixas.docs.map((d) => d.id))
  const porAlvo = new Map()
  for (const d of denuncias.docs) {
    const corte = d.id.lastIndexOf('__')
    if (corte < 0) continue
    const alvo = d.id.slice(0, corte)
    if (tratados.has(alvo)) continue
    if (!porAlvo.has(alvo)) porAlvo.set(alvo, [])
    porAlvo.get(alvo).push(d.data())
  }

  if (porAlvo.size === 0) {
    mostrar('vazio')
    return
  }

  // Denúncia mais recente primeiro — a fila é curta, ordenar no cliente.
  const milis = (at) => { try { return at.toMillis() } catch { return 0 } }
  const ordenados = [...porAlvo.entries()].sort(
    (a, b) => Math.max(...b[1].map((d) => milis(d.at)))
            - Math.max(...a[1].map((d) => milis(d.at))),
  )

  mostrar(null)
  const fila = $('fila')
  fila.replaceChildren()
  for (const [alvo, lista] of ordenados) {
    fila.appendChild(await cartao(alvo, lista))
  }
}

// ── Um cartão por alvo ──────────────────────────────────────────────────

function el(tag, className, texto) {
  const n = document.createElement(tag)
  if (className) n.className = className
  if (texto !== undefined) n.textContent = texto
  return n
}

function quando(at) {
  try {
    return at.toDate().toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' })
  } catch {
    return ''
  }
}

async function cartao(alvo, denuncias) {
  const info = parseAlvo(alvo)
  const card = el('section', 'cartao')
  card.appendChild(el('h2', null, info.tipo === 'post' ? 'Post denunciado' : 'Comentário denunciado'))

  const selos = el('p')
  for (const d of denuncias) {
    // A denúncia da máquina se distingue da humana no selo — e diz se ela
    // removeu ou só sinalizou, que é a diferença entre revisar um ato e
    // decidir um.
    const prefixo = d.uid === 'maquina'
      ? (d.removeu ? 'Automática (removeu): ' : 'Automática: ')
      : ''
    selos.appendChild(el('span', 'selo', `${prefixo}${MOTIVOS[d.reason] ?? d.reason} · ${quando(d.at)}`))
  }
  card.appendChild(selos)

  // O alvo: post sempre (é o contexto), comentário quando for o caso.
  const postSnap = await getDoc(doc(db, 'posts', info.postId)).catch(() => null)
  const post = postSnap?.exists() ? postSnap.data() : null
  let comentario = null
  if (info.tipo === 'comentario') {
    const c = await getDoc(doc(db, 'posts', info.postId, 'comments', info.commentId)).catch(() => null)
    comentario = c?.exists() ? c.data() : null
  }

  const autorUid = info.tipo === 'post' ? post?.uid : comentario?.uid
  const jaResolvido = info.tipo === 'post' ? (post == null || post.deleted === true) : comentario == null

  if (jaResolvido) {
    card.appendChild(el('p', 'suave', info.tipo === 'post'
      ? 'O post já foi removido (pelo autor ou pela moderação). Falta só a baixa.'
      : 'O comentário já foi apagado. Falta só a baixa.'))

    // Se foi a máquina que removeu, o original está em quarentena — e o
    // julgamento dela se revisa olhando o que ela viu, não a lápide.
    const q = await getDoc(doc(db, 'quarentena', alvo)).catch(() => null)
    if (q?.exists()) {
      const dadosQ = q.data()
      card.appendChild(el('p', 'suave',
        `Original em quarentena (categorias: ${(dadosQ.categorias ?? []).join(', ')}):`))
      const conteudoQ = el('div', 'conteudo', dadosQ.texto ?? '')
      if (dadosQ.imagePathQuarentena) {
        try {
          const img = document.createElement('img')
          img.src = await getDownloadURL(ref(storage, dadosQ.imagePathQuarentena))
          img.alt = 'Imagem em quarentena'
          conteudoQ.appendChild(img)
        } catch { /* sem a imagem o texto ainda julga */ }
      }
      card.appendChild(conteudoQ)
    }
  } else {
    if (autorUid) {
      const perfil = await getDoc(doc(db, 'profiles', autorUid)).catch(() => null)
      const p = perfil?.exists() ? perfil.data() : null
      card.appendChild(el('p', 'suave', p
        ? `Autor: ${p.name}${p.nickName ? ' · @' + p.nickName : ''}`
        : 'Autor: conta sem perfil (possivelmente excluída)'))
    }

    const conteudo = el('div', 'conteudo', info.tipo === 'post' ? post.text : comentario.text)
    if (info.tipo === 'post' && post.imagePath) {
      try {
        const img = document.createElement('img')
        img.src = await getDownloadURL(ref(storage, post.imagePath))
        img.alt = 'Imagem do post'
        conteudo.appendChild(img)
      } catch { /* sem a imagem o texto ainda julga */ }
    }
    card.appendChild(conteudo)

    if (info.tipo === 'comentario' && post?.text) {
      card.appendChild(el('p', 'suave', `No post: "${post.text.slice(0, 120)}"`))
    }
  }

  const acoes = el('div', 'acoes')
  const btnRemover = el('button', 'perigo', jaResolvido ? 'Dar baixa como removido' : 'Remover')
  const btnIgnorar = el('button', null, 'Ignorar')
  const aviso = el('p', 'suave oculto', '')
  acoes.append(btnRemover, btnIgnorar)
  card.append(acoes, aviso)

  const resolver = async (acao) => {
    btnRemover.disabled = btnIgnorar.disabled = true
    try {
      if (acao === 'removido') await remover(info, alvo, post, comentario)
      else await setDoc(doc(db, 'moderation', alvo), { resolution: 'ignorado', at: serverTimestamp() })
      card.remove()
      if (!$('fila').hasChildNodes()) mostrar('vazio')
    } catch (e) {
      btnRemover.disabled = btnIgnorar.disabled = false
      aviso.textContent = `Não deu: ${e.code ?? e.message}. Tente de novo.`
      aviso.classList.remove('oculto')
    }
  }
  btnRemover.addEventListener('click', () => resolver('removido'))
  btnIgnorar.addEventListener('click', () => resolver('ignorado'))

  return card
}

// Remover = a MESMA lápide que PostController.erase grava, mais a baixa, num
// batch só — a regra confere a forma; errar aqui é permission-denied, não um
// documento torto. A foto sai do Storage depois do commit, em melhor
// esforço: sem referência no documento, o pior caso é um objeto órfão.
async function remover(info, alvo, post, comentario) {
  const batch = writeBatch(db)
  const imagePath = info.tipo === 'post' ? post?.imagePath : null

  if (info.tipo === 'post') {
    if (post && post.deleted !== true) {
      batch.update(doc(db, 'posts', info.postId), { deleted: true, text: '', imagePath: null })
    }
  } else if (comentario) {
    batch.delete(doc(db, 'posts', info.postId, 'comments', info.commentId))
  }
  batch.set(doc(db, 'moderation', alvo), { resolution: 'removido', at: serverTimestamp() })
  await batch.commit()

  if (imagePath) {
    try { await deleteObject(ref(storage, imagePath)) } catch { /* órfão inofensivo */ }
  }
}
