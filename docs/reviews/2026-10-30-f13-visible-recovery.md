# F13 — recuperação visível e continuidade da posição

A recuperação legada com checkpoint ativo agora apresenta a leitura retida e oferece critérios anteriores/atuais no menu e no estado vazio. Publicação fica pausada até escolha explícita; busca, filtros, salvos e ações das cartas ficam desabilitados. Cancelar a folha preserva a leitura. Falhas posteriores à gravação da escolha mantêm o preview e informam que a intenção já foi salva.

A posição rolada localmente é transportada pela escolha anterior com validação transacional, mantendo o checkpoint original como fence da promoção. Os três caminhos de ativação preservam checkpoints owned existentes; uma Edition declarada incorreta no singleton legado não concede autoridade para sobrescrever outro owner. Regressões reais reproduziram overwrite nos caminhos imediato/legado e corrupção por declaração inconsistente antes da correção compartilhada.

## Validação real da interface

Duas jornadas XCUI passaram (`recovery-activation-card-geometry-journeys.json`, exit0, sem interrupção):

- Português: leitura anterior, rolagem até cauda, abrir/cancelar recuperação, escolher critérios anteriores, mesmos IDs publicados e posição relativa à viewport dentro de dois pontos, encerrar/reabrir o processo e conferir novamente IDs/posição.
- Inglês accessibilityXXXL: abrir/cancelar recuperação, alcançar a escolha atual na folha, ativar, encerrar/reabrir o processo e conferir os mesmos IDs da leitura escolhida.

O RED UI revelou identificador no container sobrescrevendo os controles descendentes; marcador movido ao texto de status. Outro RED mediu crescimento de 26pt por carta porque o preview omitia o controle inline de salvar. Preview e leitura ativa agora usam a mesma estrutura de ações, desabilitada enquanto a recuperação está pendente. O oráculo de posição permaneceu estrito. Um erro separado do teste XXXL tentava medir a cauda fora da área realizada; a medição agora pertence somente à jornada que a rola para a tela.

A revisão independente encontrou a possibilidade de o fallback misfiled sobrescrever a Edition declarada owned; o guard e a regressão foram ampliados, e o followup não encontrou novos defeitos. A revisão de geometria confirmou a mesma estrutura de ações com interação desabilitada.

## Suíte Swift

**1860 testes completos, um ignorado, zero falhas**, exit0 (`recovery-activation-delivery-sequential-full.json`). O ignorado exige catálogo externo. O comando anterior `recovery-activation-delivery-full` recompilou a última alteração compartilhada de UI, mas sua execução de testes foi interrompida pela reserva de espaço enquanto rodava em paralelo com iOS. A repetição final isolada usou esses mesmos binários com `--skip-build`. Foco de persistência:49/0.

## Regressão nativa

ContentFilter20 + FilterConfirmationBoundary13: **33 testes, zero falhas**, build e test exit0 (`recovery-activation-native-build.json`, `recovery-activation-native-sequential-tests.json`). Incluem critérios globais/R4, escolhas de recuperação, falha após intenção salva/retry e handoff NF03. A tentativa simultânea com a suíte Swift foi interrompida pela reserva de disco; a repetição sequencial usou os mesmos hashes de binários e concluiu.

## Limites

Esta entrega cobre recuperação com checkpoint legado ativo e as duas escolhas já implementadas. Não oferece ainda UI de seleção de todas as leituras retidas, nem resolve os casos sem singleton ou de política global não resolvida. As jornadas não provam causalidade de supply, benchmark ou aceitação completa F13. B02/B04/B05 abertos; B03 FAIL e B06 NOT_RUN continuam pendentes.

Logs/patches RED/GREEN e relatórios de build/teste ficam em `evidence/2026-10-27-source-exclusions/recovery-activation-*`; arquivos comprimidos são reversíveis e acompanhados de hashes. Schemes de probe são temporários, com cópias arquivadas, e não integram o projeto entregue.
