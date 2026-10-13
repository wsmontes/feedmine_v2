# FeedMine

**INSTRUÇÃO ATUAL PARA AGENTES (2026-10-11):** [Diretriz de execução V2 após checkpoint B05](docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md). Leia antes de iniciar novas correções ou mais documentação; preservar a evidência canônica de B05 e atacar descoberta real, runway e os gates restantes sem alterar a régua.


**Status documental (2026-10-13):** O catálogo público gerenciado em [wawasoft/feed-repository](https://github.com/wawasoft/feed-repository) é a **fonte da verdade** ([PD-10](docs/product/PRODUCT_DECISIONS_2026-10-09.md), [INV-18](docs/architecture/PRODUCT_INVARIANTS.md)). O bundle atual usa o catálogo derivado da revisão pública 5, com inventário e artefato compilado validados por SHA-256. `scripts/fetch-catalog.sh` é legado; o pipeline atual é `scripts/bootstrap_catalog.py`. A sincronização e a travessia progressiva já têm implementações no código, mas release de produção continua condicionada às provas B01–B06. Consulte [a matriz de entrega atual](docs/reviews/2026-10-13-production-delivery.md); relatórios antigos não certificam o HEAD atual.


**Por que existe:** fazer a internet aberta voltar a ser um lugar onde é gostoso descobrir coisas. O objetivo é oferecer descoberta contínua de conteúdo interessante, inclusive de fontes que a pessoa ainda não conhece — sem exigir que ela primeiro configure um leitor RSS. Leia o [norte de produto](docs/product/PRODUCT_NORTH_STAR.md) antes de decidir funcionalidades, prioridades ou mudanças na experiência de leitura. O [benchmark de aceitação vigente](docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md) fixa as provas de produto: agentes devem implementá-las, executá-las e corrigir falhas autonomamente, sem pedir aprovação intermediária nem baixar a exigência. A [especificação de produto F02](docs/product/F02_DISCOVERY_FEED_ONBOARDING_PRD.md) define o primeiro contato como um feed normal, divertido e interativo, não um formulário obrigatório de onboarding; descreve experiência, interface, linguagem e aceitação, não implementação.

FeedMine é um feed reader local-first/offline-first, sem servidor próprio. O pacote Swift contém dez módulos; o aplicativo iOS separado usa esses módulos por referência local.

Abra `FeedMineApp/FeedMineApp.xcodeproj`, selecione o scheme compartilhado **FeedMine** e um simulador iOS 18 ou posterior. Não é necessário configurar uma equipe para compilar no simulador. Para um dispositivo físico, configure sua assinatura de desenvolvimento no Xcode.

O aplicativo restaura publicação local antes de qualquer aquisição. Sem história publicada, usa ColdFeedBootstrap, preparação com evidências reais e publicação incremental. O Runway mantém reserva local, e a mídia é preparada antecipadamente para cards com imagem local ou layout text-only. Cards com link abrem o artigo. O catálogo derivado da revisão pública 5 (77.443 fontes) é empacotado no app com descritor e integridade verificados; fontes selecionadas, contextos, busca local e bookmarks persistem offline. A manutenção da cauda preserva cards já vistos. Consulte o relatório de validação para resultados e pendências.

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

TestFlight interno confirmado pela API Apple: **1.0 (31)**, commit `5dcc4cab0de8c88a0afe23a23009b368a3de5615`, estado `VALID` / `IN_BETA_TESTING`, grupo **WawaTesters**. Disponibilidade interna não certifica B01–B06 nem aprovação de produção. Evidência atual: [status de entrega](docs/reviews/2026-10-13-production-delivery.md).
