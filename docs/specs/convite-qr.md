# Spec: Compartilhar perfil e convite por QR Code

Status: **implementada** · Criada, aprovada e implementada em 2026-08-24 ·
Falta verificação em aparelho da leitura (câmera não sobe em teste de widget) e
o **link clicável**, que depende de uma página no Firebase Hosting

## Objetivo

O botão COMPARTILHAR do dialog de perfil dizia "está em desenvolvimento" desde
que nasceu. Passa a mandar o convite para fora do app — WhatsApp, Instagram,
e-mail, área de transferência, o que a pessoa tiver — e ganha ao lado um botão
de QR Code que **vira o cartão** e mostra o código para o colega ler.

Usuário: o entregador que acabou de conhecer alguém no galpão. Sucesso = os dois
saem de lá amigos no app sem ninguém digitar apelido no celular do outro.

É a dívida que `amigos.md` registrava como *"UI para trocar o próprio apelido"*,
resolvida pela metade que interessa: **para alguém te achar, você precisa
conseguir passar o seu apelido.** Trocar o apelido continua fora de escopo.

## O problema do link, e por que ele não existe hoje

O pedido foi "mandar o seu link de amigo nas redes". Não há link possível agora,
e fingir que há seria pior do que não mandar nada:

- **Firebase Dynamic Links**, o caminho clássico para "link que abre o app,
  instala se não tiver", o Google **desligou em agosto de 2025**.
- **`iter://amigo/<apelido>`** funciona como esquema, mas WhatsApp e Instagram
  não transformam esquema desconhecido em link clicável: chega como texto morto.
- **`https://`** precisa de uma página de verdade atrás. Link quebrado
  compartilhado em rede social é pior do que apelido nenhum — quem toca vê erro
  e conclui que o app é que está quebrado.

Então o que sai hoje é o **apelido com a instrução**:

```
Sou Wesley Nogueira no iter: @wesley-efmg
Busque por esse apelido em Amigos › Adicionar amigo.
```

Funciona em toda rede, hoje, e quem recebe sem ter o app entende o que é. A
dívida do link está no fim desta spec.

## O que sai e o que entra

`lib/Utils/friendShare.dart` é a **fronteira** da feature, e é por isso que ela
é um arquivo separado e não duas interpolações dentro de widget: tudo que sai
por aqui vira mensagem em rede alheia, e tudo que entra vem de uma câmera lendo
um quadrado que qualquer um pode ter gerado. As duas pontas são função pura,
testáveis sem câmera e sem Firestore.

| função | o que faz |
|---|---|
| `friendQrPayload(apelido)` | `iter://amigo/<apelido>` — o conteúdo do QR |
| `friendShareText(apelido, {name})` | a mensagem da folha de compartilhamento |
| `nicknameFromScan(raw)` | o apelido que veio da câmera, ou `null` |

### Sai o `@apelido`, nunca o uid

O apelido já é a chave pública da busca — é o que a `AddFriend` pede — e
resolver apelido → uid passa por `nicknames/{apelido}`, que a regra deixa ler
por id. Pôr o uid no QR não abriria nada que já não esteja aberto, mas
espalharia por print e captura de tela o identificador que as regras usam como
sujeito. **O apelido é trocável; o uid não.**

### Recusar é o caso comum

A câmera lê etiqueta de encomenda, QR de Wi-Fi, link de nota fiscal e o cartaz
da parede do galpão. Devolver o último pedaço de qualquer URL transformaria
`https://loja.com/promo` numa busca por "promo" — e a tela responderia "ninguém
usa esse apelido", culpando o apelido por um código que nunca foi um convite.

`nicknameFromScan` só aceita código que **se declara** convite: o payload do
próprio app ou um `@apelido`. A decisão é pelo **esquema** primeiro, nunca pelo
caminho: `Uri.tryParse` engole quase tudo, e `meu-yzwy` vira um `Uri` de caminho
relativo sem esquema nenhum.

**Texto solto não entra, e essa foi uma correção durante a escrita do teste.**
`NicknameController.normalize` troca espaço por hífen e tira acento, então
"Promoção 50" vira `promocao-50` — que **passa** na régua
`^[a-z0-9._-]{3,20}$`. Sem exigir o `@`, o cartaz do galpão viraria uma busca. O
`@` é o que separa "isto é um apelido" de "isto é uma frase".

## O flip

O cartão gira em `rotationY` com perspectiva (`Matrix4..setEntry(3, 2, 0.0012)`),
420 ms, e a face de trás leva uma **segunda rotação de π**. Sem ela o QR sai
espelhado — e QR espelhado não é um QR difícil de ler: é **outro dado**, que o
leitor recusa. A troca de face acontece em `value > 0.5`, no meio do giro, que é
onde a face que sai já está de perfil.

**O cabeçalho fica fora do `Transform`.** Banner, foto, nome e apelido não giram:
é o que faz o giro ler como "o mesmo cartão virou" em vez de "abriu outra tela",
e é o que mantém o `@apelido` à vista na face do QR — quando a câmera do outro
não coopera, digitar é a saída.

**`AnimatedSize`, não altura fixa.** As duas faces não têm a mesma altura e
nenhuma das duas tem altura constante: a dos números mede 144 px numa carreira
completa e 158 px numa com empresa que este app não conhece (medido com Roboto
de verdade, em 390 dp).
Cravar uma constante serviria a um perfil e faria o cartão pular no meio do giro
em todos os outros — a mesma armadilha que o `_StatsPlaceholder` deste mesmo
dialog já custou duas vezes, com dois números errados.

### `qrPayload` vem de fora, e só o próprio perfil passa

O dialog não sabe quem está logado — é o que o mantém testável sem Firebase — e
o QR é parâmetro como todo o resto. `null` esconde o botão **e** a face de trás
inteira. O perfil de um amigo não passa: o QR é o convite dele, e oferecê-lo
daqui deixaria qualquer um distribuir o convite de outra pessoa.

## A leitura cai no fluxo que já existe

`ScanFriend` devolve o **apelido** e não convida. Quem resolve apelido → perfil
→ convite é a `AddFriend`, e aquele caminho já mostra "é essa a pessoa?" antes de
qualquer escrita e já sabe distinguir apelido inexistente de falta de rede.
Convidar direto da câmera seria uma segunda implementação do mesmo fluxo, com a
diferença de mandar convite para quem a pessoa nem viu quem é.

O apelido lido **preenche o campo** antes de buscar: se ele não existir mais, a
tela diz isso com o apelido à vista, e dá para corrigir uma letra em vez de ler
o código de novo.

Duas travas na tela da câmera, e as duas vêm de a detecção disparar muitas vezes
por segundo enquanto o código continuar enquadrado: `_resolvido` impede que um
único QR empilhe dezenas de `pop` (derrubando a tela de baixo junto), e
`_recusado` guarda o último código negado para a mensagem não piscar a cada
quadro.

## Dependências

As três foram aprovadas antes de instalar, como a Fronteira de `amigos.md`
manda:

| pacote | por quê | alternativa recusada |
|---|---|---|
| `share_plus` | a folha nativa entrega WhatsApp, Instagram, e-mail e "copiar" de uma vez, com os apps que a pessoa **tem** | um botão por rede é uma lista para manter e um esquema de URL para quebrar sozinho |
| `qr_flutter` | desenha o QR | gerar à mão é correção de erro Reed-Solomon, ~300 linhas que não são o problema deste app |
| `mobile_scanner` | lê o QR dentro do app | deixar a câmera nativa abrir o `iter://` troca uma dependência por outra (`app_links`), mais configuração de esquema nos dois sistemas, e depende de como cada app de câmera trata esquema desconhecido |

No iPad a folha do `share_plus` é um **popover**, e popover sem âncora derruba o
app com exceção nativa. O `TARGETED_DEVICE_FAMILY` do projeto é `"1,2"`, então o
iPad é destino declarado mesmo que ninguém teste nele — por isso o
`sharePositionOrigin` sai do `RenderBox` da Home. No iPhone o parâmetro é
ignorado.

`mobile_scanner` é a mais pesada (ML Kit no Android). Ele exige
`android.permission.CAMERA` no manifesto — o `image_picker` não a declarava
porque **delega** a foto ao app de câmera do sistema, que tira a foto com a
permissão dele; ler QR é diferente, o app recebe o fluxo da câmera. E a frase do
`NSCameraUsageDescription` no iOS passou a mencionar o QR: a Apple recusa build
cuja frase não descreve o uso.

## Estratégia de teste

`test/unit/friendShare_test.dart` — as duas pontas, 12 casos:

- o QR carrega o apelido e a mensagem carrega a instrução;
- a leitura desfaz o que o compartilhamento faz (ida e volta);
- normaliza como a busca normaliza (`@Maria.S7` → `maria.s7`);
- **esquema alheio é recusado, não raspado** — `https://loja.com/promo`, QR de
  Wi-Fi e `mailto:` voltam `null`;
- esquema certo com caminho errado (`iter://rota/123`) também é recusado;
- texto solto não vira busca, mesmo sobrevivendo à normalização.

`test/widget/profileDialog_test.dart` — o flip, seis casos. Um deles achou um
defeito de verdade: o `AnimationController` estava num `late final` inicializado
por uso, e o perfil de um **amigo** — que não tem QR e portanto nunca lê o campo
no `build` — só tocava nele dentro do `dispose()`, procurando o `TickerMode` num
contexto já desativado. **Fechar o perfil de qualquer amigo levantava exceção.**
O controller passou para o `initState`.

Os testes do flip fixam a tela em 390×844. O padrão do teste é 800×600 — mais
**baixo** que qualquer aparelho —, e como a face do QR é mais alta, a linha de
botões saía da área visível e o toque não chegava nela. Não é defeito do dialog,
que rola; é o teste medindo numa tela que não existe.

`test/widget/addFriend_test.dart` — que o botão de ler existe e que montar a tela
**não** dispara busca. Se disparasse, o Firestore não inicializado derrubaria o
teste, o que torna a asserção real.

A câmera em si não tem teste, e não dá para ter: `MobileScanner` é canal de
plataforma. Por isso a tela é fina — toda a decisão mora em `nicknameFromScan`.

## Dívidas

- **O link clicável.** Uma página no Firebase Hosting (`iter-mn.web.app/u/<apelido>`
  — o subdomínio é grátis e o projeto já está no Blaze) daria um `https://`
  linkificado em qualquer rede, e serviria de cartão de visita para quem ainda
  não tem o app. Trocar é uma linha em `friendQrPayload` e um ramo em
  `nicknameFromScan` — por isso o formato mora numa função só. Abrir o app pelo
  link (App Links / Universal Links) é outra história: o `release` do Android
  ainda assina com a chave de debug, então a verificação nem passaria.
- **Ler QR de dentro da galeria** — o `mobile_scanner` sabe analisar imagem, e
  resolveria o print que o colega mandou pelo WhatsApp. Hoje é só câmera.
- **Trocar o próprio apelido** — continua sem UI. `NicknameController.change()`
  existe desde o primeiro dia.
