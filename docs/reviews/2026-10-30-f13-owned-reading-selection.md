# F13 — preparação explícita de leitura já owned — 2026-10-30

prepareRetainedReading recebe o snapshot de uma leitura retida, seu checkpoint owned exato e a ativação do leitor atual. Revalida token atual, metadata de owner/Edition, membership e checkpoint antes de revogar qualquer preparação. Uma leitura que participa de preparação selecionada não pode ser apropriada por esta ação.

A preparação escolhe exatamente a Edition pedida, em vez da escolha automática de candidata/base. Se o card apontar para outra Edition, recusa a seleção explícita; não corrige silenciosamente o pedido. O active_edition_id, checkpoint e token atuais permanecem intactos. A promoção continua usando os fences existentes e conserva a última posição de A antes de instalar B. Retornar A restaura esse ponto final, não o ponto anterior à preparação de B.

O helper de preparação foi extraído para reutilizar a implementação normal. Não há migração nova, remoção de histórico ou empréstimo de namespace/ownership.

## Verificação

RED de compilação por ausência da API, GREEN focal1/0. Foco final: **46 testes, zero falhas**. A→B→A no mesmo binding prova leitura atual utilizável durante preparação, checkpoint final de A e invalidação de tokens aposentados. Negativos recusam leitura unowned/oculta, checkpoint alterado, token rotacionado e snapshot de owner obsoleto após rollover real, sem revogar uma preparação preexistente.

Uma fixture negativa inicialmente tentou criar novo checkpoint inicial sem executar o clear explícito exigido no rollover e lançou checkpointAlreadyExists. Corrigida para o caminho público já usado pelos testes de produção (clear com Edition esperada, depois publicação), sem mudar o produto. Falha intermediária preservada. Revisão independente e followup final sem achados. Suíte completa macOS Debug: **1857 testes, um ignorado, zero falhas**, exit0 (`recovery-owned-selection-full`); ignorado exige catálogo externo. Build iOS exit0 e regressão nativa **33 testes, zero falhas**, exit0 (`recovery-owned-selection-native-tests`): ContentFilter20 + FilterConfirmationBoundary13/NF03. Essa execução valida o caminho compartilhado existente; o entry point novo continua sem consumidor nativo. Não é prova de seleção pela UI, relaunch de processo ou benchmark.

[Manifesto](evidence/2026-10-27-source-exclusions/recovery-owned-selection-manifest.json) conserva hashes do executável e logs/patches comprimidos sem perdas, JSONs originais intactos. Patch de App/Sources corresponde ao hash capturado no build. Dylib `926ab54886633344d90bb0a0782512d6015b5b780cd9c1de99f3cbad38da9e59`. Result bundles preservados; sem interrupção por espaço nas execuções finais. Somente caches de módulos regeneráveis do workspace foram removidos para manter a reserva de disco.

## Limites

Este é um primitivo de preparação owned com leitor predecessor bound, ainda sem consumidor no host. Não aceita leitura sem proprietário, ponto somente original sem checkpoint owned correspondente, nem ausência de binding atual. Adoção de Editions irmãs unowned em um logical binding existente, compatibilidade/isolamento de namespace legado, estado sem singleton, persistência/revalidação da escolha no host, UI/More-menu/empty-reader e jornadas de aceitação continuam obrigatórios. Nenhuma opção foi substituída por um contexto novo para fazer o caso passar. F13 permanece aberto.
