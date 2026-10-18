# FeedMine

**MONITOR EXTERNO DE ARQUITETURA (consultivo, a cada 2 horas):** antes de uma nova rodada de planejamento, consulte o parecer atualizado na branch `monitor/architecture` com `git fetch origin monitor/architecture` e `git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md`. O relatório pode apontar regressões e prioridades, mas **não** altera a hierarquia de decisões vigente, não autoriza modificações nem substitui provas no Mac. O arquivo do monitor está numa branch separada e não aparece na `main`.

**INSTRUÇÃO ATUAL PARA AGENTES (2026-10-11):** [Diretriz de execução V2 após checkpoint B05](docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md). Leia antes de iniciar novas correções ou mais documentação; preservar a evidência canônica de B05 e atacar descoberta real, runway e os gates restantes sem alterar a régua.


**Status documental (2026-10-13):** O catálogo público gerenciado em [wawasoft/feed-repository](https://github.com/wawasoft/feed-repository) é a **fonte da verdade** ([PD-10](docs/product/PRODUCT_DECISIONS_2026-10-09.md), [INV-18](docs/architecture/PRODUCT_INVARIANTS.md)). O bundle atual usa o catálogo derivado da revisão pública 5, com inventário e artefato compilado validados por SHA-256. `scripts/fetch-catalog.sh` é legado; o pipeline atual é `scripts/bootstrap_catalog.py`. A sincronização e a travessia progressiva já têm implementações no código, mas release de produção continua condicionada às provas B01–B06. Consulte [a matriz de entrega atual](docs/reviews/2026-10-13-production-delivery.md); relatórios antigos não certificam o HEAD atual.


**Por que existe:** fazer a internet aberta voltar a ser um lugar onde é gostoso descobrir coisas. O objetivo é oferecer descoberta contínua de conteúdo interessante, inclusive de fontes que a pessoa ainda não conhece — sem exigir que ela primeiro configure um leitor RSS. Leia o [norte de produto](docs/product/PRODUCT_NORTH_STAR.md) antes de decidir funcionalidades, prioridades ou mudanças na experiência de leitura. O [benchmark de aceitação vigente](docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md) fixa as provas de produto: agentes devem implementá-las, executá-las e corrigir falhas autonomamente, sem pedir aprovação intermediária nem baixar a exigência. A [especificação de produto F02](docs/product/F02_DISCOVERY_FEED_ONBOARDING_PRD.md) define o primeiro contato como um feed normal, divertido e interativo, não um formulário obrigatório de onboarding; descreve experiência, interface, linguagem e aceitação, não implementação.

FeedMine é um feed reader local-first/offline-first, sem servidor próprio. O pacote Swift contém dez módulos; o aplicativo iOS separado usa esses módulos por referência local.

Abra `FeedMineApp/FeedMineApp.xcodeproj`, selecione o scheme compartilhado **FeedMine** e um simulador iOS 18 ou posterior. Não é necessário configurar uma equipe para compilar no simulador. Para um dispositivo físico, configure sua assinatura de desenvolvimento no Xcode.

O aplicativo restaura publicação local antes de qualquer aquisição. Sem história publicada, usa ColdFeedBootstrap, preparação com evidências reais e publicação incremental. O Runway mantém reserva local, e a mídia é preparada antecipadamente para cards com imagem local ou layout text-only. Cards com link abrem o artigo. O catálogo derivado da revisão pública 5 (77.443 fontes) é empacotado no app com descritor e integridade verificados; fontes selecionadas, contextos, busca local e bookmarks persistem offline. A manutenção da cauda preserva cards já vistos. Consulte o relatório de validação para resultados e pendências.

Coleta inicial: `CollectionLaunchSettings(initialParallelism:)` fornece o orçamento de alvos (padrão 48);
o coordenador executa no máximo 8 alvos simultâneos. `AcquisitionPlanningResources` continua sem defaults.
A composição ordena alvos por qualidade/atividade do catálogo e latência medida quando disponível; sem sinais,
preserva a ordem fornecida. Transições de prontidão de mídia notificam a oportunidade local existente do runway,
sem publicar mídia pendente nem criar outro pipeline. Os testes de fixture fixam ≥10 cards em ≤3 s com
`FeedLaunchWitness`, recuperação após prontidão e ordenação estável; não certificam latência de pixels no aparelho.

Antes de compilar um clone, prepare o catálogo público com `python3 scripts/bootstrap_catalog.py` e instale o par validado `build/catalog-bootstrap/catalog.sqlite` + `catalog.manifest.json` em `FeedMineApp/FeedMineApp/Resources/`, conforme [a procedência do catálogo](FeedMineApp/FeedMineApp/Resources/CATALOG.md). `scripts/fetch-catalog.sh` é legado e baixa um snapshot incompatível com o descritor atual; não o execute para preparar uma release. Sem o par válido, a instalação do catálogo é recusada. Git LFS não é mais usado.

A rodada atual é verificada localmente, sem CI hospedada. Resultados e limitações ficam em [validação OMP/Codex](docs/reviews/OMP_VALIDATION_2026-10-09.md); a transferência do frontend V1 → V2 tem o seu próprio registro, superfície por superfície, em [evidência da transferência](docs/reviews/V1_V2_FRONTEND_TRANSFER_EVIDENCE.md), com o inventário de controles em `docs/v1-study/UI_TRANSFER_MATRIX.md`.

Verificação do pacote: `swift package describe`, `swift build`, `swift test`, `git diff --check`. A suíte do app roda no simulador pelo scheme **FeedMine**; os testes de UI de um caso por vez com `-only-testing:FeedMineUITests/FeedMineUITests/<nome>` (é assim que a evidência de cada superfície foi produzida), e a corrida completa do scheme é o portão final.

Veja [execução iOS](docs/IOS_RUN.md) e [arquitetura](docs/architecture/ARCHITECTURE.md).

Antes de avaliar UX/experiência em um build de simulador, rode `scripts/verify_product_catalogue.sh "$(xcrun simctl get_app_container booted com.feedmine.development app)"`: uma corrida do benchmark instala o app com o catálogo do corpus dentro dele e, fora da corrida, esse app parece não publicar nada (o script sai 1 e diz como reinstalar o build de produto).

## Pesquisa Apple — UI/UX, offline e confiabilidade

Documentação primária Apple com limites iOS e cenários verificáveis: [índice de pesquisa Apple](docs/research/APPLE_IOS_UI_UX_RELIABILITY_2026-10-10.md). A terceira onda de [F21–F27](docs/product/PRODUCT_AUDIT_APPLE_FRONTS_21_27.md) complementa F01–F20 em scene lifecycle, rede/offline, background, integridade local, SwiftUI, integrações e recursos; não altera B01–B06 ou o status de release.

## Ouro escondido da V1 — backlog de produto para V2

Análise de 15 oportunidades da V1 com código/linhas como evidência, V2 atual inspecionada e critérios de aceitação: [Garimpo V1: 15 oportunidades com prova no código](docs/v1-study/V1_HIDDEN_GEMS_PRODUCT_MINING_2026-10-10.md). Para executar sem copiar o runtime legado: [Briefs de implementação por jornada](docs/product/V1_GOLD_IMPLEMENTATION_BRIEFS_2026-10-10.md). Armadilhas arquiteturais que não devem ser trazidas: [Lista do que não portar](docs/v1-study/V1_GOLD_DO_NOT_PORT_2026-10-10.md). **Não há código novo nem certificação B01–B06 nesses documentos.**

## Avaliador congelado e TestFlight — verificação de 2026-10-13

Execute o benchmark por `scripts/run-discovery-benchmark.sh --gate B01 --profile A --profile B` (ou os demais gates). O launcher configura a origem de transporte no ambiente do app por `UITargetAppEnvironmentVariables` do `.xctestrun` gerado, fora do avaliador; `bench/run.sh`, driver, oráculo e corpus conservam os hashes congelados. Em iPhone físico, forneça `FEEDMINE_BENCH_DEVICE_UDID` e `FEEDMINE_BENCH_TRANSPORT_HOST` (host:porta do Mac).

TestFlight interno confirmado pela API Apple: **1.0 (32)**, commit `c6de80b7decca9a81a4888333521b696f84cf761`, estado `VALID` / `IN_BETA_TESTING`, grupo **WawaTesters**. Esta build corrige o travamento por cardinalidade variável de filhos no lazy layout. Disponibilidade interna não certifica B01–B06 nem aprovação de produção. Evidência atual: [status de entrega](docs/reviews/2026-10-13-production-delivery.md).

### PD10-P0C — preparação verificável de catálogo para novas releases

`fetch-catalog.sh` agora recusa explicitamente o catálogo V1. Em um checkout separado do compilador
V1, mantenha `build_catalog.py` **e** `catalog_identity.py` juntos e identifique seus bytes:

```sh
COMPILER=/absolute/path/to/legacy/scripts/build_catalog.py
COMPILER_SHA=$(shasum -a 256 "$COMPILER" | awk '{print $1}')
IDENTITY_SHA=$(shasum -a 256 "$(dirname "$COMPILER")/catalog_identity.py" | awk '{print $1}')
python3 scripts/bootstrap_catalog.py --compiler "$COMPILER" \
  --compiler-sha256 "$COMPILER_SHA" --identity-sha256 "$IDENTITY_SHA"
# Examine build/catalog-bootstrap/{provenance.json,state.json,build-report.json}.
cp build/catalog-bootstrap/{catalog.sqlite,catalog.manifest.json} FeedMineApp/FeedMineApp/Resources/
# Commit the tracked descriptor before release; catalog.sqlite is Git-ignored and is\n# instead bound to the commit/build by the archive's byte-level evidence.
scripts/release-testflight.sh --dry-run
```

O `catalog.sqlite` é intencionalmente ignorado pelo Git (atualmente maior que 100 MB),\nportanto o SHA Git sozinho **não** certifica seus bytes. A evidência de cada archive vincula\nGit SHA + manifesto público + SHA-256 do SQLite efetivamente distribuído.\n\nO preflight exige manifesto público atual acessível, inventário completo e OPMLs íntegros,
relatório e identidade do compilador, par do staging e par de Resources. O archive real é
revalidado antes de qualquer export/upload. Evidências legíveis por máquina ficam em
`.build/pd10-p0c-*.json`. O dry-run não exige credenciais do App Store Connect.
Essas verificações são somente de empacotamento e não alteram o first paint offline.

`scripts/publish_catalog_update.py` é uma operação **distinta**: use
`--source <editorial-root> --destination <public-checkout> --revision <nova-revisão>`
e os três argumentos do compilador acima. Sem `--apply` só inspeciona; mesmo com
`--apply` não faz commit, push, nem altera Resources.
O README externo de `wawasoft/feed-repository` ainda mostra apenas
`--destination` e promete copiar o catálogo para o app; sua correção necessita gate
separado: **P0C-PUBLISH-DOC — EXTERNAL BLOCKER**.
