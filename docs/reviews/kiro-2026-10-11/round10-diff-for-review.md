# Rodada 10 — diff para revisão (K-06) — branch `omp/round10-diff-for-review`

**O que esta branch é:** um pacote de **análise** para revisão estática do diff da rodada 10. Ela **não** contém
código aplicado, **não** altera `main` e **não** deve ser mesclada. Nasceu de `main` e carrega apenas os dois
arquivos abaixo, mais este documento.

**O que esta branch não é:** um patch aplicável. A base local de onde o diff saiu está **63 commits atrás de
`origin/main`** e a árvore de trabalho carrega **trabalho não-commitado de sessões anteriores** — misturado, nos
mesmos arquivos, com as mudanças da rodada 10.

## Entrelaçamento declarado (números medidos, não estimados)

|Arquivo|Situação|Números|
|---|---|---|
|`Sources/FeedMineUI/EditorialInvitationCadence.swift`|**novo**, integralmente da rodada 10|novo|
|`Sources/FeedMineUI/FeedEditorialInvitationView.swift`|**novo** no worktree (base: introduzido numa rodada anterior hoje)|novo|
|`Sources/FeedMineUI/Settings/ReaderDiscoveryPreferencesView.swift`|**novo** no worktree|novo|
|`FeedMineApp/FeedMineAppTests/EditorialOfferBudgetUITests.swift`|**novo**, integralmente da rodada 10|novo|
|`FeedMineApp/FeedMineApp/AppComposition.swift`|**misturado**: trabalho local anterior + rodada 10|1077+/113− no diff contra a base|
|`FeedMineApp/FeedMineApp/FeedMineApp.swift`|**misturado**|257+/17−|
|`FeedMineApp/FeedMineAppTests/CompositionTests.swift`|**misturado**|548+/4−|
|`FeedMineApp/FeedMineApp.xcodeproj/project.pbxproj`|**misturado** (só as quatro entradas do alvo são da rodada 10)|34+/14−|
|`FeedMineApp/FeedMineAppTests/DiscoveryBenchmarkTests.swift`|existe na base remota; **novo neste worktree** (o bench é congelado)|novo no worktree|
|`bench/oracle.py`, `bench/EVALUATOR.sha256`|idem (congelados; o hash foi re-congelado pela rodada 10)|novo no worktree|

## Como revisar (o que é, de fato, da rodada 10)

O documento `docs/reviews/2026-10-11-round10-changes-inventory.md` nomeia **cada símbolo e cada linha de âncora**
que a rodada 10 tocou, arquivo por arquivo. É ele que separa o meu trabalho do trabalho anterior dentro dos
arquivos misturados. O patch ao lado (`round10-code-diff.patch`) tem três partes:

- **Parte A** — arquivos que **não existem** na base remota: conteúdo integral; são inteiramente da rodada 10 (ou
  introduzidos hoje por ela).
- **Parte B** — arquivos que **existem** na base remota: o diff direto contra a base local, que **contém trabalho
  local anterior misturado**. A revisão deve olhar os hunks nomeados no inventário; qualquer coisa fora deles é de
  outra sessão.
- **Parte C** — arquivos congelados do benchmark: existem na base remota, mas são novos neste worktree. A revisão é
  do **diff**, não da aplicação do patch.

## Referências de evidência (publicadas em `main`)

- `docs/reviews/2026-10-11-round10-consolidated-report.md` — relatório consolidado da frente e as limitações
  declaradas.
- `docs/reviews/2026-10-11-round10-alternative-a-evidence.md` — tudo o que foi executado, com comandos e números
  (inclui o parecer final do PO, §18, e o gate B04 PASS completo, §17).
- `docs/reviews/2026-10-11-round10-alternative-a-plan.md` — o plano e as regras registradas antes de editar.

## Limites, para não induzir a conclusão errada

- O diff **não é aplicável** como está e não foi feito para ser.
- `FeedMineApp/FeedMineAppTests/CompositionTests.swift` é o arquivo com maior risco de conflito: a rodada 10
  acrescentou três testes e reforçou um quarto entre as linhas ~925 e ~1010 (nomeados no inventário).
- Os arquivos congelados do benchmark foram alterados **com autorização explícita do arquiteto**, com o
  `bench/EVALUATOR.sha256` re-congelado; o **critério de produto não mudou**.
