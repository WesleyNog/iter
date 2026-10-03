// Testes das regras de `firestore.rules`, rodando contra o emulador.
//
// Existe porque Amigos é a primeira feature do app em que uma regra errada
// vaza **dado de terceiro**, e não um número torto. O simulador do console foi
// removido pelo Google, e ele não testava batch de qualquer forma — que é
// justamente onde mora o `existsAfter` do aceite.
//
// Rodar: `npm test` dentro de `firestore-tests/`.

import { after, before, describe, it } from 'node:test'
import assert from 'node:assert/strict'
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing'
import { readFileSync } from 'node:fs'
import { createHash } from 'node:crypto'
import {
  doc,
  collection,
  getDoc,
  getDocs,
  setDoc,
  deleteDoc,
  writeBatch,
  updateDoc,
  serverTimestamp,
} from 'firebase/firestore'

const ANA = 'uid-ana'
const BIA = 'uid-bia'
const ZECA = 'uid-zeca'

// As regras são lidas uma vez e o uid do admin sai do literal de `isAdmin()`
// no próprio arquivo: a fonte é uma só, então trocar o uid lá (ou um clone
// rodar com o placeholder) não dessincroniza este teste — ele testa o que
// está escrito, seja lá o que for.
const REGRAS = readFileSync('../firestore.rules', 'utf8')
const ADMIN = REGRAS.match(/function isAdmin\(\)[\s\S]*?==\s*'([^']+)'/)[1]

let env
let ana
let bia
let zeca
let admin

/** O corpo que a regra aceita: só `at`, e preso a `request.time`. */
const stamp = () => ({ at: serverTimestamp() })

const perfil = (uid, nickName) => ({
  uid,
  name: 'Fulano',
  nickName,
  photoUrl: null,
  updatedAt: '2026-08-07T10:00:00.000',
})

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'iter-mn',
    firestore: {
      rules: REGRAS,
      host: '127.0.0.1',
      port: 8080,
    },
  })

  ana = env.authenticatedContext(ANA).firestore()
  bia = env.authenticatedContext(BIA).firestore()
  zeca = env.authenticatedContext(ZECA).firestore()
  admin = env.authenticatedContext(ADMIN).firestore()
})

after(async () => {
  await env.cleanup()
})

/** Estado inicial: três perfis publicados e as reservas de apelido. */
async function seed() {
  await env.clearFirestore()
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore()
    for (const [uid, nick] of [
      [ANA, 'ana.a1'],
      [BIA, 'bia.b2'],
      [ZECA, 'zeca.z3'],
    ]) {
      await setDoc(doc(db, 'nicknames', nick), { uid })
      await setDoc(doc(db, 'profiles', uid), perfil(uid, nick))
      await setDoc(doc(db, 'profiles', uid, 'stats', 'all'), { routes: 10 })
      await setDoc(doc(db, 'user', uid), { id: uid, cpf: '00000000000' })
    }
  })
}

/** Ana convida Bia, como o `FriendController.invite` faz. */
async function convite() {
  const batch = writeBatch(ana)
  batch.set(doc(ana, 'friendRequests', BIA, 'incoming', ANA), stamp())
  batch.set(doc(ana, 'friendRequests', ANA, 'outgoing', BIA), stamp())
  await batch.commit()
}

describe('leitura pública — o que qualquer autenticado alcança', () => {
  before(seed)

  it('lê o perfil de alguém por id', async () => {
    await assertSucceeds(getDoc(doc(bia, 'profiles', ANA)))
  })

  it('lê os PRÓPRIOS números de carreira', async () => {
    await assertSucceeds(getDoc(doc(ana, 'profiles', ANA, 'stats', 'all')))
  })

  it('NÃO lê os números de quem não é amigo', async () => {
    // A vitrine é pública porque responde "é essa a pessoa?". Rotas,
    // insucesso e tempo médio não respondem a isso — e o Feed, sendo mural
    // global, entrega uid a quem rolar a tela.
    await assertFails(getDoc(doc(bia, 'profiles', ANA, 'stats', 'all')))
    await assertFails(getDoc(doc(bia, 'profiles', ANA, 'stats', '2026-08')))
  })

  it('lê os números de quem é amigo', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore()
      await setDoc(doc(db, 'friends', ANA, 'list', BIA), { at: new Date() })
      await setDoc(doc(db, 'friends', BIA, 'list', ANA), { at: new Date() })
    })

    await assertSucceeds(getDoc(doc(bia, 'profiles', ANA, 'stats', 'all')))
    await assertSucceeds(getDoc(doc(bia, 'profiles', ANA, 'stats', '2026-08')))
    // E continua fechado para quem está de fora da amizade dos dois.
    await assertFails(getDoc(doc(zeca, 'profiles', ANA, 'stats', 'all')))
  })

  it('NÃO lista a coleção de perfis', async () => {
    // `read` seria `get` + `list`, e `list` aqui entregaria o cadastro
    // inteiro do app numa chamada.
    await assertFails(getDocs(collection(bia, 'profiles')))
  })

  it('NÃO lista a coleção de apelidos', async () => {
    // Estava aberto em produção até esta entrega: devolvia o mapa completo
    // apelido -> uid, que é o que torna a enumeração de perfis barata.
    await assertFails(getDocs(collection(bia, 'nicknames')))
  })

  it('resolve um apelido por id', async () => {
    await assertSucceeds(getDoc(doc(bia, 'nicknames', 'ana.a1')))
  })

  it('NÃO lê o documento privado de outro — é onde mora o CPF', async () => {
    await assertFails(getDoc(doc(bia, 'user', ANA)))
  })
})

describe('projeção pública — o que o dono pode gravar', () => {
  before(seed)

  it('publica o próprio perfil', async () => {
    await assertSucceeds(
      setDoc(doc(ana, 'profiles', ANA), perfil(ANA, 'ana.a1')),
    )
  })

  it('NÃO grava CPF na projeção', async () => {
    // O `hasOnly` é o que transforma "nunca gravar CPF aqui" de convenção em
    // invariante: nenhum publish futuro vaza um campo por descuido.
    await assertFails(
      setDoc(doc(ana, 'profiles', ANA), {
        ...perfil(ANA, 'ana.a1'),
        cpf: '00000000000',
      }),
    )
  })

  it('NÃO publica com o apelido de outra pessoa', async () => {
    await assertFails(
      setDoc(doc(ana, 'profiles', ANA), perfil(ANA, 'bia.b2')),
    )
  })

  it('NÃO escreve na projeção alheia', async () => {
    await assertFails(
      setDoc(doc(bia, 'profiles', ANA), perfil(ANA, 'ana.a1')),
    )
  })

  it('NÃO grava balde de mês com nome inventado', async () => {
    await assertFails(
      setDoc(doc(ana, 'profiles', ANA, 'stats', 'lixo'), { routes: 1 }),
    )
    await assertSucceeds(
      setDoc(doc(ana, 'profiles', ANA, 'stats', '2026-08'), { routes: 1 }),
    )
  })
})

describe('convite — ninguém forja consentimento', () => {
  before(seed)

  it('Ana convida Bia', async () => {
    await assertSucceeds(convite())
  })

  it('Bia vê o convite na própria caixa', async () => {
    await assertSucceeds(getDocs(collection(bia, 'friendRequests', BIA, 'incoming')))
  })

  it('NÃO lê a caixa de convites alheia', async () => {
    await assertFails(getDocs(collection(zeca, 'friendRequests', BIA, 'incoming')))
  })

  it('NÃO forja um convite "de" outra pessoa', async () => {
    // Zeca tentando criar um convite que pareça vir da Ana. É esta
    // impossibilidade que sustenta toda a regra de `friends`.
    await assertFails(
      setDoc(doc(zeca, 'friendRequests', BIA, 'incoming', ANA), stamp()),
    )
  })

  it('NÃO convida a si mesmo', async () => {
    await assertFails(
      setDoc(doc(ana, 'friendRequests', ANA, 'incoming', ANA), stamp()),
    )
  })

  it('NÃO convida quem não tem perfil publicado', async () => {
    await assertFails(
      setDoc(doc(ana, 'friendRequests', 'uid-fantasma', 'incoming', ANA), stamp()),
    )
  })

  it('NÃO convida SEM ter perfil publicado', async () => {
    // A outra ponta da mesma regra, e é a que o usuário sentiu no aparelho:
    // sem o perfil de quem envia, o convite chega como "Entregador" e não dá
    // para aceitar nem recusar com conhecimento de causa.
    const semPerfil = env.authenticatedContext('uid-sem-perfil').firestore()
    await assertFails(
      setDoc(
        doc(semPerfil, 'friendRequests', ANA, 'incoming', 'uid-sem-perfil'),
        stamp(),
      ),
    )
  })

  it('NÃO carimba o convite com hora escolhida a dedo', async () => {
    await assertFails(
      setDoc(doc(ana, 'friendRequests', BIA, 'incoming', ANA), {
        at: new Date('2099-12-31'),
      }),
    )
  })
})

describe('aceite — o caso que nenhum simulador testava', () => {
  before(async () => {
    await seed()
    await convite()
  })

  it('NÃO cria só uma das arestas', async () => {
    // O `existsAfter` exige a irmã no mesmo commit. Sem isso, quem aceita
    // poderia gravar meia amizade.
    await assertFails(setDoc(doc(bia, 'friends', BIA, 'list', ANA), stamp()))
  })

  it('aceita com as duas arestas no mesmo batch', async () => {
    const batch = writeBatch(bia)
    batch.set(doc(bia, 'friends', BIA, 'list', ANA), stamp())
    batch.set(doc(bia, 'friends', ANA, 'list', BIA), stamp())
    batch.delete(doc(bia, 'friendRequests', BIA, 'incoming', ANA))
    batch.delete(doc(bia, 'friendRequests', ANA, 'outgoing', BIA))
    batch.delete(doc(bia, 'friendRequests', ANA, 'incoming', BIA))
    batch.delete(doc(bia, 'friendRequests', BIA, 'outgoing', ANA))

    await assertSucceeds(batch.commit())
  })

  it('as duas listas ficaram com a aresta', async () => {
    const daAna = await getDoc(doc(ana, 'friends', ANA, 'list', BIA))
    const daBia = await getDoc(doc(bia, 'friends', BIA, 'list', ANA))
    assert.equal(daAna.exists(), true)
    assert.equal(daBia.exists(), true)
  })

  it('NÃO lê a lista de amigos alheia', async () => {
    await assertFails(getDocs(collection(zeca, 'friends', ANA, 'list')))
  })
})

describe('ataques que têm de falhar', () => {
  before(seed)

  it('NÃO me insiro na lista de quem nunca me convidou', async () => {
    const batch = writeBatch(zeca)
    batch.set(doc(zeca, 'friends', ANA, 'list', ZECA), stamp())
    batch.set(doc(zeca, 'friends', ZECA, 'list', ANA), stamp())
    await assertFails(batch.commit())
  })

  it('NÃO adiciono alguém à minha lista sem ele aceitar', async () => {
    // Precisaria de um convite `incoming` vindo da vítima, que só ela cria.
    const batch = writeBatch(zeca)
    batch.set(doc(zeca, 'friends', ZECA, 'list', ANA), stamp())
    batch.set(doc(zeca, 'friends', ANA, 'list', ZECA), stamp())
    await assertFails(batch.commit())
  })

  it('convite fantasma não basta: o marcador tem de ser do par certo', async () => {
    // Zeca cria o próprio `outgoing` para Ana (é documento dele, passa) e
    // tenta usá-lo para se inserir na lista dela.
    await setDoc(doc(zeca, 'friendRequests', ZECA, 'outgoing', ANA), stamp())

    const batch = writeBatch(zeca)
    batch.set(doc(zeca, 'friends', ANA, 'list', ZECA), stamp())
    batch.set(doc(zeca, 'friends', ZECA, 'list', ANA), stamp())
    await assertFails(batch.commit())
  })

  it('NÃO viro amigo de mim mesmo', async () => {
    await assertFails(setDoc(doc(ana, 'friends', ANA, 'list', ANA), stamp()))
  })
})

describe('feed — o mural é a coleção mais exposta, e a mais validada', () => {
  const post = (uid, extra = {}) => ({
    uid,
    text: 'Dia puxado no galpão',
    createdAt: serverTimestamp(),
    deleted: false,
    ...extra,
  })

  before(seed)

  it('publico um post meu', async () => {
    await assertSucceeds(setDoc(doc(ana, 'posts', 'p1'), post(ANA)))
  })

  it('qualquer autenticado lê o mural', async () => {
    await assertSucceeds(getDocs(collection(zeca, 'posts')))
  })

  it('NÃO publico assinando como outro', async () => {
    await assertFails(setDoc(doc(bia, 'posts', 'p2'), post(ANA)))
  })

  it('NÃO carimbo o post com data futura', async () => {
    // O ataque que a regra de `friends.at` já fechava: ordenar por dado do
    // adversário. Num mural global, um post de 9999 lidera para sempre.
    await assertFails(
      setDoc(doc(ana, 'posts', 'p3'), {
        ...post(ANA),
        createdAt: new Date('9999-12-31'),
      }),
    )
  })

  it('NÃO invento campo no post', async () => {
    await assertFails(
      setDoc(doc(ana, 'posts', 'p4'), { ...post(ANA), nickName: 'bia.b2' }),
    )
  })

  it('NÃO gravo texto acima do teto', async () => {
    await assertFails(
      setDoc(doc(ana, 'posts', 'p5'), { ...post(ANA), text: 'x'.repeat(501) }),
    )
  })

  it('NÃO aponto para a imagem de outra pessoa', async () => {
    await assertFails(
      setDoc(doc(ana, 'posts', 'p6'), {
        ...post(ANA, { imagePath: `posts/${BIA}/foto.jpg` }),
      }),
    )
    await assertSucceeds(
      setDoc(doc(ana, 'posts', 'p7'), {
        ...post(ANA, { imagePath: `posts/${ANA}/foto.jpg` }),
      }),
    )
  })

  it('NÃO invento empresa fora do enum', async () => {
    await assertFails(
      setDoc(doc(ana, 'posts', 'p8'), { ...post(ANA), company: 'ifood' }),
    )
    await assertSucceeds(
      setDoc(doc(ana, 'posts', 'p9'), { ...post(ANA), company: 'shopee' }),
    )
  })

  it('apagar é marcar, e delete de verdade é negado', async () => {
    await assertFails(deleteDoc(doc(ana, 'posts', 'p1')))
    await assertSucceeds(
      updateDoc(doc(ana, 'posts', 'p1'), {
        deleted: true,
        text: '',
        imagePath: null,
      }),
    )
  })

  it('NÃO edito o texto sem apagar, nem o post do outro', async () => {
    await assertFails(updateDoc(doc(ana, 'posts', 'p9'), { text: 'outro' }))
    await assertFails(updateDoc(doc(bia, 'posts', 'p9'), { deleted: true }))
  })

  it('curtir e descurtir o post de alguém', async () => {
    await assertSucceeds(
      setDoc(doc(bia, 'posts', 'p9', 'likes', BIA), {
        uid: BIA,
        at: serverTimestamp(),
      }),
    )
    await assertSucceeds(deleteDoc(doc(bia, 'posts', 'p9', 'likes', BIA)))
  })

  it('NÃO curto em nome de outro nem descurto a curtida alheia', async () => {
    await assertFails(
      setDoc(doc(bia, 'posts', 'p9', 'likes', ANA), {
        uid: ANA,
        at: serverTimestamp(),
      }),
    )

    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'posts', 'p9', 'likes', ANA), {
        uid: ANA,
        at: new Date(),
      })
    })
    await assertFails(deleteDoc(doc(bia, 'posts', 'p9', 'likes', ANA)))
  })

  it('NÃO curto um post que não existe', async () => {
    // Sem o `exists` no pai, `posts/<id-inventado>/likes/*` vira depósito
    // permanente e cobrado que nenhum delete alcança.
    await assertFails(
      setDoc(doc(bia, 'posts', 'nao-existe', 'likes', BIA), {
        uid: BIA,
        at: serverTimestamp(),
      }),
    )
  })

  it('o espelho é só do dono', async () => {
    await assertSucceeds(
      setDoc(doc(ana, 'iter', ANA, 'posts', 'p1'), post(ANA)),
    )
    await assertFails(getDoc(doc(bia, 'iter', ANA, 'posts', 'p1')))
  })

  it('a lápide não vira porta dos fundos do create', async () => {
    // `affectedKeys` diz QUAIS chaves mudaram, nunca o valor delas. Sem prender
    // a forma, um post de 10 caracteres virava 1 MiB permanente — `delete` é
    // `false` — numa coleção com `list` aberto; e o `imagePath` escapava do
    // prefixo `^posts/{meu uid}/` que só o `create` exigia, passando a apontar
    // para a foto de outra pessoa no Storage.
    await assertSucceeds(setDoc(doc(ana, 'posts', 'p20'), post(ANA)))

    await assertFails(
      updateDoc(doc(ana, 'posts', 'p20'), {
        deleted: true,
        text: 'x'.repeat(1000),
        imagePath: null,
      }),
    )
    await assertFails(
      updateDoc(doc(ana, 'posts', 'p20'), {
        deleted: true,
        text: '',
        imagePath: `posts/${BIA}/foto.jpg`,
      }),
    )

    // A forma exata que `PostController.erase` grava continua passando.
    await assertSucceeds(
      updateDoc(doc(ana, 'posts', 'p20'), {
        deleted: true,
        text: '',
        imagePath: null,
      }),
    )
  })

  it('NÃO escolho um id que torna o post imdenunciável', async () => {
    // O id entra no id da denúncia, e id de documento estoura em 1500 bytes:
    // sem teto, quem publica escolhe um id que impede qualquer denúncia sobre
    // o próprio post, para sempre. O `_` fica de fora porque é o separador do
    // id da denúncia.
    await assertFails(setDoc(doc(ana, 'posts', 'z'.repeat(200)), post(ANA)))
    await assertFails(setDoc(doc(ana, 'posts', 'com_underscore'), post(ANA)))
    await assertSucceeds(
      setDoc(doc(ana, 'posts', '9f8e7d6c-1234-4abc-9def-0123456789ab'), post(ANA)),
    )
  })

  it('post apagado não aceita curtida nem comentário novos', async () => {
    // Apagar é marcar, então `exists` continua verdadeiro — era por aí que a
    // thread de um post apagado seguia viva, aceitando texto e legível por
    // quem tivesse o id, enquanto sumia da tela do dono.
    await assertFails(
      setDoc(doc(bia, 'posts', 'p20', 'likes', BIA), {
        uid: BIA,
        at: serverTimestamp(),
      }),
    )
    await assertFails(
      setDoc(doc(bia, 'posts', 'p20', 'comments', 'c1'), {
        uid: BIA,
        text: 'ainda dá?',
        createdAt: serverTimestamp(),
      }),
    )
  })

  it('post antigo, sem o campo `deleted`, continua aceitando os dois', async () => {
    // `.get('deleted', false)` e não `.deleted`: chave ausente erra, e erro
    // nega. O acervo publicado antes de a regra exigir o campo viraria "não dá
    // para comentar", em silêncio.
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'posts', 'antigo'), {
        uid: ANA,
        text: 'sem o campo deleted',
        createdAt: new Date(),
      })
    })

    await assertSucceeds(
      setDoc(doc(bia, 'posts', 'antigo', 'likes', BIA), {
        uid: BIA,
        at: serverTimestamp(),
      }),
    )
    await assertSucceeds(
      setDoc(doc(bia, 'posts', 'antigo', 'comments', 'c1'), {
        uid: BIA,
        text: 'passa',
        createdAt: serverTimestamp(),
      }),
    )
  })
})

describe('desfazer', () => {
  before(async () => {
    await seed()
    await convite()
    const batch = writeBatch(bia)
    batch.set(doc(bia, 'friends', BIA, 'list', ANA), stamp())
    batch.set(doc(bia, 'friends', ANA, 'list', BIA), stamp())
    await batch.commit()
  })

  it('recuso um convite apagando o par', async () => {
    await assertSucceeds(
      deleteDoc(doc(bia, 'friendRequests', BIA, 'incoming', ANA)),
    )
    // Quem foi convidado também retira o marcador do outro lado.
    await assertSucceeds(
      deleteDoc(doc(bia, 'friendRequests', ANA, 'outgoing', BIA)),
    )
  })

  it('removo a mim mesmo da lista alheia', async () => {
    await assertSucceeds(deleteDoc(doc(bia, 'friends', ANA, 'list', BIA)))
  })

  it('removo alguém da minha lista', async () => {
    await assertSucceeds(deleteDoc(doc(bia, 'friends', BIA, 'list', ANA)))
  })

  it('NÃO mexo na amizade de dois terceiros', async () => {
    await assertFails(deleteDoc(doc(zeca, 'friends', ANA, 'list', BIA)))
  })
})

describe('bloqueio — a dívida que cabia numa regra', () => {
  before(seed)

  it('bloqueio alguém, e bloquear de novo não é erro', async () => {
    // `create, update` sob a mesma condição, como a aresta de amizade: o
    // segundo toque não pode virar permission-denied.
    await assertSucceeds(setDoc(doc(ana, 'blocks', ANA, 'list', BIA), stamp()))
    await assertSucceeds(setDoc(doc(ana, 'blocks', ANA, 'list', BIA), stamp()))
  })

  it('NÃO bloqueio em nome de outro', async () => {
    await assertFails(setDoc(doc(bia, 'blocks', ANA, 'list', ZECA), stamp()))
  })

  it('NÃO me bloqueio', async () => {
    await assertFails(setDoc(doc(ana, 'blocks', ANA, 'list', ANA), stamp()))
  })

  it('NÃO carimbo o bloqueio com hora escolhida a dedo', async () => {
    await assertFails(
      setDoc(doc(ana, 'blocks', ANA, 'list', ZECA), {
        at: new Date('9999-12-31'),
      }),
    )
  })

  it('NÃO leio a lista de bloqueio alheia — nem descubro que fui bloqueado', async () => {
    // O bloqueado não pode saber que foi bloqueado: o convite dele apenas
    // falha, como falharia sem rede.
    await assertFails(getDoc(doc(bia, 'blocks', ANA, 'list', BIA)))
    await assertFails(getDocs(collection(bia, 'blocks', ANA, 'list')))
    await assertSucceeds(getDocs(collection(ana, 'blocks', ANA, 'list')))
  })

  it('quem foi bloqueado NÃO convida', async () => {
    // Ana bloqueou Bia no primeiro caso deste bloco.
    const batch = writeBatch(bia)
    batch.set(doc(bia, 'friendRequests', ANA, 'incoming', BIA), stamp())
    batch.set(doc(bia, 'friendRequests', BIA, 'outgoing', ANA), stamp())
    await assertFails(batch.commit())
  })

  it('o marcador `outgoing` sozinho passa — e não informa nada', async () => {
    // A checagem de bloqueio mora só no `incoming`, de propósito: o batch é
    // atômico, então negar um lado nega o convite inteiro, e repetir a
    // condição no documento que mora no subtree de quem escreve criava um
    // oráculo silencioso — "negou, logo ela me bloqueou", sem rastro do lado
    // dela e repetível à vontade.
    await assertSucceeds(
      setDoc(doc(bia, 'friendRequests', BIA, 'outgoing', ANA), stamp()),
    )
    await assertSucceeds(
      deleteDoc(doc(bia, 'friendRequests', BIA, 'outgoing', ANA)),
    )
  })

  it('marcador `outgoing` solto NÃO vira amizade', async () => {
    // O que sustenta a assimetria acima: a aresta exige o `incoming` da
    // vítima, e só ela consegue criá-lo.
    await assertSucceeds(
      setDoc(doc(bia, 'friendRequests', BIA, 'outgoing', ANA), stamp()),
    )

    const batch = writeBatch(bia)
    batch.set(doc(bia, 'friends', BIA, 'list', ANA), stamp())
    batch.set(doc(bia, 'friends', ANA, 'list', BIA), stamp())
    await assertFails(batch.commit())

    await assertSucceeds(
      deleteDoc(doc(bia, 'friendRequests', BIA, 'outgoing', ANA)),
    )
  })

  it('quem bloqueou também não convida o bloqueado', async () => {
    // A condição vale nas duas direções de propósito: bloquear e convidar a
    // mesma pessoa é uma contradição, e o servidor não deve aceitá-la só
    // porque a tela não a oferece.
    const batch = writeBatch(ana)
    batch.set(doc(ana, 'friendRequests', BIA, 'incoming', ANA), stamp())
    batch.set(doc(ana, 'friendRequests', ANA, 'outgoing', BIA), stamp())
    await assertFails(batch.commit())
  })

  it('desbloquear devolve o convite', async () => {
    await assertSucceeds(deleteDoc(doc(ana, 'blocks', ANA, 'list', BIA)))

    const batch = writeBatch(bia)
    batch.set(doc(bia, 'friendRequests', ANA, 'incoming', BIA), stamp())
    batch.set(doc(bia, 'friendRequests', BIA, 'outgoing', ANA), stamp())
    await assertSucceeds(batch.commit())
  })

  it('bloquear apaga a amizade no mesmo commit', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore()
      await setDoc(doc(db, 'friends', ANA, 'list', BIA), { at: new Date() })
      await setDoc(doc(db, 'friends', BIA, 'list', ANA), { at: new Date() })
    })

    // Um marcador de convite vivo continua autorizando recriar a aresta: o
    // bloqueio tem de levar os quatro junto, senão a amizade ressuscita.
    const batch = writeBatch(ana)
    batch.set(doc(ana, 'blocks', ANA, 'list', BIA), stamp())
    batch.delete(doc(ana, 'friends', ANA, 'list', BIA))
    batch.delete(doc(ana, 'friends', BIA, 'list', ANA))
    batch.delete(doc(ana, 'friendRequests', ANA, 'incoming', BIA))
    batch.delete(doc(ana, 'friendRequests', BIA, 'outgoing', ANA))
    batch.delete(doc(ana, 'friendRequests', BIA, 'incoming', ANA))
    batch.delete(doc(ana, 'friendRequests', ANA, 'outgoing', BIA))
    await assertSucceeds(batch.commit())
  })
})

describe('comentário — texto livre embaixo do post de outro', () => {
  const comentario = (uid, extra = {}) => ({
    uid,
    text: 'Boa, parceiro!',
    createdAt: serverTimestamp(),
    ...extra,
  })

  before(async () => {
    await seed()
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore()
      await setDoc(doc(db, 'posts', 'p1'), {
        uid: ANA,
        text: 'Dia puxado',
        createdAt: new Date(),
        deleted: false,
      })
    })
  })

  it('comento no post de alguém', async () => {
    await assertSucceeds(
      setDoc(doc(bia, 'posts', 'p1', 'comments', 'c1'), comentario(BIA)),
    )
  })

  it('qualquer autenticado lê a thread — `list` é liberado aqui', async () => {
    // Ao contrário de `profiles` e `nicknames`: a subcoleção está sob um post,
    // então listar devolve aquele post e nada mais.
    await assertSucceeds(getDocs(collection(zeca, 'posts', 'p1', 'comments')))
  })

  it('NÃO comento assinando como outro', async () => {
    await assertFails(
      setDoc(doc(bia, 'posts', 'p1', 'comments', 'c2'), comentario(ANA)),
    )
  })

  it('NÃO comento vazio nem acima do teto', async () => {
    await assertFails(
      setDoc(
        doc(bia, 'posts', 'p1', 'comments', 'c3'),
        comentario(BIA, { text: '' }),
      ),
    )
    await assertFails(
      setDoc(
        doc(bia, 'posts', 'p1', 'comments', 'c4'),
        comentario(BIA, { text: 'x'.repeat(501) }),
      ),
    )
  })

  it('NÃO carimbo o comentário com data futura nem invento campo', async () => {
    await assertFails(
      setDoc(
        doc(bia, 'posts', 'p1', 'comments', 'c5'),
        comentario(BIA, { createdAt: new Date('9999-12-31') }),
      ),
    )
    await assertFails(
      setDoc(
        doc(bia, 'posts', 'p1', 'comments', 'c6'),
        comentario(BIA, { nickName: 'bia.b2' }),
      ),
    )
  })

  it('NÃO escolho um id de comentário fora do formato', async () => {
    // O id entra no id da denúncia (`c_{postId}_{commentId}__{quem}`): sem o
    // teto, o comentário fica imdenunciável para sempre; sem excluir o `_`, o
    // separador daquele id vira ambíguo.
    await assertFails(
      setDoc(
        doc(bia, 'posts', 'p1', 'comments', 'z'.repeat(200)),
        comentario(BIA),
      ),
    )
    await assertFails(
      setDoc(doc(bia, 'posts', 'p1', 'comments', 'com_under'), comentario(BIA)),
    )
  })

  it('NÃO comento em post que não existe', async () => {
    // Sem o `exists` no pai, `posts/<inventado>/comments/*` é depósito
    // permanente e cobrado que nenhum delete alcança — o ramo de moderação
    // erraria num post que nunca existiu.
    await assertFails(
      setDoc(doc(bia, 'posts', 'nao-existe', 'comments', 'c7'), comentario(BIA)),
    )
  })

  it('NÃO reescrevo comentário — nem o meu', async () => {
    await assertFails(
      updateDoc(doc(bia, 'posts', 'p1', 'comments', 'c1'), { text: 'outro' }),
    )
  })

  it('apago o meu comentário', async () => {
    await assertSucceeds(deleteDoc(doc(bia, 'posts', 'p1', 'comments', 'c1')))
  })

  it('o dono do post apaga qualquer comentário do próprio post', async () => {
    // Moderação sem servidor, e só funciona porque o post nunca é apagado de
    // verdade: com `delete` real o `get()` erraria, e erro em regra nega.
    await assertSucceeds(
      setDoc(doc(bia, 'posts', 'p1', 'comments', 'c8'), comentario(BIA)),
    )
    await assertSucceeds(deleteDoc(doc(ana, 'posts', 'p1', 'comments', 'c8')))
  })

  it('terceiro NÃO apaga comentário alheio', async () => {
    await assertSucceeds(
      setDoc(doc(bia, 'posts', 'p1', 'comments', 'c9'), comentario(BIA)),
    )
    await assertFails(deleteDoc(doc(zeca, 'posts', 'p1', 'comments', 'c9')))
  })

  it('bloqueado NÃO comenta no post de quem o bloqueou', async () => {
    // É esta linha que faz o bloqueio valer alguma coisa aqui: o filtro do
    // cliente some com o comentário na tela de quem bloqueou; sem a regra, ele
    // continua visível para todo mundo embaixo do post.
    await assertSucceeds(setDoc(doc(ana, 'blocks', ANA, 'list', ZECA), stamp()))
    await assertFails(
      setDoc(doc(zeca, 'posts', 'p1', 'comments', 'c10'), comentario(ZECA)),
    )

    await assertSucceeds(deleteDoc(doc(ana, 'blocks', ANA, 'list', ZECA)))
    await assertSucceeds(
      setDoc(doc(zeca, 'posts', 'p1', 'comments', 'c10'), comentario(ZECA)),
    )
  })
})

describe('denúncia — sem servidor, o documento é o canal', () => {
  const denuncia = (uid, extra = {}) => ({
    uid,
    postId: 'p1',
    reason: 'ofensa',
    at: serverTimestamp(),
    ...extra,
  })

  before(async () => {
    await seed()
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore()
      await setDoc(doc(db, 'posts', 'p1'), {
        uid: ANA,
        text: 'Dia puxado',
        createdAt: new Date(),
        deleted: false,
      })
      await setDoc(doc(db, 'posts', 'p1', 'comments', 'c1'), {
        uid: ANA,
        text: 'Comentário qualquer',
        createdAt: new Date(),
      })
    })
  })

  it('denuncio um post, e denunciar de novo não é erro', async () => {
    // O id é `p_{postId}__{quem denunciou}`: uma denúncia por pessoa por alvo,
    // garantida pela forma do dado. A segunda sobrescreve a primeira.
    await assertSucceeds(
      setDoc(doc(bia, 'reports', `p_p1__${BIA}`), denuncia(BIA)),
    )
    await assertSucceeds(
      setDoc(
        doc(bia, 'reports', `p_p1__${BIA}`),
        denuncia(BIA, { reason: 'spam' }),
      ),
    )
  })

  it('denuncio um comentário', async () => {
    await assertSucceeds(
      setDoc(
        doc(bia, 'reports', `c_p1_c1__${BIA}`),
        denuncia(BIA, { commentId: 'c1' }),
      ),
    )
  })

  it('NÃO leio denúncia nenhuma — nem a minha', async () => {
    // Uma coleção de denúncias legível é a lista de quem delatou quem.
    await assertFails(getDoc(doc(bia, 'reports', `p_p1__${BIA}`)))
    await assertFails(getDocs(collection(bia, 'reports')))
  })

  it('NÃO denuncio em nome de outro', async () => {
    await assertFails(
      setDoc(doc(bia, 'reports', `p_p1__${ANA}`), denuncia(ANA)),
    )
  })

  it('NÃO denuncio o meu próprio conteúdo', async () => {
    // Denúncia é sobre conteúdo alheio, e essa condição é o que fecha o laço
    // de uma conta só: publicar, denunciar a si mesma, apagar o alvo e repetir
    // deixava documentos permanentes em `reports` — `delete: if false`,
    // `get/list: if false` — que nem o dono do app alcança pelo cliente.
    await assertFails(setDoc(doc(ana, 'reports', `p_p1__${ANA}`), denuncia(ANA)))
    await assertFails(
      setDoc(
        doc(ana, 'reports', `c_p1_c1__${ANA}`),
        denuncia(ANA, { commentId: 'c1' }),
      ),
    )
  })

  it('NÃO uso id fora do padrão', async () => {
    // Sem a amarra do id, a mesma pessoa denuncia o mesmo post mil vezes com
    // ids diferentes e enche a fila de moderação de graça.
    await assertFails(setDoc(doc(bia, 'reports', 'qualquer'), denuncia(BIA)))
    await assertFails(
      setDoc(doc(bia, 'reports', `p_p1__${BIA}x`), denuncia(BIA)),
    )
    // Sem o prefixo, denúncia de post e de comentário dividiam o mesmo espaço
    // de nomes — e os dois ids são escolhidos pelo cliente.
    await assertFails(setDoc(doc(bia, 'reports', `p1__${BIA}`), denuncia(BIA)))
    await assertFails(
      setDoc(
        doc(bia, 'reports', `p_p1__${BIA}`),
        denuncia(BIA, { commentId: 'c1' }),
      ),
    )
  })

  it('comentário homônimo de post NÃO sobrescreve a denúncia do post', async () => {
    // O ataque que o prefixo fecha: publicar um comentário com o id de um post
    // e ver a denúncia de um apagar a do outro, em silêncio.
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'posts', 'q9'), {
        uid: ANA,
        text: 'outro post',
        createdAt: new Date(),
        deleted: false,
      })
      await setDoc(doc(ctx.firestore(), 'posts', 'q9', 'comments', 'p1'), {
        uid: ANA,
        text: 'comentário com id de post',
        createdAt: new Date(),
      })
    })

    await assertSucceeds(
      setDoc(
        doc(bia, 'reports', `c_q9_p1__${BIA}`),
        denuncia(BIA, { postId: 'q9', commentId: 'p1' }),
      ),
    )
    // E o id continua sendo lido pelo dono: a denúncia do post p1 sobrevive.
    await env.withSecurityRulesDisabled(async (ctx) => {
      const anterior = await getDoc(
        doc(ctx.firestore(), 'reports', `p_p1__${BIA}`),
      )
      assert.equal(anterior.exists(), true)
      assert.equal(anterior.data().postId, 'p1')
    })
  })

  it('NÃO denuncio alvo que não existe', async () => {
    await assertFails(
      setDoc(
        doc(bia, 'reports', `p_fantasma__${BIA}`),
        denuncia(BIA, { postId: 'fantasma' }),
      ),
    )
    await assertFails(
      setDoc(
        doc(bia, 'reports', `c_p1_c-fantasma__${BIA}`),
        denuncia(BIA, { commentId: 'c-fantasma' }),
      ),
    )
  })

  it('NÃO invento motivo, campo ou hora', async () => {
    await assertFails(
      setDoc(
        doc(bia, 'reports', `p_p1__${BIA}`),
        denuncia(BIA, { reason: 'porque sim' }),
      ),
    )
    await assertFails(
      setDoc(
        doc(bia, 'reports', `p_p1__${BIA}`),
        denuncia(BIA, { detalhe: 'texto livre' }),
      ),
    )
    await assertFails(
      setDoc(
        doc(bia, 'reports', `p_p1__${BIA}`),
        denuncia(BIA, { at: new Date('9999-12-31') }),
      ),
    )
  })

  it('NÃO apago uma denúncia', async () => {
    // Denúncia que se apaga não é denúncia — mesma razão de `precos` não ter
    // update nem delete.
    await assertFails(deleteDoc(doc(bia, 'reports', `p_p1__${BIA}`)))
  })
})

describe('regra de pagamento — configuração de negócio, não dado de usuário', () => {
  before(async () => {
    // `seed()` começa com `clearFirestore()`. Semear antes dele apagaria isto
    // em silêncio — e, combinado com a armadilha do `getDoc` abaixo, o teste de
    // leitura continuaria verde sem documento nenhum no banco.
    await seed()
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore()
      await setDoc(doc(db, 'norouterule', 'mercadolivre'), { percent: 40 })
      await setDoc(doc(db, 'norouterule', 'amazon'), { percent: 100 })
    })
  })

  it('qualquer autenticado lê a regra da empresa, por id', async () => {
    // `assertSucceeds(getDoc(...))` sozinho NÃO prova nada: um `get`
    // autorizado sobre documento inexistente devolve um snapshot com
    // `exists() === false`, não um erro. Sem afirmar o valor, este teste
    // passaria com o seed esquecido, com o nome da coleção digitado errado, ou
    // com o `clearFirestore` apagando antes.
    const ml = await getDoc(doc(bia, 'norouterule', 'mercadolivre'))
    assert.equal(ml.exists(), true)
    assert.equal(ml.data().percent, 40)

    const amazon = await getDoc(doc(zeca, 'norouterule', 'amazon'))
    assert.equal(amazon.data().percent, 100)
  })

  it('empresa sem regra é documento ausente, não erro de permissão', async () => {
    // A Shopee não tem documento, e o app precisa distinguir isso de "não
    // consegui ler": um é "cadastre a regra", o outro é "tente de novo". Se
    // esta leitura fosse negada, o entregador offline e o entregador da Shopee
    // veriam a mesma frase.
    const shopee = await getDoc(doc(bia, 'norouterule', 'shopee'))
    assert.equal(shopee.exists(), false)
  })

  it('anônimo NÃO lê', async () => {
    // Primeiro teste anônimo do arquivo. Escrito com
    // `env.authenticatedContext('qualquer')` ele testaria a asserção errada:
    // `request.auth != null` é satisfeito por qualquer uid, então passaria sem
    // dizer nada sobre quem está de fora.
    const anonimo = env.unauthenticatedContext().firestore()
    await assertFails(getDoc(doc(anonimo, 'norouterule', 'mercadolivre')))
  })

  it('NÃO lista a coleção', async () => {
    // `get` e não `read`, como em `nicknames` e `profiles`. Não há consumidor
    // de `list`: o app busca por id conhecido.
    await assertFails(getDocs(collection(bia, 'norouterule')))
  })

  it('NINGUÉM grava pelo cliente — nem criando, nem alterando', async () => {
    // A linha que mais protege desta feature. Com `create` liberado, uma conta
    // autenticada grava `{percent: 0}` em `amazon` e zera o pagamento de todo
    // mundo; com `update`, troca 40 por 100 e infla o ganho de todos.
    //
    // Os três casos rodam contra ids **semeados**. Um `updateDoc` sobre id que
    // nunca existiu volta `not-found`, e `assertFails` só aceita
    // `permission-denied`: o teste quebraria pelo motivo errado e mandaria o
    // próximo leitor investigar a regra em vez do seed.
    await assertFails(
      setDoc(doc(bia, 'norouterule', 'amazon'), { percent: 0 }),
    )
    await assertFails(
      updateDoc(doc(bia, 'norouterule', 'mercadolivre'), { percent: 100 }),
    )
    await assertFails(deleteDoc(doc(bia, 'norouterule', 'mercadolivre')))
  })

  it('NÃO cria empresa nova pelo cliente', async () => {
    await assertFails(
      setDoc(doc(ana, 'norouterule', 'shopee'), { percent: 100 }),
    )
  })
})

describe('token de notificação — a chave é o aparelho, não o dono', () => {
  // O id **é** o sha256 do token, e a regra confere isso com
  // `hashing.sha256(...).toHexString().lower()`. Um id literal aqui não serviria
  // mais — e essa é a diferença entre a regra impor a forma e o app prometê-la.
  const idDe = (token) => createHash('sha256').update(token, 'utf8').digest('hex')

  const TOKEN_1 = 'fMxxx:APA91bExemploDeTokenDoFirebaseCloudMessaging'
  const TOKEN_2 = 'gNyyy:APA91bOutroAparelhoDaMesmaPessoa'

  const APARELHO_1 = idDe(TOKEN_1)
  const APARELHO_2 = idDe(TOKEN_2)

  const token = (uid, { plataforma = 'android', valor = TOKEN_1 } = {}) => ({
    token: valor,
    uid,
    platform: plataforma,
    updatedAt: serverTimestamp(),
  })

  before(async () => {
    await seed()
  })

  it('o dono grava o próprio aparelho', async () => {
    await assertSucceeds(
      setDoc(doc(ana, 'fcmTokens', APARELHO_1), token(ANA)),
    )
  })

  it('`updatedAt` em ISO é NEGADO — e é o erro que passaria despercebido', async () => {
    // O padrão de `updatedAt` no resto do app é string ISO
    // (`profileController`, `Users`, `Vehicle`); só `at` e `createdAt` usam
    // carimbo do servidor. Escrever este no padrão da casa nega **toda**
    // gravação de token — e como o registro é silencioso por desenho, o app
    // sobe verde, o `flutter test` passa e nenhum aparelho recebe nada.
    //
    // Este teste existe para que o erro apareça aqui, e não num aparelho mudo.
    await assertFails(
      setDoc(doc(ana, 'fcmTokens', APARELHO_2), {
        ...token(ANA, { valor: TOKEN_2 }),
        updatedAt: '2026-08-25T10:00:00.000',
      }),
    )
  })

  it('ninguém grava token carimbado com o uid de outro', async () => {
    await assertFails(
      setDoc(doc(bia, 'fcmTokens', APARELHO_2), token(ANA, { valor: TOKEN_2 })),
    )
  })

  it('o celular emprestado: quem entra depois FICA com o aparelho', async () => {
    // O desenho inteiro está neste teste. O token do FCM é da instalação do
    // app, não da pessoa: com `user/{uid}/tokens/{token}`, o aparelho da Ana e
    // o da Bia seriam dois documentos e as duas receberiam. Com o token como
    // id, é **um** documento, e o login da Bia o toma.
    //
    // Por isso o `update` é liberado aqui e negado em `nicknames`: lá a
    // segunda reivindicação é um roubo, aqui é o dono legítimo do momento.
    await assertSucceeds(
      setDoc(doc(bia, 'fcmTokens', APARELHO_1), token(BIA)),
    )

    // Afirmar o valor, e não só que a escrita passou: `assertSucceeds` sozinho
    // não diz de quem o aparelho ficou.
    await env.withSecurityRulesDisabled(async (ctx) => {
      const salvo = await getDoc(doc(ctx.firestore(), 'fcmTokens', APARELHO_1))
      assert.equal(salvo.data().uid, BIA)
    })
  })

  it('id que NÃO é o hash do token é negado — o invariante da chave', async () => {
    // Este é o teste que sustenta a frase inteira do desenho.
    //
    // Sem ele — e sem `hashing.sha256` na regra — um cliente gravaria o **mesmo
    // token** sob dois ids diferentes, com dois donos, e os dois receberiam:
    // exatamente o celular emprestado que a chave invertida existe para fechar.
    // "A colisão some por forma" só é verdade se a forma for **imposta** pela
    // regra; prometida pelo app, ela vale até o primeiro cliente que não cumpra.
    //
    // Uma versão anterior desta regra e da spec afirmavam que conferir isso era
    // impossível. Era falso: regra do Firestore calcula hash.
    await assertFails(
      setDoc(doc(ana, 'fcmTokens', APARELHO_2), token(ANA, { valor: TOKEN_1 })),
    )
  })

  it('hexa MAIÚSCULO é negado — `toHexString()` devolve assim, o Dart não', async () => {
    // `.lower()` na regra é o que faz as duas pontas casarem: o Firestore
    // devolve o hexa em maiúsculo, o `crypto` do Dart gera minúsculo. Sem o
    // `.lower()`, TODA gravação seria negada e — como o registro é silencioso —
    // o app subiria verde sem nenhum aparelho receber nada.
    await assertFails(
      setDoc(doc(ana, 'fcmTokens', APARELHO_1.toUpperCase()), token(ANA)),
    )
  })

  it('id fora do sha256 é NEGADO — inclusive o token cru', async () => {
    // Sem prender o wildcard, a coleção é depósito livre na cota do projeto,
    // como o comentário de `profiles/{uid}/stats/{bucket}` já registra. E o
    // token cru como id é a aposta que a regra recusa: o Google não promete
    // alfabeto nenhum para ele.
    await assertFails(
      setDoc(doc(ana, 'fcmTokens', 'fMxxx:APA91bTokenCru'), token(ANA)),
    )
    await assertFails(
      setDoc(doc(ana, 'fcmTokens', 'A'.repeat(64)), token(ANA)),
    )
    await assertFails(
      setDoc(doc(ana, 'fcmTokens', 'a'.repeat(63)), token(ANA)),
    )
  })

  it('campo a mais e campo a menos são NEGADOS', async () => {
    await assertFails(
      setDoc(doc(ana, 'fcmTokens', APARELHO_2), {
        ...token(ANA, { valor: TOKEN_2 }),
        apelido: 'iPhone do Wesley',
      }),
    )
    await assertFails(
      setDoc(doc(ana, 'fcmTokens', APARELHO_2), {
        uid: ANA,
        platform: 'android',
        updatedAt: serverTimestamp(),
      }),
    )
  })

  it('plataforma fora da lista é NEGADA', async () => {
    // `firebase_options.dart` só configura Android e iOS; as outras
    // plataformas lançam `UnsupportedError`. Um token "web" aqui seria linha
    // que nenhuma função saberia usar.
    await assertFails(
      setDoc(
        doc(ana, 'fcmTokens', APARELHO_2),
        token(ANA, { valor: TOKEN_2, plataforma: 'web' }),
      ),
    )
  })

  it('NINGUÉM lê, nem o próprio dono', async () => {
    // O app só escreve. Quem lê é o Admin SDK, que não passa por estas regras.
    // Uma coleção de tokens legível é o mapa dos aparelhos de todo mundo.
    await assertFails(getDoc(doc(ana, 'fcmTokens', APARELHO_1)))
    await assertFails(getDocs(collection(ana, 'fcmTokens')))
  })

  it('anônimo não grava', async () => {
    const anonimo = env.unauthenticatedContext().firestore()
    await assertFails(
      setDoc(doc(anonimo, 'fcmTokens', APARELHO_2), token(ANA)),
    )
  })

  it('o dono apaga o próprio aparelho; o de outro, não', async () => {
    // Depois do teste do celular emprestado, APARELHO_1 é da Bia.
    await assertFails(deleteDoc(doc(ana, 'fcmTokens', APARELHO_1)))
    await assertSucceeds(deleteDoc(doc(bia, 'fcmTokens', APARELHO_1)))
  })

  it('apagar aparelho inexistente passa, e é de propósito', async () => {
    // O logout apaga o último id que o serviço conhece, em melhor esforço.
    // Negar o segundo logout seria erro sem consequência nenhuma — mesma
    // escolha de `friendRequests`, onde o aceite apaga os quatro marcadores
    // sem saber quais existem.
    await assertSucceeds(
      deleteDoc(doc(zeca, 'fcmTokens', 'f'.repeat(64))),
    )
  })
})

describe('marcador de aviso — infraestrutura, não dado de usuário', () => {
  // A segunda coleção do projeto em que o cliente não tem nada a fazer, depois
  // de `norouterule`. O Admin SDK ignora estas regras e continua escrevendo — e
  // é exatamente por isso que a ausência de regra passaria despercebida: tudo
  // funcionaria, e qualquer conta autenticada poderia emudecer o vizinho.
  const ID = 'uid-ana_uid-bia_rotas_2026-08_2026-08-27'

  before(async () => {
    await seed()
  })

  it('NINGUÉM cria o marcador pelo cliente', async () => {
    // O ataque que a regra fecha: pré-criar o marcador do dia da Ana faz a
    // Function achar que já avisou, e ela passa o dia inteira muda. A supressão
    // é **invisível para os dois lados** — ao contrário do apelido tomado, que
    // dá erro na cara de quem tenta. É por isso que aqui é `if false` e em
    // `nicknames` não.
    await assertFails(
      setDoc(doc(bia, 'avisosRanking', ID), { at: serverTimestamp() }),
    )
  })

  it('NINGUÉM lê nem lista', async () => {
    await assertFails(getDoc(doc(ana, 'avisosRanking', ID)))
    await assertFails(getDocs(collection(ana, 'avisosRanking')))
  })

  it('nem o anônimo, nem para apagar', async () => {
    const anonimo = env.unauthenticatedContext().firestore()
    await assertFails(
      setDoc(doc(anonimo, 'avisosRanking', ID), { at: serverTimestamp() }),
    )
    await assertFails(deleteDoc(doc(ana, 'avisosRanking', ID)))
  })
})

describe('marcos do post — o marcador que ninguém pode tocar', () => {
  const POST = 'post-marcos'

  before(async () => {
    await seed()
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'posts', POST), {
        uid: ANA,
        text: 'Rodei 180 km hoje',
        createdAt: new Date(),
        deleted: false,
      })
    })
  })

  it('NINGUÉM cria — nem o dono do post', async () => {
    // Pré-criar `curtidas_10` num post alheio emudece o aviso daquele marco
    // para sempre, e a supressão é invisível para os dois lados. Pré-criar no
    // **próprio** post não faz sentido nenhum, e é justamente por isso que a
    // regra não abre exceção para o dono: exceção sem caso de uso é só
    // superfície.
    await assertFails(
      setDoc(doc(bia, 'posts', POST, 'marcos', 'curtidas_10'), { at: serverTimestamp() }),
    )
    await assertFails(
      setDoc(doc(ana, 'posts', POST, 'marcos', 'curtidas_10'), { at: serverTimestamp() }),
    )
  })

  it('NINGUÉM apaga — apagar faria o mesmo marco ser anunciado de novo', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), 'posts', POST, 'marcos', 'curtidas_1'),
        { at: new Date(), total: 1 },
      )
    })

    await assertFails(deleteDoc(doc(ana, 'posts', POST, 'marcos', 'curtidas_1')))
    await assertFails(deleteDoc(doc(bia, 'posts', POST, 'marcos', 'curtidas_1')))
  })

  it('NINGUÉM lê nem lista', async () => {
    // A lista de marcos conta quantas curtidas o post já teve ao longo do
    // tempo — mais do que a tela mostra, e de um jeito que o dono não escolheu.
    await assertFails(getDoc(doc(ana, 'posts', POST, 'marcos', 'curtidas_1')))
    await assertFails(getDocs(collection(bia, 'posts', POST, 'marcos')))
  })

  it('a subcoleção fechada não afeta curtir nem comentar', async () => {
    // Sanidade: a `match` nova é irmã de `likes` e `comments`, e regra do
    // Firestore não cascateia. Se esta expectativa falhar, alguém trocou a
    // posição do bloco e fechou o mural junto.
    await assertSucceeds(
      setDoc(doc(bia, 'posts', POST, 'likes', BIA), {
        uid: BIA,
        at: serverTimestamp(),
      }),
    )
  })
})

describe('painel admin — o moderador passa pelas regras, não por cima delas', () => {
  // O que o console nunca deu: a lápide do admin conferida por regra. Uma
  // escrita de admin no console não passa por este arquivo; a do painel passa
  // — e estes testes são a diferença entre as duas.
  before(async () => {
    await seed()
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore()
      await setDoc(doc(db, 'posts', 'p1'), {
        uid: ANA,
        text: 'Post denunciado',
        imagePath: `posts/${ANA}/foto.jpg`,
        createdAt: new Date(),
        deleted: false,
      })
      await setDoc(doc(db, 'posts', 'p1', 'comments', 'c1'), {
        uid: BIA,
        text: 'Comentário denunciado',
        createdAt: new Date(),
      })
      // Duas denúncias do mesmo post (a fila agrupa por alvo) e uma do
      // comentário.
      await setDoc(doc(db, 'reports', `p_p1__${BIA}`), {
        uid: BIA, postId: 'p1', reason: 'ofensa', at: new Date(),
      })
      await setDoc(doc(db, 'reports', `p_p1__${ZECA}`), {
        uid: ZECA, postId: 'p1', reason: 'spam', at: new Date(),
      })
      await setDoc(doc(db, 'reports', `c_p1_c1__${ZECA}`), {
        uid: ZECA, postId: 'p1', commentId: 'c1', reason: 'golpe',
        at: new Date(),
      })
    })
  })

  it('o admin lista a fila; conta comum e anônimo, não', async () => {
    // Afirmar o tamanho, não só que a leitura passou: um `list` autorizado
    // sobre coleção vazia também "passa" — com o seed esquecido este teste
    // continuaria verde sem provar nada, a armadilha que o bloco de
    // `norouterule` já documenta.
    const fila = await assertSucceeds(getDocs(collection(admin, 'reports')))
    assert.equal(fila.size, 3)
    await assertSucceeds(getDoc(doc(admin, 'reports', `p_p1__${BIA}`)))

    await assertFails(getDocs(collection(bia, 'reports')))
    const anonimo = env.unauthenticatedContext().firestore()
    await assertFails(getDocs(collection(anonimo, 'reports')))
  })

  it('a forma pinada da lápide vale para o admin também', async () => {
    // O admin não ganhou update: ganhou o direito à única forma que já era
    // permitida. Texto que sobrevive, imagem que aponta para outro caminho e
    // edição sem apagar continuam negados — para ele inclusive.
    await assertFails(
      updateDoc(doc(admin, 'posts', 'p1'), {
        deleted: true,
        text: 'x'.repeat(1000),
        imagePath: null,
      }),
    )
    await assertFails(
      updateDoc(doc(admin, 'posts', 'p1'), {
        deleted: true,
        text: '',
        imagePath: `posts/${BIA}/foto.jpg`,
      }),
    )
    await assertFails(updateDoc(doc(admin, 'posts', 'p1'), { text: 'censurado' }))
  })

  it('remove o post de OUTRA pessoa com a lápide exata', async () => {
    await assertSucceeds(
      updateDoc(doc(admin, 'posts', 'p1'), {
        deleted: true,
        text: '',
        imagePath: null,
      }),
    )
  })

  it('delete real continua negado — para o admin inclusive', async () => {
    // Apagar é marcar, e o moderador não é exceção: o delete real deixaria as
    // curtidas órfãs, libertaria o id e quebraria o `get()` das próprias
    // regras de moderação.
    await assertFails(deleteDoc(doc(admin, 'posts', 'p1')))
  })

  it('apaga o comentário denunciado — de terceiro, sob post de terceiro', async () => {
    await assertSucceeds(deleteDoc(doc(admin, 'posts', 'p1', 'comments', 'c1')))
  })

  it('dá baixa por alvo, e dar baixa de novo não é erro', async () => {
    const baixa = () => ({ resolution: 'removido', at: serverTimestamp() })
    await assertSucceeds(setDoc(doc(admin, 'moderation', 'p_p1'), baixa()))
    // Sobrescrever é o reparo da baixa errada — `delete` é que não existe.
    await assertSucceeds(
      setDoc(doc(admin, 'moderation', 'p_p1'), {
        resolution: 'ignorado',
        at: serverTimestamp(),
      }),
    )
    await assertSucceeds(setDoc(doc(admin, 'moderation', 'c_p1_c1'), baixa()))
  })

  it('baixa fora da forma é negada — mesmo vinda do admin', async () => {
    await assertFails(
      setDoc(doc(admin, 'moderation', 'p_p1'), {
        resolution: 'porque sim',
        at: serverTimestamp(),
      }),
    )
    await assertFails(
      setDoc(doc(admin, 'moderation', 'p_p1'), {
        resolution: 'removido',
        at: serverTimestamp(),
        nota: 'texto livre',
      }),
    )
    await assertFails(
      setDoc(doc(admin, 'moderation', 'p_p1'), {
        resolution: 'removido',
        at: new Date('9999-12-31'),
      }),
    )
    // Id que não casa com alvo nenhum não dá baixa em nada — e o regex é o
    // que impede a coleção de virar depósito de ids inventados.
    await assertFails(
      setDoc(doc(admin, 'moderation', 'qualquer'), {
        resolution: 'removido',
        at: serverTimestamp(),
      }),
    )
    await assertFails(
      setDoc(doc(admin, 'moderation', `p_${'z'.repeat(65)}`), {
        resolution: 'removido',
        at: serverTimestamp(),
      }),
    )
  })

  it('baixa não se apaga, e conta comum não lê nem escreve', async () => {
    await assertFails(deleteDoc(doc(admin, 'moderation', 'p_p1')))
    await assertFails(getDoc(doc(bia, 'moderation', 'p_p1')))
    await assertFails(getDocs(collection(bia, 'moderation')))
    await assertFails(
      setDoc(doc(bia, 'moderation', 'c_p1_c1'), {
        resolution: 'ignorado',
        at: serverTimestamp(),
      }),
    )
  })

  it('o raio do admin PARA aqui — CPF, bloqueios e configuração seguem fechados', async () => {
    // A moderação precisa do conteúdo, não da pessoa: `user/{uid}` (CPF,
    // telefone) não abre nem para o moderador, e `norouterule` continua sendo
    // escrita de console. Se um destes passar, alguém transformou `isAdmin()`
    // em superusuário — que é exatamente o que a spec proíbe.
    await assertFails(getDoc(doc(admin, 'user', ANA)))
    await assertFails(getDocs(collection(admin, 'blocks', ANA, 'list')))
    await assertFails(
      setDoc(doc(admin, 'norouterule', 'amazon'), { percent: 0 }),
    )
    await assertFails(getDocs(collection(admin, 'fcmTokens')))
  })
})
