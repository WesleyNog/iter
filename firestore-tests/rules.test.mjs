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
import {
  doc,
  collection,
  getDoc,
  getDocs,
  setDoc,
  deleteDoc,
  writeBatch,
  serverTimestamp,
} from 'firebase/firestore'

const ANA = 'uid-ana'
const BIA = 'uid-bia'
const ZECA = 'uid-zeca'

let env
let ana
let bia
let zeca

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
      rules: readFileSync('../firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  })

  ana = env.authenticatedContext(ANA).firestore()
  bia = env.authenticatedContext(BIA).firestore()
  zeca = env.authenticatedContext(ZECA).firestore()
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

  it('lê os números de carreira de alguém', async () => {
    await assertSucceeds(getDoc(doc(bia, 'profiles', ANA, 'stats', 'all')))
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
