# F13 — leitura sem autoridade durante recuperação — 2026-10-30

A recuperação ambígua precisa apresentar a leitura anterior antes de adotar critérios. Construir uma FeedAssociation legada para isso seria incorreto: seu constructor ativa contexto e pode limpar checkpoint incompatível. Foi adicionada uma projeção explícita de PublicationHistory sobre um checkpoint capturado, sem ativação.

O preview conserva a declaração original mesmo se o singleton mudar. Resolve a Edition pelo card real, preserva substituição por vizinho/card desconhecido, aceita o contexto congelado correspondente e recusa janelas de outra Edition. `saveCursor` recusa gravação com erro tipado; `markSeen` valida a Edition e não grava exposição. O initializer normal mantém os caminhos anteriores. Nenhum owner frio/ativo ou publicação é construído por esta API.

## Evidência

- Primeira tentativa do RED foi bloqueada pelo acesso da sandbox ao cache Swift; não é RED funcional.
- RED de compilação confirmado em execução com cache acessível: argumento `previewing` inexistente.
- GREEN focal: 1 teste sem falhas.
- Cobertura ampliada: **21 testes afetados, zero falhas**. Inclui singleton posterior diferente, gravação negada, ausência de apropriação, exposição intacta, Edition declarada divergente, contexto compatível/estrangeiro, archived/unknown e restauração desde o início.
- Revisão independente somente leitura: nenhum achado acionável. Coberturas adicionais sugeridas foram implementadas.

Os arquivos `recovery-preview-*` em [evidências](evidence/2026-10-27-source-exclusions/) preservam comandos/resultados/logs. Suíte completa macOS Debug: **1847 testes, um ignorado, zero falhas**, exit 0, sem interrupção de espaço (`recovery-preview-full`). O ignorado requer o catálogo externo. [Manifesto de hashes](evidence/2026-10-27-source-exclusions/recovery-preview-manifest.json) conserva o hash do executável e dos logs/patch comprimidos sem perdas.

## Limites

**Este checkpoint implementa a fronteira de leitura; não conclui a recuperação ambígua.** O host ainda precisa apresentar essa leitura, pausar publicação, oferecer critérios anteriores/atuais e acesso às leituras retidas, revalidar escolhas e cobrir UI/pt-en/XXXL/cauda. Nenhuma nova execução iOS foi feita para esta API ainda não consumida pelo host. R4 conhecido e testes nativos permanecem evidência do checkpoint anterior, sem ampliar seu escopo.
