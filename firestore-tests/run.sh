#!/bin/sh
# Roda os testes de regra contra o emulador do Firestore.
#
# O emulador exige **Java 21+**, e o build Android deste projeto usa **Java
# 17** (`android/app/build.gradle.kts`). Trocar o java do sistema quebraria o
# build, então o JDK 21 entra só aqui, no ambiente deste comando.
#
# Ordem de procura: `$ITER_JDK21` se você apontar um, senão o JBR que vem
# dentro do Android Studio, que todo mundo que compila este app já tem.
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

exec firebase emulators:exec --only firestore --project iter-mn 'node --test'
