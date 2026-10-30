# F13 — reader retido no estado de recuperação — 2026-10-30

O host agora captura um ReaderHistoryRecovery quando a seleção inicial é ambígua ou contém palavras legadas sem origem comprovável e há checkpoint ativo. Essa captura ocorre antes de qualquer apropriação ou ativação. Durante transições com associação já apresentada, mantém-se a associação anterior.

O reader retido usa PublicationHistory de preview, o mesmo decoder local e os mesmos bounds de apresentação. Tem apenas FeedSession e FeedScreenStore: não constrói driver, aquisição, coordenação de publicação ou writer de checkpoint. O ingresso de viewport reutiliza o resumo limitado do reader normal e um único drain; evidência renderizada chega ao FeedSession para rejeitar eventos antigos. Pode admitir mais histórico local sem publicar supply futuro.

## Escopo ainda incompleto

**O estado está preparado e testável, mas FeedMineApp ainda não o renderiza.** A mensagem de startup anterior é mantida até integrar a superfície com escolhas funcionais. Faltam ações explícitas de critérios anteriores/atuais, inventário navegável das leituras retidas (incluindo ausência de singleton), transação/revalidação das escolhas, aposentadoria do reader de preview ao instalar a associação escolhida, More-menu/empty-reader, pt/en e validação UI/cauda. Não equivale a completar o fluxo ambíguo.

## Verificação

RED de compilação por ausência de `historyRecovery`; a primeira fixture também precisou corrigir import de Runtime e acesso ao Mutex de requests. Um build intermediário corrigiu anotação ObservationIgnored no lazy store. Todos os logs/patches preservados.

A primeira execução iOS foi interrompida preventivamente por espaço (não conta como PASS nem falha funcional). Foi removido somente o cache de módulos macOS regenerável em `.build/index-build/arm64-apple-macosx/debug/ModuleCache` (~160 MiB), preservando executáveis, dados, simulador, logs e result bundles. A repetição usa caminho próprio e o build atual com validação de viewport.

Revisão independente e followup do ingresso concluídos sem achados pendentes nesta etapa. O teste nativo mantém Edition, âncora, checkpoint e ausência de owner; verifica lifecycle/filtros sem HTTP, rolagem local e recusa de ordinal antigo. Repetição terminal (`recovery-host-state-ingress-tests`): **17 testes, zero falhas**, exit0, sem interrupção por espaço; build exit0. O patch atual de App/Sources corresponde ao hash do build. [Manifesto de logs/patches](evidence/2026-10-27-source-exclusions/recovery-host-state-manifest.json), compressão sem perdas; JSONs originais intactos. Dylib: `0587bdd047e8ffd38e565a61034f7e03e339b5a1c3c43faa495cdf498bc0e0f4`. Result bundles locais preservados. A suíte completa do pacote1847/um ignorado/0 pertence ao checkpoint62a2fe25; os Sources do pacote não mudam nesta etapa nativa.
