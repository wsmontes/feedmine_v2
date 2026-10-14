# Build 43 no TestFlight interno (2026-10-14)

## Enviado

`1.0 (43)` = `49ad6341` (três commits sobre a 42: `bb78ba86`, `5c76a747`, `49ad6341`), tag anotada
`ios/1.0-build.43-49ad6341`. Build anterior no canal: `1.0 (42)`.

## O que a 43 corrige

**Achados da revisão independente do estado de fim de conteúdo (`7fa07b3e`)** — a revisão não achou
nenhuma instalação falsa do fim, mas achou estes:

1. **O quinto fato (o principal).** Os quatro fatos não olhavam a reserva pronta à frente do leitor.
   Com `readyAhead` entre 17 e 32, uma aquisição podia settlear `.noEligibleTargets` com o episódio
   local esgotado **enquanto cards publicados ainda estavam além da janela desenhada** — o bloco
   apareceria depois de um card que não é o último, e o leitor encontraria o resto das histórias
   acima dele. `noStoryAhead` só é verdadeiro com `readyAhead == .exact(0)`; desconhecido ou
   `.atLeast` nunca qualificam. É a segunda metade da regra que o PO ratificou ("sem itens elegíveis
   aguardando preparação/publicação"), e só torna o fim **mais difícil** de afirmar.
2. **Posse do drain.** `settledEligibleOffer()` passa a ser lido só depois que o drain soltou a posse
   (`causalExecution == nil`), para uma segunda oportunidade não instalar o fim a partir de um drain
   que ainda pode agir.
3. **Ordem.** O fim é decidido **antes** de a janela crescer, para que um crescimento que admitiu
   cards **retrate** o fim na mesma oportunidade, em vez de o fim ser reinstalado por cima.
4. **Beco sem saída.** `FeedEndOfContentView` só oferece uma rota quando o host deu a ação, e a
   superfície sem cards agora desenha o **mesmo bloco** em vez da frase sozinha — sem botão que
   promete o que o app não pode cumprir, e com a cópia num único lugar.

**Instrumentação aceita do QA:** o trace passa a registrar as **recusas** de convite
(`editorial_refusal`), não só as ofertas colocadas. A política já calculava o motivo e o jogava fora;
sem isso a cláusula de frequência que o PO pediu auditar mostra só metade dos fatos.

## Prova que acompanha este envio

| Prova | Resultado |
|---|---|
| Suíte do pacote | **1.263 testes, 1 skipped, 0 falhas** |
| Jornada iOS do fim de conteúdo | `EndOfContentUITests`: **Executed 1 test, 0 failures** |
| Build do app | `BUILD SUCCEEDED` |

## Limites declarados

- **B05 segue FAIL** e é **decisão de produto**, não defeito: o app não perde o salvo nem falha em
  restaurar — ele restaura o *milestone* do contexto, que aqui continuou no primeiro card da edição.
  O A→B→A do driver congelado **nunca roda** (o menu não tem o item "Salvos"), então a cláusula que
  "passa" é vacuamente verdadeira. Registro completo em
  `docs/reviews/2026-10-14-b05-reopen-and-the-driver-navigation.md`.
- **B04 segue INCOMPLETO** (a medida do ócio não foi possível) e **B06** exige iPhone físico.
- Os gates B01/B03/B02 estão sendo re-rodados neste commit; este documento não afirma veredito que
  ainda não tenha saído.
