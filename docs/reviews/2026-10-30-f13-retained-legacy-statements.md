# F13 — retenção de declarações legadas distintas — 2026-10-30

## Diagnóstico corrigido pela execução

A suspeita do checkpoint anterior — checkpoints de uma nova leitura com ownership sobrescreverem a linha legada do mesmo contexto — foi refutada. O teste real publica uma nova Edition com binding e salva nova posição: SessionStore.persistContext já encaminha essas gravações para persistOwned e conserva a linha legada. A tentativa chamada `recovery-retained-point-red` passou antes de qualquer correção; seu nome não constitui evidência RED.

O problema reproduzido é outro: o singleton pode conter uma declaração A e o contexto uma declaração B distinta sob a mesma chave congelada. Ao ativar uma leitura, o refiling de A substituía a linha B. O RED funcional `recovery-retained-distinct-red` perdeu exatamente a evidência de B no inventário, sem apagar sua Edition.

## Correção

Migração aditiva `reader-history-legacy-checkpoints-v1` adiciona reader_history_legacy_checkpoints. Guarda a declaração original inteira e, separadamente, a Edition observada pelo card. Não há FK para card vivo, para conservar anchors arquivados/desconhecidos; ambas as referências de Edition permanecem com FK. Nenhuma Edition, segmento, card ou bookmark é reescrito.

A resolução com adoção/escolha independente conserva todas as declarações conhecidas sem proprietário na mesma transação. Ativação de binding, promoção preparada e ativação de contexto legado também preservam antes de refilar o singleton, cobrindo resolução normal e bindings já existentes. Fences de autoridade/checkpoint precedem a preservação na promoção. Retentativas não duplicam a mesma declaração/Edition observada; falha na gravação das preferências reverte também a retenção.

O inventário inclui os originais sem apropriar histories nem escolher a Edition mais recente. A adoção revalida a declaração retida. Se um card observado depois fica desconhecido, a Edition previamente comprovada prevalece sobre sua coluna histórica incorreta; evidência contraditória é recusada.

## Verificação

Foco final: **41 testes, zero falhas**, cobrindo escolha explícita, resolução normal+ativação, resolução normal+promoção, ativação legada, adoção de B depois de substituir sua linha de contexto, dedup, rollback, migração literal e card misfiled que fica desconhecido. Revisão independente encontrou a fronteira de resolução normal inicialmente faltante; corrigida e followup sem novos achados. A cobertura prévia archived/unknown também continua no foco. Suíte completa macOS Debug: **1852 testes, um ignorado, zero falhas**, exit0 (`recovery-retained-full`); o ignorado exige catálogo externo. Native ContentFilterTests: **20 testes, zero falhas**, exit0 (`recovery-retained-native-retry-tests`), build exit0. Primeira execução nativa foi encerrada pela reserva de espaço e não conta como resultado funcional; repetição terminal usou os mesmos binários após remover somente o cache de módulos iOS regenerável. Result bundles preservados. Não são jornadas UI nem benchmark.

[Manifesto](evidence/2026-10-27-source-exclusions/recovery-retained-manifest.json) conserva hash do executável e logs/patches comprimidos sem perdas; JSONs originais intactos. O build final de proveniência inclui o arquivo novo e o patch de App/Sources atual coincide com seu hash. Dylib iOS: `39f2ef5402c975b8e4004caa1441ea5d612a87052616306fedebbc136de976a4`. Os outros25 testes nativos do checkpoint de integração não foram repetidos nesta etapa.

## Ainda pendente

A UI continua desligada. Faltam renderizar o reader retido e as ações funcionais no More-menu/empty-reader, seleção de leituras retidas — inclusive Editions irmãs do mesmo contexto e ausência de singleton — mensagem de intenção salva/ativação pendente, política não resolvida, pt/en/XXXL/cauda e relaunch real de processo. Esta retenção não certifica o fluxo inteiro de recuperação.
