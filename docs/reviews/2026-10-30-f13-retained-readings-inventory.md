# F13 — inventário completo de leituras retidas — 2026-10-30

A consulta retainedReadings() enumera cada Edition comprometida, seus critérios congelados, owner lógico opcional, declarações originais e checkpoints owned distintos, ponto realmente ativo e fato de preparação selecionada. Não depende do critério/política global atual, não escolhe a Edition mais recente e não altera autoridade. Metadados não prometem que uma Edition ainda tenha cards locais desenháveis.

A consulta inteira usa um único read snapshot. Respeita session_reader_binding.checkpoint_present: uma posição explicitamente limpa não volta a aparecer como ativa só porque seu checkpoint permanece retido. Uma preparação oculta não é confundida com leitura apresentada, inclusive quando duas Editions pertencem ao mesmo binding. Original e posição nova da mesma Edition permanecem distintos. A ordem é estável por identidade; não há seleção por recência.

Checkpoints owned só podem ser associados a uma Edition do mesmo owner após resolver o card real. Dados contraditórios são recusados com corruption. A decodificação do Record foi extraída para uso compartilhado, mantendo o caminho normal de binding. Nenhuma migração nova é necessária nesta etapa.

## Evidência

RED por ausência de retainedReadings; GREEN focal1/0. Foco final: **44 testes, zero falhas**, incluindo ausência de singleton, irmãos sem owner, adoção, preparação oculta, promoção, clear de presença, movimentação com original retido, política global não resolvida, cancelamento de candidata e recusa de card de outro owner. Revisão independente e followup final sem achados. Suíte completa macOS Debug: **1855 testes, um ignorado, zero falhas**, exit0 (`recovery-readings-inventory-full`), sem interrupção de espaço. O ignorado exige catálogo externo. [Manifesto](evidence/2026-10-27-source-exclusions/recovery-readings-inventory-manifest.json) conserva hash do executável, logs e patch completo de fontes/testes comprimidos sem perdas; JSONs originais intactos.

Nenhuma execução iOS foi feita para esta API ainda sem consumidor nativo/UI; os20 testes nativos do checkpoint anterior permanecem evidência anterior. O código novo não publica/adquire supply nem ativa bindings.

## Pendente

O inventário é a fronteira de leitura, não uma seleção implementada. Ainda faltam selecionar explicitamente Editions irmãs dentro do mesmo binding sem sobrescrever sua leitura ativa durante preparação, revalidar evidência e autoridade no commit, integrar o host sem singleton e renderizar a recuperação com More-menu/empty-reader e mensagem de escolha salva. UI pt/en/XXXL/cauda, política não resolvida e relaunch real continuam pendentes. F13 não está completo.
