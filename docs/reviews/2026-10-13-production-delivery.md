# Entrega de produção e TestFlight — 2026-10-13

## Canal instalável confirmado

Consulta autenticada à API App Store Connect, em 2026-10-13 (America/Vancouver):

- Aplicativo ASC 6793279758; versão **1.0 (31)**, bundle `com.feedmine.app`.
- Build UUID `117e8d27-6e68-4d39-86b7-8f23af029b19`: `VALID`, não expirada; `internalBuildState=IN_BETA_TESTING`.
- Upload anterior: 2026-10-12 17:39:28 PDT. Esta sessão **não realizou novo upload**.
- Grupo interno **WawaTesters**, com acesso a todas as builds; a consulta aos builds do grupo inclui explicitamente a build 31. Tester Wagner consta `INSTALLED` (estado do cadastro, não prova de qual versão está no seu iPhone).
- Pareamento local: tag anotada `ios/1.0-build.31-5dcc4cab` aponta para `5dcc4cab0de8c88a0afe23a23009b368a3de5615`. A API Apple não expõe o SHA binário; a tag é o registro do fluxo anterior.
- Mudança visível da build: correção F06 de gesto/rolagem; preservação da janela desenhada enquanto há interação nativa, seguida da reconciliação em repouso.
- Fluxos prioritários: flings rápidos, abertura de card ainda desenhado, troca A→B→A, reopen, salvos e retorno offline.

Evidência sanitizada: [testflight-status.jsonl](evidence/2026-10-13-production/testflight-status.jsonl). Nenhum token ou chave privada foi salvo no repositório.

## Validação atual

`swift test`: 1.246 testes, zero falhas, um skipped; exit 0. `swift build`: exit 0. Logs nesta pasta de evidências.

`python3 scripts/bootstrap_catalog.py`: revisão pública 5; 118/118 OPMLs conferidos por tamanho e SHA-256. Catálogo empacotado confere com o descritor: 117.993.472 bytes, SHA-256 `72f066227958b482f365c88dd58320e75bc9ade9268b4e2ddaac9173908ecf71`. Nenhum recurso de produto foi substituído nesta sessão.

A tentativa redundante de archive `--dry-run` foi interrompida após a consulta Apple confirmar que a build 31 já estava disponível. Ela não comprova novo archive ou upload. Não tentar reenviar o número 31.

## Correção da execução de benchmark

A primeira corrida foi recusada corretamente: `bench/run.sh` mudou em `b570aac6` sem alteração correspondente de `EVALUATOR.sha256`. O único arquivo divergente era o runner; driver, oráculo e demais insumos conferiam.

Restaurado o runner byte a byte de `ba0866da`, cujo SHA-256 é o congelado `966276836b6edf55f555ae25c0c15d5c23185c4894a43e92be24ea10ca0c0b3f`. Não se recalculou checksum para aceitar o arquivo novo. A configuração de transporte foi deslocada para `scripts/run-discovery-benchmark.sh` e `scripts/benchmark_launch.py`, fora do avaliador. A revisão independente encontrou que exportar ao test runner não bastava: o adapter agora insere apenas a origem no `UITargetAppEnvironmentVariables` do `.xctestrun` gerado, conforme o manual Apple local, e usa esse arquivo para `test-without-building`. Preserva destino, seleção, IDs e durações. Três regressões do adapter passaram após duas assertions vermelhas; ainda é necessária prova de transporte no app real. Todos os seis hashes passam; `bash -n` passa.

Primeira tentativa integral (anterior ao adapter de ambiente do app): `bench/run/20261013T234828Z`, B01, B02, B03 (full trace), B04 e B05, perfis A/B. Interrompida durante a preparação do build para reiniciar com o adapter corrigido; não instalou o app, não produziu veredito e não é PASS. Os artefatos brutos permanecem no Mac, ignorados pelo Git.

## Matriz viva desta entrega

| Gate | Estado atual nesta sessão | Evidência / pendência |
|---|---|---|
| B01 | NOT_RUN nesta sessão (nova corrida pendente) | Descoberta e mudança de perfil |
| B02 | NOT_RUN nesta sessão (nova corrida pendente) | Relevância, diversidade, mídia |
| B03 | NOT_RUN nesta sessão (nova corrida pendente) | Trace integral de 30 minutos |
| B04 | NOT_RUN nesta sessão (nova corrida pendente) | Estabilidade física; anterior 081619Z foi NOT_RUN |
| B05 | NOT_RUN nesta sessão (nova corrida pendente) | Preservar o PASS histórico relatado sem atribuí-lo ao HEAD atual |
| B06 | NOT_RUN | iPhone 14 Plus disponível/pareado; ainda faltam corrida integral e medidas controladas de memória, energia, térmica e hitches |
| TestFlight interno | Disponível | Apple VALID / IN_BETA_TESTING, grupo com build31 |

**Produção ainda não certificada.** Permanecem os gates integrais e a triagem K-14/K-15 (proteção da cauda admitida; enriquecimento de corpo RSS/Atom com compatibilidade de identidade material). Disponibilidade no TestFlight não fecha essas pendências.

Revisão independente do adapter: sem novo defeito estático; falta confirmar requisições reais e colocação do xcresult. `swift package clean` recuperou espaço via limpeza nativa sem excluir evidências. Cache GRDB local verificado por `git fsck`, com a revisão fixada `b83108d10f42680d78f23fe4d4d80fc88dab3212`; usado para evitar novo download integral.
