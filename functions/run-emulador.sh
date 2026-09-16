#!/bin/sh
# Roda os gatilhos contra os emuladores de Firestore e Functions, e **afirma**
# sobre o que saiu no log — inclusive o que NÃO pode ter saído.
#
# O emulador exige Java 21+, e o build Android deste projeto usa Java 17
# (`android/app/build.gradle.kts`). Trocar o java do sistema quebraria o build,
# então o JDK 21 entra só aqui — mesma solução de `firestore-tests/run.sh`.
set -e

if [ -z "$ITER_JDK21" ]; then
  ITER_JDK21="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi

if [ ! -x "$ITER_JDK21/bin/java" ]; then
  echo "Java 21+ não encontrado em: $ITER_JDK21" >&2
  echo "Aponte um com: export ITER_JDK21=/caminho/do/jdk" >&2
  exit 1
fi

export JAVA_HOME="$ITER_JDK21"
export PATH="$JAVA_HOME/bin:$PATH"

SAIDA=$(mktemp)
trap 'rm -f "$SAIDA"' EXIT

# `--project iter-mn` explícito: não existe `.firebaserc` na raiz, então sem a
# flag o destino é o que o `firebase use` global apontar por último.
( cd .. && firebase emulators:exec --only firestore,functions,auth,storage --project iter-mn \
    'node functions/emulador.mjs' ) 2>&1 | tee "$SAIDA"

echo
echo "── conferindo o log ──────────────────────────────────────────"

falhou=0

esperado() {
  if grep -q "$1" "$SAIDA"; then
    echo "  ok    $2"
  else
    echo "  FALHA $2 (esperava $1)"
    falhou=1
  fi
}

# Conta os avisos de ranking de um par e direção. Em pipeline porque a ordem
# das chaves no JSON do log não é estável, e alternar padrões vira ilegível.
par() {
  n=$(grep '"message":"ranking"' "$SAIDA" | grep "\"de\":\"$2\"" | grep -c "\"para\":\"$3\"" || true)
  if [ "$n" -eq "$1" ]; then
    echo "  ok    $4 (achei $n)"
  else
    echo "  FALHA $4 (esperava $1, achei $n)"
    falhou=1
  fi
}

contagem() {
  n=$(grep -c "$2" "$SAIDA" || true)
  if [ "$n" -eq "$1" ]; then
    echo "  ok    $3 (achei $n)"
  else
    echo "  FALHA $3 (esperava $1, achei $n)"
    falhou=1
  fi
}

proibido() {
  if grep -q "$1" "$SAIDA"; then
    echo "  FALHA $2 (não podia aparecer: $1)"
    falhou=1
  else
    echo "  ok    $2"
  fi
}

esperado '"message":"convite".*"para":"bia"\|"para":"bia".*"message":"convite"' \
  'convite da ana notifica a bia'
esperado '"message":"aceite".*"para":"carla"\|"para":"carla".*"message":"aceite"' \
  'aceite do dinho notifica a carla, que foi quem convidou'
proibido '"message":"aceite".*"para":"dinho"\|"para":"dinho".*"message":"aceite"' \
  'quem aceitou NÃO recebe aviso de aceite'
proibido '"message":"aceite".*"para":"elias"\|"para":"elias".*"message":"aceite"' \
  'recusa do fabio NÃO notifica o elias'
# Os dois fantasmas: `accept` e `decline` apagam os quatro caminhos de marcador
# sem saber quais existem, e o emulador entrega um `created` para o que nunca
# existiu. Sem a porta `event.data.exists` em `amizade.js`, quem convidou recebia
# "aceitou seu convite" E "enviou um convite de amizade pra você" — o segundo
# falso. Estas duas linhas são o que impede isso de voltar.
proibido '"message":"convite".*"para":"carla"\|"para":"carla".*"message":"convite"' \
  'o aceite NÃO produz um convite fantasma para quem convidou'
proibido '"message":"convite".*"para":"elias"\|"para":"elias".*"message":"convite"' \
  'a recusa NÃO produz um convite fantasma'

# ── Ranking ───────────────────────────────────────────────────────────────
#
# Seis gravações de balde produzem exatamente DUAS ultrapassagens legítimas:
# o Gil passa a Helô (R2) e depois a Helô passa o Gil (R6). A terceira — o Gil
# repassando a Helô no mesmo dia — é justamente o que o teto diário emudece.

contagem 2 '"message":"ranking"' \
  'duas ultrapassagens em seis gravações — as reescritas e o mês velho não contam'

par 1 gil helo \
  'o TETO DIÁRIO: o Gil passa a Helô duas vezes no mesmo dia e avisa uma só'

par 1 helo gil \
  'a Helô passar o Gil avisa o GIL, que foi quem perdeu a posição'

# ── Marcos ────────────────────────────────────────────────────────────────
# `grep -E` com a borda `[,}]` porque `"marco":1` casa com `"marco":10` — foi
# exatamente o que fez esta asserção acusar 2 onde havia 1.
#
# Presa ao post `p1`: o cenário de exclusão de conta também curte e comenta, e
# a primeira curtida do post do Zeca é outro "marco 1" legítimo.
marco() {
  n=$(grep "\"message\":\"$2\"" "$SAIDA" | grep '"postId":"p1"' | grep -cE "\"marco\":$3[,}]" || true)
  if [ "$n" -eq "$1" ]; then
    echo "  ok    $4 (achei $n)"
  else
    echo "  FALHA $4 (esperava $1, achei $n)"
    falhou=1
  fi
}

marco 1 curtidas 1 \
  'a PRIMEIRA curtida é anunciada uma vez — e só porque a auto-curtida não marcou'
marco 1 curtidas 10 \
  'dez curtidas em rajada anunciam o marco 10 UMA vez, apesar da corrida'
marco 1 comentarios 1 \
  'o primeiro comentário é anunciado uma vez'
marco 1 comentarios 5 \
  'cinco comentários anunciam o marco 5 uma vez'
proibido '"postId":"p2"' \
  'post com lápide NÃO notifica, mesmo com a curtida gravada'

# ── Exclusão de conta ─────────────────────────────────────────────────────
# As conferências de documento rodam dentro do `emulador.mjs`, que enxerga o
# banco; aqui fica o que só o log mostra.

esperado '"message":"conta exclu' \
  'a exclusão no Auth acordou a limpeza'
esperado 'EXCLUSAO: [0-9]* conferências, 0 falhas' \
  'tudo o que devia sumir sumiu, e tudo o que devia ficar ficou'
proibido '"message":"aceite".*"para":"lara"\|"para":"lara".*"message":"aceite"' \
  'a Lara NÃO recebe aceite falso (sintoma; a ordem em si não é provada aqui)'
proibido '"message":"aceite".*"para":"mika"\|"para":"mika".*"message":"aceite"' \
  'retirar o convite pendente da Mika NÃO vira aceite'

proibido 'Your function was killed' 'nenhuma função morreu'

echo "──────────────────────────────────────────────────────────────"
[ "$falhou" -eq 0 ] && echo "EMULADOR: tudo certo." || { echo "EMULADOR: falhou."; exit 1; }
