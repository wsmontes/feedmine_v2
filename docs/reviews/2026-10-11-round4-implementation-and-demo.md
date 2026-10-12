# Rodada 4 — implementação e demonstração

Data: 2026-10-11. Autor: sessão OMP. Plano registrado antes de editar: `2026-10-11-round4-plan.md`.

## 1. Expansão automática da janela (P0 do PO) — implementada e demonstrada

- **Contrato:** novo caso `FeedPresentationAdmission.publishedGrowth` — sem observação de scroll, sem
  scroll simulado; acrescenta **apenas** os cards já publicados após a cauda admitida, limitado pela
  capacidade de avanço congelada; âncora, ponto de leitura, ordem e itens já admitidos intactos; janela
  sem novidade é no-op (`Sources/FeedMineRuntime/FeedPresentationAdmission.swift`,
  `FeedSession.admitPublishedGrowth`).
- **Runtime quem admite:** o host pede o crescimento depois de instalar publicação/oportunidade e no
  retorno da evidência de aquisição (`FeedMineApp/FeedMineApp/AppComposition.swift`:
  `schedulePublishedGrowth`, `growAdmittedWindowIfPublished`, chamadas em `launch`, `viewport`,
  `foreground`).
- **Demonstração (executada):** catálogo real (77.443), rede real (feeds públicos), store novo:

```
15:08:56.046  installed cards=1  ... order=1
15:08:56.387  installed cards=1  ... order=1
15:08:56.402  installed cards=17 ... order=2   <- crescimento automático, sem gesto
```

Contadores da execução: `received=0 completed=0 backward=0` — nenhum gesto. Vídeo:
`R4-expansao-automatica.mp4`; captura: `R4-feed-preenchido-sem-gesto.png` (BBC World + BBC Science +
o próximo card **parcialmente visível**, exatamente a indicação de continuidade pedida pelo PO).

Antes da mudança, essa mesma configuração instalava **1 card** e ficava assim (rodada 3, §1.1).

- **Teste novo:** `FeedPresentationAdmissionTests.testPublishedGrowthAppendsWithoutAGestureAndKeepsTheAnchor`
  (acrescenta +2, preserva identidade/ordem/âncora/contexto/edição, e repetir é no-op).

## 2. Estados honestos de espera e recuperação

Textos exatamente como o PO aprovou (`Sources/FeedMineUI/FeedLoadingView.swift`):

|Estado|Tela|
|---|---|
|`.idle` / `.pending`|"Descobrindo histórias para você…"|
|`.preparing(progress)`|`FeedPreparationView` (evidência real: fontes, manchetes, cards prontos)|
|`.deferred`|"Procurando mais novidades…" + "Ainda não encontramos conteúdo suficiente. Vamos tentar novamente em instantes."|
|`.unavailable`|"Ainda não encontramos histórias para você." + **Tentar novamente** + **Ajustar interesses**|
|`.unreachable` (novo)|"Não foi possível conectar." + "Não conseguimos buscar novas histórias agora." + **Tentar novamente**|
|`.failed(message)`|mensagem verbatim (falhas não-transporte, ex. catálogo)|

- **Falha de conexão só quando comprovada:** `reportFailure` decide por evidência de transporte. Medido:
  com o transporte bloqueado o erro chega em `kCFErrorDomainCFNetwork` 310, não em `NSURLErrorDomain`;
  a primeira versão do predicado não pegava esse caso (a tela mostrou "Falha ao atualizar o feed") e foi
  corrigida para ler os dois domínios. Vídeo do estado correto: `R4-recuperacao-conexao.mp4`; captura:
  `R4-estado-sem-conexao.png`.
- **Ações são reais:** `Tentar novamente` cancela o agendamento pendente e dispara uma oportunidade de
  verdade (`FeedAssociation.retryNow()` → mesmo caminho do foreground); `Ajustar interesses` abre o fluxo
  existente que possui os interesses (Ajustes → preferências de descoberta). Nenhuma das duas substitui um
  feed já apresentado: a superfície de ausência só existe quando não há apresentação.
- **Rótulos derivados corrigidos:** `.unavailable` dizia "Sem conexão" (errado, agora "Sem histórias") e
  `.unreachable` diz "Sem conexão".

## 3. Verificação executada

- `swift test`: **1185 testes, 1 pulado, 0 falhas** (inclui o caso novo de crescimento).
- `Tests/ArchitectureSmokeTests/FeedScreenRenderingTests`: expectativas atualizadas para os textos
  aprovados e para o novo estado; a fronteira de UI continua honesta — o token proibido `retry` levou o
  callback a se chamar `onTryAgain`, em vez de afrouxar o teste.
- Build do app: `xcodebuild … build` → **BUILD SUCCEEDED** (`R4-build.log`).
- Demonstrações: crescimento automático e estado sem conexão, ambas com vídeo, catálogo real e transporte
  controlado apenas onde o Codex pediu (falha determinística), identificadas separadamente.

## 4. Isolamento do benchmark (entregue por fatia delegada, verificada)

- `scripts/verify_product_catalogue.sh` (novo): recusa `bench_corpus` e identidade diferente de 77.443;
  testado no app real (exit 0) e contra um catálogo sintético marcado (exit 1).
- `bench/run.sh` + `scripts/soak.py`: execução sem device nomeado passa a criar/usar um simulador
  dedicado "FeedMine Bench" (`FEEDMINE_BENCH_SHARED_DEVICE=1` mantém o comportamento antigo); comando de
  reinstalação do build de produto impresso em toda saída, inclusive em falha; `bench/EVALUATOR.sha256`
  re-congelado (o runner verifica a linha).
- `docs/IOS_RUN.md` + `README.md`: verificação obrigatória antes de qualquer avaliação de produto.

## 5. Bloqueio honesto: commits

Não commitei. A árvore tem **trabalho não commitado de outra sessão entrelaçado nas mesmas funções**
(131 entradas sujas; só `AppComposition.swift` tem +1042 linhas de outra origem; `FeedMineApp.swift`
+191; `FeedSession.swift`, `FeedScreen.swift` e `FeedScreenRenderingTests.swift` também têm hunks
alheios). Tentei seleção por hunk: os hunks do meu trabalho **contêm linhas da outra sessão** nas mesmas
regiões (as funções `install`/`viewport`/`foreground`/`recovery` foram editadas pelos dois), então nem a
seleção por caminho nem por hunk produz um commit que contenha só o meu trabalho. Uma seleção por linha
produziria um patch que não aplica limpo, porque as linhas de contexto do índice ainda são as de HEAD.

Opções, se o commit for obrigatório: (a) commit de toda a árvore — exige autorização explícita do usuário,
que as regras do repositório pedem para qualquer commit; (b) a outra sessão commitar primeiro e eu
commito por cima; (c) eu preparo um patch linha a linha para revisão, ciente de que precisará ser
aplicado à mão sobre o estado do índice.

## 6. Limitações

- O estado `.unavailable` (caminhada sem histórias elegíveis) **não** foi demonstrado em execução real —
  só o estado de conexão. A evidência de `.unavailable` e das duas ações é a do teste de renderização
  (U10), não uma execução no simulador.
- A jornada de onboarding com catálogo real **não pôde** ser repetida nesta rodada: a árvore de
  acessibilidade do simulador parou de expor a tela do app no meio da sessão (17 nós, só a moldura da
  janela) e o arrasto sintético não é entregue ao app. O crescimento foi medido na configuração de rede
  real (feeds públicos BBC), que exercita o mesmo caminho de publicação.
- Bateria de UI do esquema do app: não executada nesta rodada (só o pacote).
