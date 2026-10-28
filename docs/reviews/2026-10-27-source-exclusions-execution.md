# F13 fonte — execução do plano de 27/out

Plano: `docs/superpowers/plans/2026-10-27-source-exclusions.md`.
Spec: `docs/superpowers/specs/2026-10-27-source-exclusions-design.md`.
Base `e5f75031`; execução nativa na branch de trabalho existente `product/nf04-tail-truth`.
Objetivo F13 completo permanece aberto; cada tarefa abaixo é um incremento, não uma certificação UX13.

## Task 1: regra e snapshot persistidos

- `ReaderSourceExclusion` guarda SourceID + nome, sem usar nome como matching.
- `ReaderSettings.contentSourceExclusions` normaliza tanto init/decode quanto mutação posterior.
  Uma duplicata mantém o último nome fornecido; ordem canônica por UUID.
- Snapshot só inclui IDs efetivos; nomes e regras mascaradas não geram diferença de política.
- JSON antigo sem o campo usa []; tipo inválido lança em vez de desativar regra silenciosamente.
- Settings reabertos conservam regras e switch, sem mudar seleção, versão da seleção ou ContextKey.
- Nenhuma migração histórica ou ContextKey alterado.

RED: novas APIs ausentes na base (erros de compilação). GREEN:
`swift test --scratch-path .build/index-build --disable-index-store --jobs 2 --filter
'ReaderSourceExclusion|ReaderPreferencesStore|ReaderSettings'` — **25 testes, 0 falhas**, 0,369 s.
Logs completos comprimidos em `evidence/2026-10-27-source-exclusions/t1-{red,green}.log.gz`.

Rulings: reusar a branch existente em vez de duplicar checkout/caches com 722 MiB livres;
o arquivo untracked `capacity-ready.json` foi preservado. Duplicatas usam último nome fornecido;
se essa escolha mudar, afeta a apresentação da regra, nunca identidade/elegibilidade.

Esta tarefa ainda não altera seleção/publicação do app: provider, commit guard, fiação e UI estão
nas tarefas seguintes. Nenhum gate, build iOS, teste de app ou distribuição foi executado.

## Task 2: política de memberships e aliases

- Provider aceita exclusões explícitas e conserva as assinaturas públicas anteriores para chamadores sem regra.
- Na superfície principal, origem A+B com A excluída conserva apenas B; origem só A deixa a oferta.
- No contexto A excluído, membership B não permite publicar algo fora do contexto. Os dois caminhos
  de consulta (janela estrutural e source-scoped) são cobertos.
- Conteúdo canônico, metadados da candidata e cursor/contagem de exame são preservados; remover regra
  devolve a projeção original. Alias expansion usa exclusivamente `SourceIdentityIndex`; ID sem linha
  de catálogo continua excluído por si mesmo. Namespaces reader/catalog não se confundem.
- Prova de alias desta tarefa é unitária sobre projeção de linha já verificada; a verificação real
  e a reconciliação continuam cobertas pelos testes existentes `SourceIdentityIndexTests` executados juntos.

RED: APIs novas ausentes. Primeira tentativa green parou no link: objetos incrementais ainda
referiam a assinatura pública anterior substituída. Ruling: manter assinaturas anteriores como
wrappers sem regra, expondo novas sobrecargas explícitas. Custo se essa opção mudar: alguns wrappers
públicos a remover após rebuild de todos os chamadores; nenhuma política diferente.

GREEN: `swift test --scratch-path .build/index-build --disable-index-store --jobs 2 --filter
'SourceExclusionSupply|ReaderSourceExclusionPolicy|CandidateProvider|ReaderFilterEligibility|SourceIdentityIndex'`
— **41 testes, 0 falhas**, 0,801 s. Logs red/link failure/green preservados em
`evidence/2026-10-27-source-exclusions/t2-*.log.gz`.

Escopo sem regra mantém o comportamento anterior; o recorte contextual para uma candidata excluída
é feito apenas na nova sobrecarga efetiva. Nenhuma regra chega ao app ainda: snapshots/commit guard,
fiação, controles e jornadas permanecem nas tarefas 3–6. Não há PASS de UX13 nem de gate.

## Task 3: política comparada no commit

- Novas sobrecargas do store verificam o snapshot dentro da transação de createEdition,
  createInitialEdition e dos dois caminhos de append, antes de qualquer insert/checkpoint.
- Requests do coordenador transportam a expectativa; InitialCreateRequest usa a expectativa da
  publicação que já contém. Assinaturas anteriores continuam sem guard para compatibilidade.
- Divergência efetiva lança `staleSourceExclusions`, não erro de rede. Renomear não invalida;
  desligar master com regras ativas invalida. Estado sem preferências é unrestricted.
- Leitura estrita `ReaderPreferencesStore.sourceExclusionSnapshot()` é a mesma projeção usada pelo
  writer, em seu próprio handle de transação. Dados corrompidos lançam; o guard nunca faz leitura
  aninhada nem usa o fallback tolerante de `load()`.

Ruling: acrescentar o reader estrito em ReaderPreferencesStore, além dos arquivos iniciais de T3 —
o leitor legado de settings tolera decode inválido com `.standard`, que seria fail-open para regras.
Custo se a interface mudar: ajustar o reader público e os dois chamadores (snapshot/writer); não há
nova tabela ou estado duplicado. O comportamento tolerante dos leitores legados não foi alterado.
A fiação de T4 deve obrigatoriamente capturar por esse reader estrito.

RED: writer/snapshot APIs e campos do coordenador ausentes; guard implementado em etapas.
GREEN do store: **4 testes, 0 falhas**; GREEN combinado
`'PublicationSourceExclusion|PublicationCoordinator|SessionStore|EditedArticleRecurrence'`:
**27 testes, 0 falhas**, 0,911 s. Inclui os quatro caminhos do coordenador, ausência de primeira
Edition/checkpoint parcial, preservação das linhas antigas e corrupção sem write.
Logs em `evidence/2026-10-27-source-exclusions/t3-*.log.gz`.

Tarefas 4–6 ainda são necessárias: sem elas o app não captura nem envia snapshots e não há controle
novo de fontes na UI. Este checkpoint não é aceitação de produto, UI ou benchmark.

Verificação integral após T1–T3: `swift test --scratch-path .build/index-build --disable-index-store
--jobs 2` — **1758 testes, 1 pulado, 0 falhas**, 105,896 s. Log completo comprimido em
`evidence/2026-10-27-source-exclusions/t1-t3-package.log.gz`. Os 6 hashes da régua congelada
continuam OK; `git diff --check` limpo. Disco ao encerrar: **641 MiB**. Nenhum cache foi apagado.
A revisão independente do conjunto completo permanece na tarefa final do plano; não foi simulada
uma aprovação de feature completa para este checkpoint parcial.

## Task 4: pipeline integrado; validação iOS pendente

Parte do pacote implementada e verificada:

- `ProductionSourceExclusions` leva um valor capturado antes da preparação para a seleção e o commit.
  Os IDs originais sempre pertencem ao conjunto resolvido; não há registro de política paralelo.
- Cold bootstrap, driver, slices inicial/local e reoffers usam o mesmo snapshot por oportunidade.
  Uma regra fonte pode mascarar um reoffer sem apagá-lo definitivamente da fila; ao remover a regra,
  ele volta a competir pela mesma seleção.
- A mudança de política reinicia a caminhada local sob a mesma scope e preserva high-water, Edition,
  posição e cartas. Uma geração específica impede aceitar conclusão velha mesmo com relógios iguais;
  o ID de correlação de trace continua sem decidir identidade.
- O driver detecta política nova antes de executar um cursor antigo e usa a oportunidade tardia
  existente. Rejeição stale não é falha de rede. O cold reconsidera dentro do orçamento finito já existente.
- Erro do writer é traduzido no Runtime para os erros de slice. A fronteira do bootstrap que proíbe
  acesso direto ao store foi mantida; nenhuma asserção arquitetural foi relaxada.
- Captura sem regra efetiva faz apenas a leitura estrita dos settings, sem varrer o índice de fontes.
  RED por SQL observado, depois GREEN na suíte completa.

Provas novas incluem primeira publicação/append stale sem gravação parcial, nova oportunidade que
publica B, cartas históricas inteiras intactas e salvo de A ainda restaurável; regra removida reabre
uma caminhada que já passara pela fonte, sem duplicar histórico; reoffer mascarado volta a publicar;
conclusão de intenção antiga não avança a geração nova. A prova real do driver espera o recibo do
seu drain assíncrono, não confunde agendamento com publicação.

### Execuções e correções de instrumento

| Execução | Resultado |
|---|---|
| RED inicial | APIs de integração ausentes, erro de compilação |
| primeira prova do núcleo | 9 testes, 1 erro de fixture (`segments` de Edition ainda inexistente); corrigida a premissa, não o contrato |
| primeira compilação de integração | ENOSPC temporário, mais import/initializer inacessível; nenhum dado apagado |
| integração com um job | 144 testes, 1 falha de fronteira por erro do store citado no bootstrap; corrigida tradução no Runtime |
| integração depois da tradução | 144 testes, 0 falhas |
| provas reais cold/driver | erro inicial de `await` em autoclosure XCTest; depois premissa de cauda/caminhada e leitura anterior ao recibo; corrigidos com oportunidade real e sinais de conclusão, sem mudar políticas/assertions |
| cold/driver terminais | 2 testes, 0 falhas (0,141 s) |
| controle sem regras | RED: consulta de índice inteiro observada |
| pacote completo | **1765 testes, 1 pulado, 0 falhas**, 103,696 s |
| após reforçar no teste a recuperação de B e o salvo de A | **149 testes, 0 falhas**, 8,062 s, sem nova alteração de produção |
| app sources, `swiftc -frontend -parse` | exit 0; **somente sintaxe**, não typecheck, link, build ou execução iOS |

Logs e o resultado não vazio da checagem de sintaxe estão em
`evidence/2026-10-27-source-exclusions/t4-*`. A suíte completa antecede apenas o reforço das asserções
no teste de recuperação; a verificação final de 149 cobre esse reforço. Os seis hashes da régua seguem OK.

### App e limites restantes

O host recebeu um notificador source-only que reaproveita a associação; se ainda não há primeira
publicação, usa a recuperação fria existente. A associação só abre oportunidade estando ativa,
visível e com ingresso autorizado. O novo teste de app afirma mesma associação/Edition/âncora/prefixo.
**Esse teste e o alvo iOS não foram compilados/executados**: o parse não os substitui.

Task 4 permanece aberta nessa verificação. T5 (controles) e T6 (jornadas/aceitação/revisão final da
feature) também permanecem abertas. O editor ainda não oferece a nova regra; não há PASS UX13,
B03/B06, certificação de release ou distribuição.

### Rulings deste incremento

- Acrescentar o valor de política e a fiação em InitialProductionSlice/PendingMediaReconsideration,
  além dos arquivos originais de T4: são os owners reais de primeira publicação e reoffer. Custo se
  a decomposição mudar: mover passagem de valores, sem nova autoridade ou persistência.
- Requests ganham payload opcional de valor, preservando construtores anteriores; o pipeline de app
  sempre o preenche. Custo se o formato mudar: ajustar builders; dados publicados não mudam.
- Geração de política participa da identidade de intenção, pois invalidar só `inFlight` não distingue
  dois intentos com o mesmo instante. Custo: campo transitório adicional, sem schema/migração.
- Erros concretos de persistência são traduzidos no Runtime; custo: dois casos explícitos nos erros
  de slice. O bootstrap continua sem conhecer o store.

## Bloqueio de capacidade na validação iOS

A condição abaixo da guarda de 3 GiB persiste por pelo menos três retomadas consecutivas:
707 MiB no desenho (`e5f75031`), 641 MiB após T1–T3 (`93bbc7cf`) e **670 MiB** nesta rodada.
Uma compilação de pacote com dois jobs chegou a ENOSPC; com um job foi possível concluir o pacote.
Isso não comprova capacidade para um build iOS isolado e seus resultados de teste.

O diretório de trabalho e `/private/tmp` estão no mesmo volume, ambos com 670 MiB livres. O scratch
inteiro mede 1,3 GiB e contém produtos, fontes de dependências e caches: nem removê-lo inteiro
atingiria 3 GiB, além de destruir o build já verificado. Nenhum cache, produto, banco, simulador ou
artefato foi apagado. Nenhuma execução própria permanece em voo.

O próximo gate necessário é compilar/executar `FeedMineAppTests/ContentFilterTests` e o novo caso
source-only num build iOS identificado; depois prosseguir T5/T6. Não substituir esse gate por mais
testes de pacote nem marcar T4 concluída. É necessário deixar pelo menos 3 GiB livres no volume de
trabalho para retomar essa validação com a margem registrada do projeto.

## Continuação após limpeza autorizada — incremento parcial T5

Auditoria: `docs/reviews/2026-10-27-authorized-cleanup.md`. A limpeza chegou a 2,49 GiB livres,
antes da regeneração de caches. Não atingiu o guard de 3 GiB para build iOS. T4 continua aberta.

O backend de filtros agora projeta/grava `sourceExclusions` no campo existente, preservando seleção,
palavras e modelos. Compara a política efetiva e aguarda o callback de composição antes de retornar;
remover uma regra mascarada não inventa oportunidade de supply. O master switch conserva as regras.
O store oferece inclusão/remoção por SourceID e restaura a lista persistida quando uma gravação falha.
A seção de fontes excluídas mostra nomes congelados e remoção explícita, com copy pt/en e AX por identidade.
A fábrica do app fornece a notificação source-only existente; não invoca substituição de sessão.

TDD: backend RED por API ausente, GREEN 1/1; store RED por API ausente, GREEN focado 8/8 incluindo
política e produção. Logs `t5-*.log.gz` e parse syntax-only do app estão no diretório de evidência F13.
O parse não demonstra typecheck/link/execução iOS.

**Ainda pendentes de T5:** ação confirmada na superfície da fonte (catálogo e importadas), recuperação
na ausência de nova supply, validação app e acessibilidade em tela. Nenhum checkbox de conclusão de T5
foi marcado. T6 e as ressalvas de histórico de palavras/B03/B06 continuam abertas.

Verificação final deste incremento: suíte completa do pacote **1767 testes, 1 skip, 0 falhas**,
99,452 s; parse do app exit 0 (apenas sintaxe); seis hashes do avaliador OK; diff sem erros.
Espaço após a regeneração de caches: cerca de 2,3 GiB, ainda abaixo do guard iOS.


## Continuação — ação explícita no catálogo

O menu de uma fonte do catálogo oferece “Não publicar mais desta fonte”, também como ação de
acessibilidade, e pede confirmação sobre novas publicações, preservação de histórico/salvos e reversão.
O host resolve o key pela mesma autoridade existente usada para abrir a fonte, passa o SourceID ao
store de filtros e aguarda a gravação/notificação. A operação não chama adoção de seleção nem abertura
ou substituição de sessão. Erro de resolução/gravação produz mensagem de falha ao salvar.
O editor de rascunho de filtros, que compartilha NodeSourcesView, não oferece essa ação: o host não
fornece o callback nessa superfície. A fonte conserva seu toggle independente.

O teste app de continuidade agora chama a ação real do host e compara seleção/version/contexto,
além de associação/Edition/âncora/prefixo. **Execução iOS ainda NOT_RUN:** o parse só prova sintaxe.
O pacote compilou NodeSourcesView e passou os dois testes de backend/store; isso não prova a confirmação
nem os controles em tela. Copy pt/en e identificadores AX estão presentes; jornada visual pendente.

Restam ação acessível para fonte importada, recuperação de supply, testes iOS e T6. A frente continua aberta.

Verificação final da ação do catálogo: pacote **1767 testes, 1 skip, 0 falhas**, 97,052 s;
parse de AppComposition/FeedMineApp/ContentFilterTests exit 0 (sintaxe somente), hashes do avaliador 6/6,
diff sem erros. Espaço livre ~2,3 GiB; build iOS não iniciado.


## Continuação — switch dos ajustes e recuperação de regras

Causa inspecionada: o master switch da tela geral grava por ReaderSettingsBackendAdapter,
que apenas sinalizava invalidação de cache; o callback de exclusões só existia no editor específico.
O backend geral agora compara snapshots efetivos antes/depois da gravação e aguarda a notificação
source-only antes de retornar. Mudanças de aparência não notificam essa política; desligar mantém
as regras. A fábrica do app fornece o callback, e a notificação de fonte invalida o snapshot de settings.
RED: callback ausente; GREEN: 11 testes focados de filtros/settings/produção, zero falhas.

No fim da supply, FeedScreen aceita o callback de recuperação somente quando o host informa regras
ativas. A mensagem informa a existência de exclusões sem atribuir a elas toda exaustão de supply.
A ação “Rever fontes excluídas” leva diretamente ao editor existente, em sheet com Concluir.
Com histórico, o bloco vem depois das cartas; sem histórico, acompanha a ausência de supply.
RED: interface de recuperação ausente; GREEN: 28 testes focados, incluindo renderização OCR que
compara cartas/ordem/occurrenceIDs antes e depois. Nova prova de ausência de histórico foi incluída
na suíte completa. Copy pt/en e AX presentes; não equivalem a jornada iOS.

Continuam pendentes a superfície para fontes importadas e as provas iOS de T4/T5/T6, incluindo
acessibilidade real, relaunch e guards de aceitação. A margem de espaço iOS continua insuficiente.


### Perda de regras ao voltar do editor — reproduzida e corrigida

A revisão causal encontrou um segundo caminho: ReaderSettingsStore mantinha settings da abertura
da tela. Após o editor filho gravar regras, mudar o master switch aplicava a intenção a essa cópia
antiga e gravava as listas vazias. Regressão com backend real reproduziu **três falhas**: perda das
fontes, palavras e modelos. O store agora lê o valor atual pelo backend antes de aplicar a intenção
e relê depois da gravação. A correção preserva as regras do editor filho; teste GREEN com 9 testes
focados, zero falhas. Não se afirma transação atômica entre escritores concorrentes: esta prova cobre
o fluxo serial de navegar/editar/voltar ao ajuste, antes quebrado.

A suíte intermediária anterior a essa correção passou 1770 testes, 1 skip, zero falhas (97,657 s),
incluindo a recuperação sem histórico. Esse log é intermediário; a suíte final é registrada à parte.


Verificação final deste incremento: **1771 testes, 1 skip, 0 falhas**, 97,063 s. Os testes de renderização
incluem fim com histórico e fim sem apresentação. Parse app exit 0 (somente sintaxe), avaliador 6/6,
diff sem erros. O teste app de continuidade também verifica master off pela tela geral, regras
persistidas e mesma associação/Edition/âncora/prefixo; **não executado em iOS**. Espaço livre ~2,3 GiB.


## Continuação — fontes importadas na superfície de Fontes

A tela Fontes agora mostra as entradas da autoridade reader_imported_sources, inclusive sem catálogo.
O host passa key/nome conhecido; nenhum UUID é digitado. A ação de importadas exige um registro de
importação existente e usa o resolvedor operacional já existente, preservando namespace/aliases.
Uma fonte nova do leitor usa identidade reader; uma fonte já estabelecida como catálogo conserva
essa identidade mesmo quando importada. Não criar identidade alternativa só porque a linha é importada.
O menu de exclusão, confirmação descritiva, AX e falha ao salvar são compartilhados com o catálogo.
O callback só grava a regra e notifica; não modifica seleção/autoridade de aquisição.

TDD: RED por interface de lista ausente. Primeira captura OCR retornou vazia: List nativa ainda não
havia desenhado; o teste agora aguarda um ciclo de display AppKit. O caso passou isolado. A primeira
suíte completa encerrou com sinal 11 após esse teste: o diagnóstico aponta objc_release em
_NSWindowTransformAnimation dealloc. A janela de teste agora desativa animação e não se libera
automaticamente ao fechar. A classe inteira passou **22 testes, zero falhas**, 8,024 s. Logs de falha,
interrupção controlada e resumo do diagnóstico foram preservados; não são evidência GREEN.

Dois casos app foram adicionados: identidade reader conhecida/recusa de chave desconhecida e
preservação de identidade catalog anteriormente registrada. Ambos continuam **NOT_RUN em iOS**;
parse é somente sintaxe. As jornadas de confirmação/cancelamento/reversão e acessibilidade continuam
parte de T6, sem alegação de PASS por compilação do pacote.


Verificação final de importadas: suíte completa **1772 testes, 1 skip, 0 falhas**, 97,537 s;
app parse exit 0 (sintaxe somente); avaliador 6/6; diff sem erros. Espaço livre ~2,1 GiB.
T4/T5/T6 seguem abertas nos gates iOS/aceitação. A tentativa de compressão não foi aplicada a originais.
