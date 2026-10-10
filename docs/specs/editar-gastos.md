# Spec: Editar e excluir gastos

Status: **implementada** · Pedida, decidida e implementada em 2026-10-10

## Objetivo

Corrigir um abastecimento ou uma manutenção lançados errado. Até aqui o app só
sabia criar: valor, litros ou odômetro digitados errado ficavam para sempre — e
o odômetro errado ainda estragava o km/l medido.

Usuário: o entregador, depois de lançar. Sucesso = no detalhe de **Gastos do
período** (o extrato que o card do Resumo abre), deslizar a linha para a
esquerda dá **Editar** e **Excluir**, como na lista de rotas.

## O que muda

- `ExpensesScreen` passa a ter estado: recebe as **mesmas listas** que o card
  somou (abastecimentos, manutenções e as datas do período), monta as linhas por
  `expenseRows` e desliza cada uma com o `iconSlideAction` — extraído do
  `RouteSlidable` para os dois gestos terem a mesma cara.
- `AddSupply` e `AddMaintenance` ganham modo de edição: recebem o lançamento,
  reabrem os campos e salvam com o **mesmo** `id`, substituindo o documento —
  o modelo do `AddIter`. Os dois devolvem o que gravaram no `pop`, e o extrato
  troca a linha sem reler o banco.
- Excluir pergunta antes ("Não dá para desfazer"), como na lista de rotas.

## Decidido

1. **Editar não manda preço novo ao posto.** O cadastro relata o preço em
   `gastop/{posto}/precos`, e as regras só deixam **criar** relato — nunca
   alterar nem apagar. O original fica; um segundo relato contaria o mesmo
   abastecimento duas vezes na mediana. Um preço errado é diluído pela mediana,
   como o de qualquer pessoa que digita errado. Excluir também não apaga o
   relato. No código: na edição, `AddSupply` chama `updater`
   (`SupplyController.save`, e só) e nunca o `saver` do cadastro, que relata.
2. **Editar continua oferecendo atualizar o veículo** — preço do litro e consumo
   no abastecimento, preço da peça na substituição. Corrigir um lançamento
   errado é justamente quando o cadastro pode ter recebido o número errado. Só
   pergunta, nunca decide, como no cadastro.
3. **Abastecimento e manutenção**, os dois. O extrato mistura os dois, e o gesto
   valer numa linha e não na outra ensinaria errado.

## Regras que a edição preserva

- **O GPS de agora não é o lugar do abastecimento.** Quem corrige está em casa,
  não na bomba — a mesma razão de "Outra localização" gravar `lat/lng` nulos.
  Posto mantido mantém a posição gravada; posto trocado fica sem ela, e o posto
  carrega as próprias coordenadas.
- **A data gravada fica** quando o dia não muda — hora incluída. Refazê-la por
  `expenseDateFor` trocaria "registrado às 14:32" por meio-dia sem ninguém
  pedir. Na manutenção, que não tem campo de data, ela fica sempre: salvar com
  a de agora moveria a troca de agosto para hoje.
- **O veículo é o do lançamento, nunca o ativo**, e o combustível gravado fica:
  corrigir o valor de ontem não pode mudar de carro quem rodou com ele.
- `createdAt` fica.
- O km/l medido se corrige sozinho: `measuredEconomy` é recalculado dos
  abastecimentos gravados a cada leitura.
- Uma edição que leve a data para fora do período tira a linha do extrato, pelo
  mesmo `inPeriodByDate` do card.

## Testes

`test/widget/expensesScreen_test.dart` (o gesto, a confirmação, editar troca a
linha, data fora do período sai, voltar sem salvar não muda, a manutenção igual)
e o grupo `editar` em `addSupply_test.dart` e `addMaintenance_test.dart`. O
teste que protege a decisão 1 injeta os dois caminhos e exige o do cadastro com
**zero** chamadas — fazer a edição voltar a passar por ele derruba quatro
testes.

## Fora de escopo

- Corrigir o relato de preço já mandado ao posto (as regras não deixam, de
  propósito).
- Editar a data de uma manutenção (o formulário nunca teve o campo).
- Editar ou excluir de outros lugares além do extrato.
