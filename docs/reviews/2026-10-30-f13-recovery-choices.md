# F13 — escolhas explícitas de recuperação — 2026-10-30

As APIs nativas distinguem continuar com critérios anteriores completos e abrir critérios atuais. Não há subtração de palavras históricas. A escolha anterior usa adoção exata com evidência original; a atual reutiliza um binding lógico existente ou cria namespace independente mesmo quando o namespace legado ainda não tem proprietário. Históricos antigos não são apagados ou reescritos.

## Escolha salva e ativação são resultados distintos

A revisão encontrou dois riscos na primeira implementação: adoção permanente antes de falha sem intenção correspondente nas preferências, e checkpoint legado alterado durante o await de lançamento. A política final torna o commit explícito: critérios e binding/adoção são gravados juntos, revalidando contexto esperado e checkpoint mostrado antes de qualquer escrita. Se a transação falhar, nada é salvo.

Depois desse commit a escolha está salva. Root.currentContextKey e recovery.selectedContextKey refletem a intenção; uma falha de preparação/ativação mantém essa intenção e o preview, retorna selectionStoredNotActivated e permite retry. Uma nova composição honra os critérios já salvos. Isso segue a distinção já existente no produto entre intenção armazenada e ativação pendente; não afirma que o lançamento fracassado foi revertido.

A candidata usa handle preparado. A promoção compara novamente o checkpoint legado exato na mesma transação, além dos fences de binding/token existentes. Não há suspensão entre promoção e instalação. O preview é aposentado sincronamente, e todos os retornos de awaits da rolagem verificam sua aposentadoria antes de instalar snapshots.

## Validação e escopo

REDs de compilação e GREENs focais da persistência preservados. O teste transacional força falha no UPDATE de preferências: binding e adoção são revertidos juntos. Também verifica a recusa atômica da promoção após mudar o singleton. Testes nativos cobrem as duas escolhas, falha após intenção salva, retry, recriação da composição, mudança do singleton durante preparação e callbacks aposentados. Revisão independente acompanhou a correção dos dois P2, sem novos achados. Resultados finais: **1849 testes completos macOS Debug, um ignorado, zero falhas**, exit0 (`recovery-choice-full`); ignorado exige catálogo externo. **20 testes nativos iOS, zero falhas**, exit0 (`recovery-native-choice-atomic-tests`), build exit0; nenhum stop por espaço nas execuções finais. Dylib `3b2e7a4f80163bb3a75c57e2e6c99438b03c1ad4cabf682bab0e6638a2bb3487`. [Manifesto](evidence/2026-10-27-source-exclusions/recovery-choice-manifest.json) inclui hash do executável do pacote e logs/patches comprimidos sem perdas. JSONs e result bundles locais preservados. O patch de App/Sources atual corresponde ao hash capturado no build nativo. Os demais25 cenários nativos do checkpoint de integração não foram repetidos nesta etapa.

**A interface ainda não oferece estas APIs.** Faltam renderizar a leitura retida, oferecer ambas as ações no More-menu e na ausência de cards, comunicar escolha salva/ativação pendente, permitir seleção de leituras retidas (inclusive múltiplas Editions do mesmo contexto e ausência de singleton), e provar pt/en/XXXL/cauda/relaunch de processo real. Os testes de recriação da composição não equivalem a matar/reabrir o processo. F13 e aceitação completa continuam abertos.

## Dependência obrigatória antes de expor a UI

A auditoria identificou uma lacuna de retenção futura: se raw atual == chave legada, a nova leitura tem namespace próprio, mas seu próximo checkpoint pode substituir a única linha antiga em context_checkpoints. Os testes desta etapa provam o ponto de corte e a preservação imediata; não provam a retenção dessa posição após checkpoints futuros no mesmo contexto. É necessário um registro durável independente das declarações originais e sua inclusão no inventário/adoção antes de ligar as ações à interface (Task2g). Não há novo caminho UI alcançável nesta etapa.

Atualização posterior: o teste de gravação owned no mesmo contexto refutou a suspeita literal acima; persistOwned já protege essa linha legada. O RED real envolve singleton A/context B distintos antes da ativação. [Diagnóstico corrigido e correção](2026-10-30-f13-retained-legacy-statements.md). Mantém-se o registro histórico da hipótese inicial.
