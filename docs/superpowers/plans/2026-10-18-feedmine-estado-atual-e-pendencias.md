# FeedMine — estado atual, avanços e plano das pendências

**Data de corte:** 18/10/2026, 14h21, America/Vancouver.  
**Objetivo:** transformar o desenvolvimento existente em uma candidata reproduzível, com descoberta contínua, leitura estável, retorno local e evidências de aceite.  
**Arquitetura:** preservar os owners de aquisição, preparação, publicação, sessão e apresentação. Resolver lacunas nos caminhos reais e consolidar evidências antes de expandir funcionalidades.  
**Tecnologia:** Swift 6, SwiftUI, GRDB/SQLite, AVFoundation, XCTest/XCUITest e instrumentos existentes.  
**Natureza:** revisão e plano de trabalho; não implementa correções nem aprova publicação.

## 1. Conclusão executiva

O FeedMine avançou além da avaliação inicial do build 53. Há correções locais para os dez achados daquela avaliação, busca conectada à interface, diversidade editorial persistida, melhorias de residência de imagens e redução medida de engasgos em um cenário Release. B01, B02, B04 e B05 têm vereditos PASS em execuções inspecionadas.

**Ainda não há uma candidata única certificada.** O produto está numa worktree com alterações não commitadas; B03 tem último resultado concluído FAIL e nova execução sem veredito no corte; B06 não foi executado no iPhone. Há lacunas de UI, acessibilidade, primeira abertura e proveniência dos resultados. O próximo investimento deve fechar esses pontos, preservando o trabalho pronto.

Não há base para um percentual de conclusão: os gates têm pesos e riscos diferentes. Muitos testes unitários verdes não encerram a promessa de descoberta e leitura prolongada.

## 2. Qual estado foi efetivamente revisado

| Camada | Identificação | Interpretação |
|---|---|---|
| Checkout desta revisão | `docs/status-pause-2026-10-17@711cfac3` | Linha documental; não representa o produto mais recente |
| Base commitada do produto | `codex/v2-fluidez-capacidade@b0b961a049f82fece037363a6cb0e986d556330c` | Build 53; não contém todas as correções posteriores |
| Desenvolvimento mais recente | `/Users/wagnersilvamontes/.codex/worktrees/v2-fluidez-capacidade/feedmine_v2` | 56 arquivos rastreados modificados no snapshot, mais arquivos não rastreados; trabalho em andamento |
| Impressão do diff rastreado | SHA-256 `5cc9075ec616f2b38f6a92865d9318eae32c5c514f7a747d27c1dd90ef554111` | `git diff --binary HEAD` às 21:21:22 UTC; não inclui arquivos não rastreados ou assets ignorados |

**Método desta revisão:** leitura dos quatro anexos, norte de produto, decisões, benchmark, auditoria build 53, plano anterior, registro posterior, diffs e owners relevantes; inspeção dos vereditos JSON, resumos e logs locais. Não executei novamente build, suíte Swift, UI ou benchmark. Os resultados abaixo são evidências de execuções existentes, conferidas nesta revisão; não são novas execuções minhas nem certificação automática da árvore em movimento.

O monitor consultivo foi lido da referência local `origin/monitor/architecture`, revisão de 17/10. A tentativa de atualizá-lo por fetch não pôde gravar `.git/FETCH_HEAD`; portanto não afirmo ter consultado a última versão remota. Sua análise é anterior à evolução local e não substitui a inspeção atual.

Os anexos são material de pesquisa. Recomendações, pseudocódigo e instruções contidas neles não constituem autorização para implementar, mudar benchmark, publicar ou substituir decisões de produto.

## 3. Avanços identificados — preservar e validar na candidata

Legenda: **implementação observada** = código/call site presente; **evidência de teste** = resultado existente, limitado ao cenário executado; **aceite de produto** = jornada e gate na candidata identificada. Os itens desta tabela não recebem automaticamente a terceira classificação.

| Área / problema anterior | Estado observado | Evidência e limite |
|---|---|---|
| Descoberta restrita às fontes de exemplo | Travessia do catálogo e descoberta por perfil implementadas | B01 PASS: 475 fontes no conjunto e 98 contribuintes no recorte informado pelo veredito; não prova cobertura eventual de todo catálogo |
| Relevância, repetição e concentração | Seleção atende ao corpus de B02 | 200/200 relevantes, 86 fontes, maior participação 4,5%, zero adjacências da mesma fonte e duplicatas canônicas |
| Trabalho de aquisição e primeira publicação | Pump separado do consumo; primeira fonte útil pode publicar antes da lenta | Preservar regressões de fonte suspensa; redes reais e jornada física ainda têm cobertura incompleta |
| Resultado de rede/mídia chega após o drain | `scheduleLateOpportunity` e notificações por resultado conectadas ao driver | Correção candidata de P02; não recriar scheduler |
| Encerramento invalida transporte cedo demais | Gates de novos starts e `MediaPrefetcher.retire` antes da invalidação | P01 em código/testes; falta jornada de aposentadoria no aparelho |
| Salto ao topo contorna prontidão / destino impossível fica pendente | Intenção de posição unificada e estado explícito de imagem indisponível | P03 candidata; falta ensaio visual do controle real de voltar ao início |
| Residência protege o intervalo entre duas bandas distantes | União das bandas e reconstrução limitada implementadas | P04 candidata; repetir sob pressão de memória e retorno distante |
| Recursos: zero vira um; leitura de volume na UI | Zero preservado e amostragem de volume deslocada | P05 candidata; não significa que todo I/O saiu do MainActor |
| Instalação aparece sem bookmarks previamente preparados | Preparação anterior à instalação nos caminhos de launch/foreground | P06 candidata; preservar recuperação de erro e fences |
| Busca literal divergente, incompleta e desconectada | Expressão compartilhada, resultados tipados, paginação e erros por autoridade ligados à interface | P07/P08 locais; validar negativos, múltiplos campos, continuação, cancelamento e busca salva offline |
| Diversidade dormente / versão desconhecida / comparador cíclico | v5 explícita, chaves comparáveis por grupo e fatos persistidos com a publicação | P09/P10 locais; falta comparação fim a fim entre bancos/restaurações |
| Neutralidade, filtros e fonte interna | Correções presentes na linha de produto | Preservar R11–R15/R19; testar persistência, desfazer e A→B→A |
| B04/B05: resposta temática reconstruía sessão em andamento | Correção local impede rebuild indevido; regressão vermelho/verde registrada | Vereditos posteriores B04/B05 PASS; manter o limite de medição de repouso de B04 |
| Engasgos repetidos por consulta de idiomas no corpo da view | Grupos reutilizados por catálogo, com invalidação na ativação | A/B Release: 5,44% → 0,12% de frames perdidos em 24 gestos/12 cards textuais no simulador; não equivale a B03/B06 |
| Player, mini-player e progresso | Já existem `MediaPlaybackAdapter`, `ReaderMediaCoordinator`, `MiniPlayerBar`, comandos remotos e armazenamento de posição | Não planejar áudio básico e mini-player como desenvolvimento do zero; ampliar provas e corrigir lacunas |

## 4. Matriz de evidências atuais

Os diretórios de execução abaixo ficam na **worktree de produto**, não neste checkout documental. Cada corrida sobre árvore suja pode conter bytes diferentes, apesar do mesmo SHA-base.

| Verificação | Última evidência inspecionada | Estado para a próxima candidata |
|---|---|---|
| Pacote Swift | `docs/reviews/evidence/2026-10-18-suite-final/swift-package-tests.log`: 1.505 executados, 1 skip, zero falhas | Histórico positivo; repetir após congelar candidata |
| Build Debug/Release | Sucesso registrado no relatório posterior | Sem nova execução nesta revisão |
| UI completa | 74 testes, 62 PASS, 4 testes FAIL, 8 SKIP; log registra 12 falhas de asserção | Suíte ainda vermelha; não confundir 12 asserções com 12 testes falhos |
| B01 | `bench/run/20261018T173653Z/B01.verdict.json`: PASS | Revalidar no SHA final |
| B02 | `bench/run/20261018T174540Z/B02.verdict.json`: PASS | Revalidar no SHA final |
| B03 | Último resultado concluído registrado: 1.716/1.800 avanços; zero pausas ≥1 s, duplicatas ou adjacências indevidas | FAIL até nova prova; `20261018T205726Z` ainda sem `B03.verdict.json` no corte |
| B04 | `20261018T204639Z` e `20261018T205047Z`: PASS | Ressalva: `b04-idle-stable` = `not-measurable`; falta provar integralmente o repouso exigido |
| B05 | `20261018T205428Z/B05.verdict.json`: PASS | Salvos, âncora, retorno e offline verdadeiros no percurso; repetir na candidata |
| B06 | Sem execução física atual | NOT_RUN; depende de iPhone(s) compatível(is) e medição |
| Headroom | Carga sintética de 1.000 fontes/10.000 candidatos; registro de 5.467 publicados/s | Prova local de capacidade; não prova entrega sustentada de rede, frames ou consumo real |
| Cold start / acessibilidade | First display-link e árvore AX disponíveis; cold start sem medida válida, VoiceOver falado ausente | Abertos; callback de display-link não comprova primeiro conteúdo visível |

Os arquivos `manifest.check` e `evaluator.check` das corridas B01/B02/B04/B05 listadas contêm, respectivamente, 2.314 e 6 verificações sem linhas `FAILED`. Isso sustenta a integridade registrada naquelas execuções; não substitui nova checagem da candidata.

### Divergências documentais a corrigir

1. O registro pós-build53 tem seção recente com B04/B05 PASS e resumo G4 antigo que ainda os chama de vermelhos. Prevalecem os vereditos datados para descrever aquelas corridas; G4 continua aberto pela ausência de candidata certificada.
2. A narrativa de fluidez diz zero eventos severos após a correção; `release-hitch/summary.json` informa **2**. Usar 2 até reconciliar com o JSONL bruto. O ganho 5,44% → 0,12% permanece no resumo.
3. O resumo JSON chama um evento de display-link de primeiro frame apresentado; a narrativa posterior reconhece que ele ocorre mesmo sem conteúdo novo composto. Não usar 73 ms ou 576,4 ms como tempo de primeira história visível.
4. Há referências a 69 testes e depois 74. São rodadas distintas. O último resumo inspecionado termina com `TEST FAILED`; skips justificados continuam sendo ausência de cobertura.
5. README e benchmark contêm status históricos de outros builds. Não usá-los para afirmar que o produto atual passou todos os gates.

## 5. Plano priorizado do restante

**Prioridade de execução:** P0 = bloqueia a candidata/aceite; P1 = correção ou prova necessária na jornada; P2 = evolução posterior. Não equivale automaticamente à severidade técnica de cada achado. **Esforço:** baixo = escopo localizado; médio = vários owners/integração; alto = ensaio prolongado, plataforma ou causa ainda desconhecida. Não são prazos contratados.

| ID | Trabalho e entrega | Prioridade / esforço | Benefício / risco principal | Dependência e critério de conclusão |
|---|---|---|---|---|
| E01 | Fixar snapshot reproduzível: branch/SHA, diff final, manifesto dos assets e estado dos testes | P0 / baixo–médio | Evita perder correções ou certificar bytes diferentes | Coordenar com executor ativo; preservar WIP. Candidata reconstruível, sem alteração funcional durante os gates |
| E02 | Diagnosticar e fechar B03 | P0 / alto e incerto | Entrega a promessa de continuar lendo; risco de confundir replay com produto | Aproveitar execução em andamento; medir avanço distinto, gestos, oferta pronta, publicação/admissão e relógios. Completar trace congelado, sem reduzir limiares ou declarar overhead sem prova |
| E03 | Completar estabilidade de repouso e navegação real | P0 / médio | Evita saltos, branco e perda de ponto | Exercitar 10 min parado, chegada tardia, voltar ao início, asset indisponível, memória e retorno distante; IDs/bounds/offset estáveis e bitmap observado. B04 automático sozinho não fecha a lacuna |
| E04 | Executar B06 e jornadas de lifecycle no iPhone | P0 / alto | Revela memória, térmica, energia, hitches e interrupções reais | B03 estabilizado e candidata identificada; preservar corpus, coletar séries/picos. Validar dispositivo de referência e alvo segundo benchmark; registrar impedimentos reais |
| E05 | Encerrar a suíte UI com causas classificadas | P0 / médio–alto | Separa defeito, infraestrutura e automação | Restaurar catálogo/rede em namespace de teste para os casos reais; resolver controle de fechar Safari/U2 ou obter evidência manual rastreável para o contrato. Suite fica explicitamente FAIL/BLOCKED enquanto houver falha; não trocar prova real por fixture e dizer que é equivalente |
| E06 | Completar acessibilidade e instalação limpa | P1 / médio | Usabilidade e confiança na primeira experiência | VoiceOver falado, Dynamic Type incluindo contexto ativo, iPad/rotação e locales suportados; cold launch com primeiro conteúdo visível medido e origem dos relógios válida |
| E07 | Validar busca/diversidade ponta a ponta | P1 / médio | Relevância e controle com menor retrabalho | Dois bancos/relançamentos, v5 e versões antigas, campos ausentes, negativos, fontes/artigos paginados, erro parcial, cancelamento e busca salva offline; confirmar integração P07–P10 sem reescrever os owners |
| E08 | Completar durabilidade/lifecycle | P1 / médio | Preserva dados pessoais e continuidade | Force quit, purge de cache, falta de disco, salvo em duas caixas, falha de gravação, grant expirado, BGTask do host e aposentadoria com mídia pendente; nenhum start não autorizado ou perda silenciosa |
| E09 | Consolidar entrega e documentação | P0 de saída / médio | Uma decisão de release auditável | Reexecutar B01–B06 e verificações necessárias no mesmo candidato; matriz única de estado e limitações; revisão do diff; empacotamento e catálogo verificados |
| E10 | Evolução editorial/mídia dos anexos | P2 / incremental | Melhora valor percebido após base confiável | Executar o segundo plano em fatias. Nenhuma nova integração de mídia deve adiar E02–E05 |

### Sequência recomendada

- [ ] **Etapa A — reconhecer o WIP:** registrar E01, ler resultado terminal de B03 quando existir e reconciliar os resumos. Não interromper nem sobrescrever a execução ativa.
- [ ] **Etapa B — corrigir o que ainda falhar:** E02/E03, regressão discriminante antes da correção; preservar B04/B05 positivos, sem presumir que dispensam repetição.
- [ ] **Etapa C — fechar provas integradas:** E05–E08; resolver infraestrutura antes de gastar novas rodadas completas com a mesma causa conhecida.
- [ ] **Etapa D — estabilizar os bytes da candidata:** incorporar somente correções verificadas, registrar manifesto e reconstruir artefato.
- [ ] **Etapa E — aceite:** E04/E09, incluindo toda a matriz B01–B06 e limites de medição. Se mudar código após um gate, reavaliar quais provas foram invalidadas.

Os trabalhos exigem papéis distintos: executor Swift/iOS para E01–E03/E07/E08; QA com acesso ao aparelho para E04–E06; responsável por release para E09. São responsabilidades sugeridas, sem novas atribuições ou mensagens a terceiros nesta revisão.

## 6. Onde intervir e como verificar

| Frente | Owners/arquivos de partida na worktree de produto | Verificação que distingue correção de aparência |
|---|---|---|
| Continuidade B03 | `FeedRunwayDriver`, `RunwayAcquisitionCycle`, `RunwayController`, `FeedSession`, `AppComposition` | Trace completo e avanços distintos; fonte lenta liberada depois do drain com usuário parado |
| Posição/pixels | `FeedDestinationGate`, `FeedNativeViewport`, `FeedScreen`, `FeedSession` | Controle real, perda/recuperação de asset, salto longo e repouso; vídeo e coordenadas |
| Busca | `ReaderSearchResults.swift` do app, `ReaderSearchResultsStore`, `ReaderShell`, `LegacyCatalogReader` | Resultado válido fora da primeira página; consulta com negativos e campos diferentes; autoridade falha visível |
| Diversidade | `SelectionEngine`, `SelectionDiversity`, `PublicationStore+Writing/Presentation`, `LocalProductionSlice` | Ordem consistente sob permutação, fatos congelados restaurados, não alterar publicação antiga |
| Durabilidade e catálogo | `SavedMediaCoordinator`, `ReaderLibraryCoordinator`, `CatalogInstallation`, migrações | Processo realmente encerrado, offline real, purge e recuperação; não apenas reabrir handle |
| Player | `MediaPlaybackAdapter`, `ReaderMediaCoordinator`, `ReaderPlaybackPositionsAdapter` | Som/posição/controles reais durante scroll, filtro, interrupção e background; medir SQL síncrono no MainActor |

Comandos de referência: `swift build`, `swift test`, testes do scheme **FeedMine**, e `scripts/run-discovery-benchmark.sh --gate B01 --profile A --profile B` (demais gates com o launcher correspondente). Inspecionar a ajuda e o runbook existentes antes da execução; não chamar diretamente `bench/run.sh` omitindo o launcher que configura o transporte. B06 precisa do alvo físico e configuração de transporte previstos no projeto.

## 7. Restrições e critério de saída

- Preservar catálogo público como autoridade, separação do runtime pessoal, transações, identidades e publicação imutável.
- Preparação/readiness antecede exposição. Imagem ausente não autoriza reescrever um card publicado como texto.
- Nada de rede/SQL/parsing/decode bloqueante no renderer ou callback visual; validar executor efetivo, inclusive caminhos indiretos.
- Não adicionar cache semântico, runtime, fila ou scheduler paralelo para contornar um owner incompleto.
- Não alterar corpus, driver, oráculo, limiares ou duração para obter PASS. Instrumentação complementar fica fora da régua congelada.
- Não apagar containers pessoais, branches ou worktrees para limpar o cenário de teste.

**Pronto para decisão de publicação:** uma candidata identificada; todos os gates obrigatórios comprovados nos bytes pertinentes; suíte e exceções explicitamente reconciliadas; lacunas de repouso, offline, acessibilidade e aparelho encerradas ou formalmente mantidas como impedimentos. TestFlight disponível e bump de versão não substituem esse aceite. Este plano não executa merge, push ou release.

## 8. Rastreabilidade

- [Auditoria do build 53](../../reviews/2026-10-18-v2-avaliacao-build53.md) e [plano anterior pós-build53](2026-10-18-v2-restante-pos-build53.md): baseline, não fotografia final do WIP.
- [Registro posterior na worktree de produto](/Users/wagnersilvamontes/.codex/worktrees/v2-fluidez-capacidade/feedmine_v2/docs/reviews/2026-10-18-v2-execucao-pos-build53.md): entregas P01–P16, medições e contradições históricas.
- [Resumo da suíte UI](/Users/wagnersilvamontes/.codex/worktrees/v2-fluidez-capacidade/feedmine_v2/docs/reviews/evidence/2026-10-18-suite-final/summary.txt) e [resumo Release A/B](/Users/wagnersilvamontes/.codex/worktrees/v2-fluidez-capacidade/feedmine_v2/docs/reviews/evidence/2026-10-18-release-hitch/summary.json).
- [Norte](../../product/PRODUCT_NORTH_STAR.md), [decisões](../../product/PRODUCT_DECISIONS_2026-10-09.md), [invariantes](../../architecture/PRODUCT_INVARIANTS.md) e [benchmark](../../product/DISCOVERY_ACCEPTANCE_BENCHMARK.md).
- [Plano de aproveitamento dos estudos](2026-10-18-feedmine-aproveitamento-dos-estudos.md): oportunidades futuras, custo-benefício e riscos.

Links absolutos para a outra worktree dependem de sua permanência local. E01/E09 devem preservar as evidências necessárias em uma localização durável antes de arquivá-la.

## 9. Execução em 2026-10-18/19 (adendo operacional)

Este adendo registra o que foi executado sobre a worktree de produto. Não altera a natureza do plano: não há commit,
merge, push ou release, e nenhuma lacuna abaixo foi convertida em PASS por fixture.

**Candidata identificada:** `codex/v2-fluidez-capacidade@b0b961a0`, diff completo `3d8b068f…`, **produto
`dc63a761…`**, 62 arquivos modificados. Evidência consolidada em
`<worktree>/docs/reviews/evidence/2026-10-18-candidate-snapshot/` (`identity.txt`, `assets.sha256`,
`candidate.patch`, `candidate-assets.tgz`, README).

| Item | Estado em 2026-10-19 | Evidência |
|---|---|---|
| E01 | **feito** | identidade + **`candidate.patch`** (aplicado a worktree limpo em `b0b961a0` reproduz o diff `3d8b068f…` e o produto `dc63a761…`) + **`candidate-assets.tgz`** (catálogo e corpus, conferidos contra `assets.sha256`) + suítes, em `docs/reviews/evidence/2026-10-18-candidate-snapshot/` |
| E02 | **feito** | B03 PASS: 3.398 avanços, 0 paradas ≥1 s, 2.309 candidatos, **475/475 fontes HTTP 200** (`bench/run/20261019T043856Z`); causa raiz e regressão discriminante documentadas |
| E03 | **parcial** | repouso de 10 min + chegada tardia + retorno distante PASS (`docs/reviews/evidence/2026-10-18-e03-rest/`); delta de 16 pt registrado como margem de conteúdo e **offset não fechado a ±1 pt**; memória e asset indisponível não cobertos; janela de uma carta com 40 itens/atraso 30 s registrada como achado |
| E04 | **bloqueado** | iPhone listado como Offline; nenhuma medição física |
| E05 | **encerrado com exceções classificadas** | `FeedMineAppTests` **156/0** (`run-final7-apptests`); `FeedMineUITests` 75 testes / 9 skips / **11 asserções em 5 testes** (`run-final3`), causas: infra de catálogo real (2 testes) e plataforma SafariViewService (3 testes, reproduzidos no HEAD). O reopen **passou** com o instrumento corrigido (cold 1.188 ms / warm 884 ms); a falha anterior era **incapacidade da fixture** de cobrir o perfil respondido (descoberta aponta fontes reais; `LOCAL_FEEDS` só cobre dev feeds; `BLOCK_RSS_NETWORK` derruba o resto: `cards=0`, 389 s, "Não foi possível conectar…"). U2 passou no leitor **local** — o fechamento do leitor **de site** permanece sem prova (`docs/reviews/evidence/2026-10-18-ui-suite/`) |
| E06 | **parcial** | iPad/rotação, Dynamic Type, locales, instalação limpa e warm relaunch verdes; **cold start medido sem descoberta** (`FEEDMINE_DISABLE_DISCOVERY=1`): 1.188–1.314 ms (warm 793–884 ms; 4 passagens de `launch-progress` entre 519–948 ms na fria). A variante com perfil de descoberta + transporte bloqueado é o stall de fixture (`cards=0`, 389 s), condição diferente. Aberto: VoiceOver falado; superfície de progresso fria (~0,5–0,9 s) é observação |
| E07 | **parcial** | diversidade restaurada→engine (v5 e v4), expressão negativa, paginação do host (artigo e fonte) e falhas explícitas de `.saved` e `.content` e abertura de resultado de fonte cobertas por testes novos. Gaps: relançamento de processo (tentativa de UI medida e retirada), cancelamento em voo, retry/superfície de erro, destinos `.savedCard`/`.article` (`docs/reviews/evidence/2026-10-18-e07-e08/`) |
| E08 | **parcial, com a escrita corrigida** | escrita de `saved_media_availability` deixou de ser silenciosa: `recordState` devolve `.failed` quando o registro falha e um `pending` recusado não inicia a preparação; prova red→green com trigger `BEFORE INSERT`. Permanecem: force quit durante preparação, purge real, disco real, BGTask real, apresentação do `.failed` na UI |
| E09 | **consolidado até aqui** | matriz B01–B05 no diff `f5092e6f`, cujo **produto é byte-idêntico** ao atual (produto `dc63a761…`, diff completo `3d8b068f…`; `diff -r` em `Sources/` e `FeedMineApp/FeedMineApp/` = zero); pacote 1.509 testes/1 skip/0 falhas; app 156/0; suíte UI `run-final3` (75/9/11); impedimentos nomeados |
| E10 | não iniciado | permanece posterior a E02–E05 |

**Correções de produto aplicadas nesta execução:** (1) páginas de descoberta herdavam `authorizedNonPublicOrigins`
vazio — o transporte local recusava todo alvo descoberto depois da primeira página; (2) o evento de
`position_checkpoint` não era descarregado no trace e a posição durável de B05 ficava sem prova; (3) a resposta dada
durante a construção da associação não era relida antes de fixar o perfil de discovery; (4) a escrita de
`saved_media_availability` era engolida por `try?` e podia reportar disponibilidade sem linha durável.
**Correção de instrumento:** o exercício de cold start passou a desligar a descoberta nas duas aberturas medidas.

**Gates no diff `f5092e6f` (produto idêntico ao atual):** B01 A+B PASS (`20261019T041638Z`), B02 PASS
(`20261019T042513Z`), B03 PASS (`20261019T043856Z`), B04 PASS (`20261019T043138Z`, protocolo completo), B05 PASS
(`20261019T043521Z`); B06 **NOT_RUN** (aparelho offline).

**Critério de saída:** ainda **não** satisfeito para decisão de publicação, porque B06, VoiceOver, o offset de
retorno de E03 (16 pt; decisão pendente) e os gaps de durabilidade remanescentes permanecem impedimentos formais — e
não porque falte uma candidata identificada.
