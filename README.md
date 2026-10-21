# FeedMine

O FeedMine existe para fazer a internet aberta voltar a ser um lugar onde é gostoso descobrir coisas: abrir, encontrar conteúdo relevante e diverso, continuar lendo e voltar ao mesmo lugar, inclusive offline. Configurar assinaturas não é pré-requisito.

O aplicativo iOS é local-first/offline-first, sem servidor próprio de conteúdo. Usa os dez módulos do pacote Swift por referência local.

## Direção e contratos

Leia nesta ordem antes de decidir uma correção ou funcionalidade:

1. [Norte do produto](docs/product/PRODUCT_NORTH_STAR.md): a experiência que estamos tentando entregar.
2. [Decisões de produto](docs/product/PRODUCT_DECISIONS_2026-10-09.md): regras vinculantes de descoberta, mídia, publicação e catálogo.
3. [Invariantes](docs/architecture/PRODUCT_INVARIANTS.md) e [benchmark B01–B06](docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md): comportamentos e provas obrigatórios.
4. [Arquitetura](docs/architecture/ARCHITECTURE.md) e [dependências](docs/architecture/DEPENDENCY_RULES.md): os responsáveis existentes por cada fluxo.

A [diretriz de execução](docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md) manda fechar jornadas com correções pequenas e evidência observável. Planos, pesquisas, estudos da V1 e relatórios históricos não substituem esses contratos. Testes verdes não substituem a experiência do leitor.

Antes de planejar, consulte o monitor consultivo: `git fetch origin monitor/architecture` e `git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md`. O parecer não altera contratos nem certifica o código local; compare seus achados com o HEAD real.

## Executar e verificar

Abra `FeedMineApp/FeedMineApp.xcodeproj`, scheme **FeedMine**, em simulador iOS 18 ou posterior. O simulador não exige equipe de assinatura; dispositivo físico exige configuração no Xcode. Detalhes: [execução iOS](docs/IOS_RUN.md).

Antes de compilar um clone, prepare e instale o par validado `catalog.sqlite` + `catalog.manifest.json` em `FeedMineApp/FeedMineApp/Resources/`, conforme a [procedência do catálogo](FeedMineApp/FeedMineApp/Resources/CATALOG.md) e o procedimento abaixo. O catálogo gerenciado tem autoridade em [wawasoft/feed-repository](https://github.com/wawasoft/feed-repository), conforme PD-10/INV-18. `scripts/fetch-catalog.sh` é legado; use `scripts/bootstrap_catalog.py`.

Verificação do pacote: `swift package describe`, `swift build`, `swift test`, `git diff --check`. A suíte do app roda no scheme **FeedMine**; um teste de UI pode ser isolado com `-only-testing:FeedMineUITests/FeedMineUITests/<nome>`.

Antes de avaliar a experiência no simulador, confirme que o app usa o catálogo de produto:

```sh
scripts/verify_product_catalogue.sh "$(xcrun simctl get_app_container booted com.feedmine.development app)"
```

O benchmark pode deixar instalado um app com catálogo de corpus; isso não representa a descoberta no catálogo real. O verificador informa como reinstalar o build de produto.

Execute as provas por `scripts/run-discovery-benchmark.sh --gate B01 --profile A --profile B` (ou os demais gates). O launcher configura o transporte fora do avaliador; preserve driver, oráculo, corpus e hashes congelados. No iPhone, forneça `FEEDMINE_BENCH_DEVICE_UDID` e `FEEDMINE_BENCH_TRANSPORT_HOST` (host:porta do Mac).

## Interpretar o estado do projeto

Confira `git status`, `git log -1` e `git worktree list` antes de trabalhar: este checkout pode não ser a linha de produto mais recente. Cada resultado vale para o commit, build, catálogo e ambiente que sua evidência identifica. Um relatório antigo não certifica o HEAD atual.

Os [registros pós-build 53](docs/reviews/2026-10-18-v2-execucao-pos-build53.md), o [snapshot da candidata](docs/reviews/evidence/2026-10-18-candidate-snapshot/README.md) e o [registro de distribuição de 13/out](docs/reviews/2026-10-13-production-delivery.md) documentam suas respectivas execuções; não são declaração de release aprovada. TestFlight interno serve à avaliação. A aprovação pública exige B01–B06 e PD-10 comprovados na candidata, incluindo B06 em iPhone físico.

Referências de apoio: [primeira experiência F02](docs/product/F02_DISCOVERY_FEED_ONBOARDING_PRD.md), [pesquisa Apple](docs/research/APPLE_IOS_UI_UX_RELIABILITY_2026-10-10.md), [transferência da UI V1](docs/reviews/V1_V2_FRONTEND_TRANSFER_EVIDENCE.md) e [o que não portar da V1](docs/v1-study/V1_GOLD_DO_NOT_PORT_2026-10-10.md).

## Preparação verificável do catálogo para release

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
# Commit the tracked descriptor before release; catalog.sqlite is Git-ignored and is
# instead bound to the commit/build by the archive's byte-level evidence.
scripts/release-testflight.sh --dry-run
```

O `catalog.sqlite` é intencionalmente ignorado pelo Git (atualmente maior que 100 MB),
portanto o SHA Git sozinho **não** certifica seus bytes. A evidência de cada archive vincula
Git SHA + manifesto público + SHA-256 do SQLite efetivamente distribuído.

O preflight exige manifesto público atual acessível, inventário completo e OPMLs íntegros,
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
