# F13 — integração nativa de histórico e continuidade — 2026-10-30

A composição nativa agora consome vínculos de histórico e handles preparados. Alterações de palavras globais notificam a elegibilidade futura sem reconstruir a associação apresentada. O oráculo conhecido R4 (incluir, master off/on e remover) passou com assertions ordinárias após registrar que as oito falhas estritamente esperadas haviam se tornado passes inesperados.

## Implementação

A seleção usa critérios lógicos originais; uma Edition restaurada conserva critérios e revisão congelados. Adoção legada exige evidência compatível e mantém o checkpoint original. Contextos explícitos que colidem com namespaces históricos recebem isolamento. Ambiguidade e palavras legadas sem origem comprovável interrompem a seleção antes de apropriar ou apagar o histórico.

No NF03, a candidata prepara enquanto o leitor anterior permanece autorizado. O corte congela novas entradas de viewport, aguarda o drain existente, salva o último ponto, atualiza somente a projeção oculta e promove imediatamente antes da instalação. Rollback respeita visibilidade/atividade; foreground não reabre ingress durante o congelamento. Cancelamento fecha somente o handle da candidata.

## Evidência verificada

- Pacote macOS Debug completo: **1846 testes, um ignorado, zero falhas**, exit 0 (`r4-prepared-refresh-full`). O ignorado requer catálogo externo. Refresh preparado teve RED de compilação e GREEN focal.
- XCTest hospedado no simulador iOS: **42 testes distintos, zero falhas**, assertions ordinárias. ContentFilter17 (`r4-native-binding-legacy-tests`), lifecycle2 (subset de `r4-native-binding-lifecycle-green`), NF03 13 (`r4-native-binding-nf03`) e contextos10 (`r4-native-binding-contexts`). Os 15 ContentFilter repetidos no lifecycle não são contados duas vezes.
- O R4 compara associação, Edition, prefixo, âncora, posição, checkpoint completo incluindo timestamp, registros congelados, segmentos e salvo.
- Adoção current-forward, colisão independente, callbacks aposentados e recriação da composição passaram. Recriação da composição não prova encerramento/relaunch do processo pelo sistema.
- Revisão independente encontrou races de drain/rollback/foreground; correções e testes determinísticos concluídos, sem achados acionáveis restantes na revisão desta integração.

Logs e patches completos foram comprimidos sem perdas. [Manifesto de hashes](evidence/2026-10-27-source-exclusions/r4-native-binding-archive.json). Os JSONs originais permanecem intactos; seus hashes de build/patch foram conferidos. Dylib de produção nas execuções lifecycle/NF03/legacy/contextos: `2daaa734393cf4d65bf1db72895184deeedde514413dde50082f06c56935518f`. Result bundles locais preservados em `.build/f13-ios-tests`. Falhas intermediárias e REDs também foram preservados.

## Limites e trabalho restante

**F13 e a aceitação completa de R4 continuam abertos.** O fluxo ambíguo/sem origem comprovável protege dados, mas ainda precisa apresentar a leitura anterior e oferecer escolhas explícitas de recuperação. Faltam recovery de política não resolvida, jornadas UI/gestos/pt-en/XXXL/cauda estável e encerramento/relaunch real. B02/B04/B05 abertos, B03 FAIL e B06 NOT_RUN permanecem inalterados. Os testes cold/live anteriores exercitavam owners diretamente. O followup abaixo cobre o callback nativo; as jornadas UI continuam pendentes.

## Followup — callback nativo de política

Os testes cold/live agora invocam `root.reapplyReaderFilters()`, como o fechamento da sheet. O caso frio desativa globals usando o mesmo writer e prova recuperação sem substituir o contexto; a variante com palavra contextual coincidente continua bloqueada. O caso ativo prova bloqueio/reversão de supply futuro, mesma associação/Edition e prefixo congelado intacto. Não houve mudança de produção.

Build e XCTest reais: `r4-native-root-policy-build` e `r4-native-root-policy-tests`, **17 testes, zero falhas**, exit 0, sem interrupção por espaço. Dylib de produção idêntica ao checkpoint anterior; test bundle recompilado. [Manifesto](evidence/2026-10-27-source-exclusions/r4-native-root-policy-archive.json). Não amplia a contagem distinta42 nem substitui aceitação UI/relaunch.
