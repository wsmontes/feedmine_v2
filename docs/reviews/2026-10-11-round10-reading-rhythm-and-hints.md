# Rodada 10 — ritmo de leitura e "FeedMine sugere" (diagnóstico e proposta, 2026-10-11)

Sem alterar código. Toda afirmação abaixo tem dono: código com `file:line`, ou medição de uma corrida real já
gravada neste repositório.

## 1. O que a dica é, e onde ela entra

- O bloco é `FeedEditorialInvitationView` (`Sources/FeedMineUI/FeedEditorialInvitationView.swift:15`): título
  "FeedMine sugere", a pergunta sobre o assunto da fonte, e os botões "Mais de X" / "Menos de X" / "Esconder
  dicas" (e, depois de responder, "Você pediu…" + "Desfazer").
- Ele é inserido **dentro da lista do feed, imediatamente depois do card que o hospeda**, como filho irmão do
  card (`Sources/FeedMineUI/FeedScreen.swift:104` e `:130`), pela closure `editorial:`.
- O **espaço é do leitor**: "esconder" não remove o bloco, aplica `opacity(0)` + `allowsHitTesting(false)`
  (`FeedMineApp/FeedMineApp/FeedMineApp.swift:684-685`). O comentário registra o motivo com número: tirar as
  linhas do feed **moveu o card ancorado em 128 pt** ("measured twice").

## 2. A regra de frequência (não é por card, não é por relógio)

`FeedMineApp/FeedMineApp/FeedMineApp.swift:649-685` decide, e as condições são todas necessárias:

1. a dica só existe a partir do **quarto card** (`index >= 3`);
2. a fonte do card tem de resolver a um assunto do catálogo (`editorialSubject`);
3. a fonte precisa **diferir da fonte do card anterior** — a dica aparece "where the feed moves to a subject";
4. o assunto não pode estar já respondido (de sessões anteriores);
5. **uma oferta por assunto por sessão** (`cadence.subjects`), com o bloco respondido mantido — é nele que mora
   o caminho de volta.

Não há cadência fixa, stride nem cooldown. O código diz por que não há, e o motivo é medido:
*"a fixed cadence offered the same subject over and over and, in one whole profile, never offered a second one
(the acceptance driver could declare only one of the two answers the benchmark requires)"*.

Nem o card nem a dica têm token de altura (`Sources/FeedMineUI/FeedDesignTokens.swift`: o único token de altura
é `Measurement.workFeedbackHeight = 44`). **Não existe no código nenhuma relação "altura de card"** — a premissa
da rodada 1 ("uma dica com altura de card depois de cada artigo") não está representada.

## 3. Medição sobre conteúdo real (corrida já gravada no repositório)

Fonte: `bench/run/20261011T065200Z/` (2026-10-11 06:52Z, jornada B03-A com catálogo real, trinta minutos de
avanço). Números lidos de `B03-A.phases`, `B03.verdict.json` e `trace.jsonl` (17.167 linhas):

|Fato medido|Valor|
|---|---|
|Avanços efetivos|4.570 (esperado ≥1.800)|
|Candidatos|874, **todos preparados** (0 pendentes, 0 texto)|
|Registros de janela|2.574 (2.571 com cards)|
|`with_subject` vs `cards`|**iguais em todas as janelas com cards** — todo card cuja fonte resolve a um assunto|
|Pares consecutivos da mesma fonte|**0 no trace inteiro**|
|Assuntos conhecidos na sessão|até 120|
|Respostas dadas|2 (`…/mental-health` e `…/world-news`, ambas `more`)|
|Esconder as dicas|`hide-stable: true`, `hide-frames: 302->302` (o card ancorado não se moveu)|
|Cláusulas do gate|5, todas PASS — **nenhuma sobre a dica**|

Leitura honesta desses números, juntos:

- como **todo** card tinha assunto e **não houve** par consecutivo da mesma fonte, as condições (2) e (3) da
  regra **não freiam nada** nesse conteúdo;
- o único freio que resta é "**uma oferta por assunto por sessão**" — ou seja, o teto real de dicas por sessão é
  o número de assuntos distintos por onde a leitura passa (a sessão conheceu 120);
- cada oferta mostrada custa **128 pt** (medidos); 120 ofertas seriam ≈ 15.360 pt ≈ **16 telas** de dica numa
  tela de 956 pt;
- o gate não mede nem frequência nem espaço: nada impede esse teto de ser alcançado.

## 4. O que acontece quando o leitor responde

`AppComposition.voteOnTopic(nodeKey:level:)` grava
`settings.discoveryProfile.topicPreferences["topic:<node>"] = .more/.less` na única linha `reader_preferences`
(tabela `reader_preferences`, `settings_json`) e **reconstrói a sessão** (`replaceSession`) para a descoberta
olhar noutro lugar. A edição/janela visível **não** é retratada nem reordenada. O bloco passa ao estado
respondido, com "Desfazer". **Não há toast, banner nem haptic.** A resposta persiste entre reinícios, é lida
pelo pool de descoberta (`more` = interesse; `less` = exclusão), pela página de preferências de descoberta e
pela criação de feed curado. **Não há decaimento**: `adjustFromOpens` é declarado e propagado, mas nenhum código
de ranking o consome; o único caminho de volta é o "Desfazer" explícito.

## 5. Acessibilidade e fonte ampliada

- O bloco **não se declara elemento de acessibilidade**, de propósito, e o motivo está escrito: *"a container
  that declares itself an accessibility element hides its own buttons from the tree — the app offered thousands
  of invitations that no query could find, which also means a reader with VoiceOver could never answer one"*
  (`FeedEditorialInvitationView.swift:84-87`). É a mesma classe de defeito que a rodada 9 encontrou em um
  contêiner que engolia os identificadores dos filhos.
- **Achado novo (código, não verificado com VoiceOver ligado aqui):** quando o leitor escolhe "Esconder dicas",
  o bloco fica invisível apenas para quem vê — não há `accessibilityHidden` no caminho do esconder
  (`FeedMineApp.swift:684-685`). Com `opacity(0)` + `allowsHitTesting(false)` os botões continuam na árvore de
  acessibilidade, então um leitor com VoiceOver pode alcançar e acionar "Mais de X"/"Menos de X" de um bloco
  invisível.
- **"Esconder" não tem volta na interface:** `setEditorialTipsHidden(_:)` só é chamado com `true`
  (`FeedMineApp.swift:713-714`); nenhum chamador passa `false`, apesar do comentário em
  `Sources/FeedMineDomain/ReaderSettings.swift:52-53` prometer o retorno pelo "Conhecer o FeedMine".
- **Fonte ampliada:** o bloco é totalmente intrínseco — `footnote/subheadline/caption/caption2`, sem
  `lineLimit`, `fixedSize` nem `minimumScaleFactor` (`FeedEditorialInvitationView.swift:37-80`). Ele cresce com
  o tamanho de texto do leitor e não trunca; **os 128 pt são do tamanho padrão** e não valem para tamanhos
  maiores (e foram medidos na cópia em português, antes da localização da rodada 9).

## 6. A premissa desta rodada, conferida

- Rodada 1 (`docs/reviews/2026-10-11-ux-diagnosis-round1.md:143-145`): "as dicas 'FeedMine sugere' quebram o
  ritmo — uma dica depois de **cada** card, altura de card".
- Rodada 2 (`docs/reviews/2026-10-11-cold-start-diagnosis-round2.md:98-102, 205`) **retrata em parte**: as dicas
  foram vistas sobre o catálogo de benchmark e precisam ser reconferidas.
- Hoje: o código não tem cadência por card; a corrida real mostra todo card elegível **pelo assunto**, zero pares
  consecutivos da mesma fonte, e apenas **duas** ofertas respondidas dentro da caminhada limitada do benchmark.
  O que existe é "uma oferta por assunto por sessão", sem teto de sessão.
- Nenhum documento tem regra numérica de proporcionalidade ("no máximo 1 a cada N cards") e nenhum teste fixa
  frequência ou espaço.

## 7. Duas alternativas

### A) Manter a dica no fluxo, com orçamento e ritmo declarados — **recomendada**

A dica continua depois do card (é ali que a resposta vive, e é ali que vive o "Desfazer"). O que muda é ela
**deixar de ser ilimitada** e passar a ter regra de produto, não só de implementação:

1. **Orçamento de sessão**: no máximo K ofertas por sessão (e não "uma por assunto", que é ilimitado).
2. **Espaçamento**: no máximo uma oferta a cada N cards percorridos.
3. **Prioridade**: com o orçamento apertado, oferecer primeiro o assunto **não respondido** de maior peso; um
   assunto já respondido não reabre.
4. **Forma proporcional**: a primeira oferta da sessão pode ter a pergunta completa; as seguintes usam a forma
   curta (título + dois botões), que é menor que os 128 pt medidos.
5. **Regra declarada e medida**: derivar K e N da própria medição (128 pt por bloco, cards por tela) e prender
   ambos num teste/gate — hoje nenhum gate olha para isso.

Custo: mantém a interrupção, mas limitada e previsível. Ganho: preserva o sinal que a descoberta aprende com a
resposta (o PRD do F02 chama a pergunta de "ocasional" e pede que as intervenções didáticas "fiquem menos
frequentes" — é exatamente isto).

### B) Tirar a dica do fluxo de leitura

A dica nunca entra entre cards:

1. **Afordância no próprio card** (chip discreto na linha de ações) que abre a pergunta **sob demanda**; e/ou
2. **Painel "FeedMine sugere"** aberto pelo leitor no cabeçalho, listando os assuntos por onde ele passou;
3. Nudge opcional: uma **linha** (44 pt, o token `workFeedbackHeight` que já existe) depois de N cards lidos,
   que abre o painel.

Custo: a resposta fica menos visível (e ela é o sinal de aprendizado do motor), exige uma superfície nova e um
jeito de o leitor descobrir que existe. Ganho: **zero** interrupção do gesto de leitura e nenhum slot de 128 pt
no feed; a "ocasionalidade" deixa de depender de heurística e passa a ser escolha do leitor.

**Recomendação: A agora, B como destino se a medição mostrar que a oferta continua interrompendo.** Motivo:
A corrige o problema real (ausência de teto e de regra de produto) sem perder o sinal de descoberta, e é
verificável com o que já existe — o journey B03 já caminha o feed e responde ofertas; falta apenas uma cláusula
de gate que meça frequência e espaço, que hoje não existe. B é a resposta certa se, com o orçamento de A, a
leitura ainda parar.

## 8. Parecer do PO (2026-10-11): **A APROVADA para implementação**

- **(a) Alternativa A aprovada** — "manter o 'FeedMine sugere' no fluxo de leitura, porém com presença
  controlada": primeira sugestão com a pergunta completa, posteriores em formato compacto, prioridade para
  assuntos não respondidos, card ancorado preservado, respostas aplicadas à descoberta futura sem reorganizar o
  feed visível. Princípio: "sugestões são oportunidades ocasionais de melhorar a descoberta, não parte
  obrigatória de cada mudança de assunto". E uma ressalva metodológica que fica registrada: **os 120 blocos
  demonstram a ausência de controle de volume, mas não provam, isoladamente, interrupção excessiva** —
  "precisamos medir a experiência, não apenas contar blocos".
- **(b) Orçamento: ADAPTATIVO, com teto máximo.** Regras de produto: leitor ignora → reduzir progressivamente a
  frequência; leitor responde → permitir novas oportunidades com intervalos confortáveis; leitor **esconde** →
  nenhuma outra sugestão até ele reativar; leitor continua rolando → priorizar conteúdo; assunto respondido →
  não repetir. A frequência considera **cards efetivamente percorridos, exposição e respostas, não timers
  arbitrários**. Teto por sessão aceito como proteção, mas "K e N devem ser parâmetros de calibração, não a
  lógica central". **Não autorizado** criar um subsistema novo de personalização: reaproveitar sinais e
  mecanismos existentes.
- **(c) Correções autorizadas:** acessibilidade é **P0** — esconder tem de remover os elementos da árvore de
  acessibilidade (VoiceOver não pode alcançar controles invisíveis); reexibição é **P1** — reativar em "Mais" ou
  nas preferências existentes, com opção clara ("Mostrar sugestões do FeedMine"), persistente entre reinícios, e
  **sem criar painel novo** só para isso.
- **Critérios de aceite** (os oito do parecer): sugestões não aparecem indiscriminadamente a cada assunto novo;
  o ritmo se adapta à interação ou à ausência dela; existe limite efetivo de frequência e volume; as sugestões
  compactas ocupam menos que os 128 pt atuais; mostrar/responder/desfazer/esconder preservam a posição do leitor;
  esconder remove os controles da acessibilidade; reativar restaura o comportamento; o feed continua navegável
  sem depender das sugestões. Testes automatizados com instrumentação são aceitos inicialmente, **mas a
  validação visual no simulador deve ocorrer antes do aceite final, quando o ambiente de execução estiver
  disponível**.
- **Decisão para o Codex:** APROVADO PARA IMPLEMENTAÇÃO — Alternativa A. **Não implementar B nesta rodada.** Se A
  continuar interferindo perceptivelmente, reavaliar a remoção das sugestões do fluxo principal.

## 9. O que **não** consegui re-medir hoje, e por quê

- **Uma nova passada de leitura na build atual**: o simulador não aceita entrada por este caminho (a ponte de
  acessibilidade do Simulator expõe só o cromo da janela, e a sessão de controle de desktop está fechada), e
  recompilar está bloqueado por disco (799 MiB livres; um build de teste precisa de ~1,2 GiB). A máquina já
  estava com o disco cheio antes desta rodada.
- **A altura renderizada do bloco na build atual**: os 128 pt são a medição que o próprio código registra
  (tamanho padrão, cópia em português).
- **VoiceOver de verdade** sobre o esconder: o achado do §5 é leitura de código, não observação com VoiceOver.

Re-medição barata quando houver espaço: a jornada B03 existente (`DiscoveryBenchmarkTests`, perfil A) já grava
`answered:*`, `hide-stable` e `hide-frames`, e o app grava `trace.jsonl` com `with_subject`/`tips_hidden` por
janela — o instrumento já existe; o que falta é a cláusula de gate.
