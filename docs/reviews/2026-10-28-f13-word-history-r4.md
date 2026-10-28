# F13 — palavras globais: falha de continuidade R4 — 2026-10-28

**R4 FAIL na integração do host. O comportamento de produção ainda não foi corrigido.**
Base: `38396c08`. Neste checkpoint mudam teste, evidências e apontamentos; Sources e executável/dylib
do app permanecem iguais ao build aprovado da recuperação de cauda.

## Reprodução e resultado

A fixture publica 48 CardRecords em segmentos; 17 IDs estão na janela apresentada. Salva-se uma carta
e checkpointa-se a posição. Pelo backend real: incluir `published fixture`, desligar o master, religá-lo,
remover a regra. Após cada intenção executa-se `reapplyReaderFilters()`, como o host faz no fechamento
da sheet (`FeedMineApp.swift`, onDismiss). A regra coincide com título já publicado.

| Intenção | Leitura/posição ativa preservada | Regra guardada | 48 registros, segmentos, salvo e checkpoint histórico |
| --- | --- | --- | --- |
| Incluir | **Não** | Sim | Preservados |
| Master off | Sim, baseline restaurada | Sim | Preservados |
| Master on | **Não** | Sim | Preservados |
| Remover | Sim, baseline restaurada | Não | Preservados |

A intenção lógica `root.currentContextKey` é igual nos quatro passos. Incluir/reativar produz outra
identidade aplicada, sem apresentação/Edition/IDs/âncora ativos; o singleton `checkpoint()` fica nil.
`checkpoint(for: original.contextKey)` conserva a posição histórica. Isso é interrupção apresentada,
não apagamento dos registros ou do checkpoint antigo. Recuperação eventual não elimina a interrupção.

A primeira prova só persistia a regra e passou; era incompleta porque não aplicava o fechamento do host.
A prova completa deu RED oficial (1 caso, cinco asserções, exit 65). Refinou-se o oráculo: identidade do
objeto association e timestamp são diagnóstico, não exigências de produto. A matriz normal deu RED
oficial com **oito asserções de continuidade**: Edition, prefixo admitido, âncora e posição ativa, em add/on.
As demais verificações passaram. `r4-red-reversal-facts.json` guarda os quatro estados.

## Causa e proteção da regressão

`AppComposition.applied(ContextKey)` dobra palavras globais nos critérios da identidade; `reapplyReaderFilters`
chama `replaceSession()` quando essa união muda. `SessionStore.activateContext` conserva o checkpoint
anterior por contexto e ativa uma identidade inédita sem checkpoint. O host desenha `composition.association`.
Logo uma regra global vira troca efetiva de leitura sem intenção explícita de substituir contexto.

O teste final mantém oito `XCTExpectFailure` individuais, estritos e com matcher de tipo/marcador exclusivo.
Segmentos antigos completos (prefixo, permitindo append futuro), todos os CardRecords, salvo, checkpoint
histórico, preferências e continuidade off/remove ficam em asserções normais. Um sintoma resolvido faz a
expectativa estrita falhar até sua remoção. **Não é correção nem PASS UX13.** O matcher identifica o campo
falho; outra manifestação dentro desse contrato já falho pode ser aceita. Por isso os fatos JSON são
preservados e mudanças de forma/gravidade exigem nova análise.

Revisão independente confirmou o alcance do oráculo e a delimitação das expectativas. O relatório oficial
da primeira suíte de acompanhamento registra **9 Passed, 0 Failed, 1 ExpectedFailure**; o caso esperado
contém oito issues. Não descrever como “10 testes aprovados”. A suíte final com prefixos históricos confirmou a mesma contagem oficial em
`r4-history-prefix-app-suite-tests-summary.json`: 9 Passed, 0 Failed, 1 ExpectedFailure; oito issues
identificadas; exit 0, sem interrupção. O status de produto permanece **FAIL**, também registrado em
`r4-product-acceptance-status.json`. Patch compilado e diff atual conferidos por SHA-256
`b9e27a65f0bb51f4bae7f12f3a537e8ba2457475c0ecea85e671bc1d8a02cd2e`.

## O próximo fix deve resolver

- Separação entre critérios próprios do contexto e política global de publicação futura; o master mascara
  somente a parte global, inclusive quando o mesmo termo também pertence ao contexto.
- Snapshot/guard de política nas oportunidades de first/append/cold/reoffer e reconsideração local pelo owner
  existente. Simplesmente deixar de reaplicar a regra preservaria a leitura, mas ignoraria o efeito futuro.
- Compatibilidade de históricos cujos ContextKeys já contêm a união. Não subtrair palavras de Editions antigas
  supondo origem global; preservar critérios contextuais e metadados congelados. Definir desenho/plano antes
  de alterar identidade/migração, incluindo casos de origem ambígua.
- Publicações X/Y, gestos UI, relaunch, A→B→A e vazio recuperável correto. Esta prova é integração do host,
  não navegação pelo histórico inteiro nem certificação black-box UX13-A/B/D. Templates e contextos próprios
  continuam exigindo provas de continuidade, além dos testes existentes de matching/gate.

F13 segue aberta; B02/B04/B05 e demais jornadas pendentes. B03/B06 e régua de benchmark não mudaram.

## Capacidade, identidade e reprodução

Um build amplo foi interrompido pela reserva de 700 MiB. Um scheme temporário com somente o target unitário
permitiu compilar a prova; seu XML e SHA estão em `r4-unit-probe-scheme*`. O scheme principal não mudou.
O temporário é retirado após a verificação, preservando os produtos e xctestrun para replay.

A primeira coleta de falha completou o teste, mas o sysdiagnose posterior cruzou a reserva e não finalizou
Info.plist. Seus dados foram arquivados em tar.gz com verificação de todos os SHA-256, antes de liberar a
pasta (`r4-interrupted-result-archive.json`). A execução formal usa `-collect-test-diagnostics never`;
asserções, status e fatos permanecem completos. Não muda oráculo de teste ou benchmark.

Cópias temporárias de attachments foram liberadas somente após conferir que o xcresult completo original
continuava presente. SDK ModuleCache regenerável foi limpo após builds terminais. Nenhum banco histórico,
produto ou resultado completo foi removido. A guarda padrão de 3 GiB permanece intacta.

Os manifestos dos builds guardam base/patch e os testes guardam hashes dos binários/xctestrun. Para repetir
o RED sem expectativas, usar o patch `r4-global-word-reversal-matrix-build.patch.gz` sobre a base em checkout
isolado e o scheme arquivado. Não aplicar esse patch sobre trabalho atual sem isolamento. A última suíte
completa do pacote continua sendo 1777/1skip/0 do checkpoint anterior; não se soma esse número aos testes do app.
