# MIG-V1V2-B — Migração pessoal sem perda, com legado recuperável

**Spec de execução e delegação do arquiteto — P0 de certificação de upgrade. Versão 1.3, 2026-10-15, base pós-P0D verificada.**

## 1. Decisão e fronteira

- **Escolha: opção B.** Preservar os dados pessoais da V1 na autoridade durável da V2; converter apenas equivalências comprovadas; manter o restante recuperável e inventariado, sem fabricar ocorrências publicadas.
- **Gate novo e independente:** `MIG-V1V2-B`. Não anexar ao PD10-P0D. O P0D regula a continuidade de identidade **dentro** da V2; este gate transporta dados de outra versão e de outras autoridades.
- **Repositório de implementação:** `github.com/wsmontes/feedmine_v2`. A V1 (`github.com/wsmontes/feedmine-dev`, referência auditada `712a6ba9`) é **somente leitura e fonte de fixtures/contratos**. Não modificar a V1.
- **Base de implementação CONGELADA:** `dee94e2ef251212ad33ecb422433be3d101e63f6` (`origin/main` verificado no GitHub em 2026-10-15, tree `f535205ae4ee8fddc9fe8dfab66fcf6cbe01c8bf`). Esta base contém o P0D aceito `c8c1b508fe7f81acfe532cb83465a7eb00f4ec3f` e o registro de integração `docs/reviews/2026-10-15-p0d-integracao.md`. Confirmar local e remoto antes de abrir a branch; se `origin/main` tiver avançado, **parar e pedir rebase autorizado**, não adotar uma nova base silenciosamente. Branch **exata:** `chatgpt/mig-v1v2-b-personal-preservation`. **Um único commit** do implementador sobre a base efetiva; reportar SHA completo, árvore Git e `git diff --name-only <base> HEAD`. Não publicar em `main`, fazer rebase ou resolver fronteira por conta própria.
- **Entrega:** branch remota, **um commit**, diff dentro da allowlist, documento de evidência preenchido e instruções objetivas ao executor Mac. Não declarar `PASS` para comandos não executados. Se não houver acesso ao repositório GitHub, reportar `SEM-ACESSO-GITHUB` e parar, sem simular commits.
- **Estado de release:** upgrade V1→V2 = `BLOCK`; release geral não certificada. Isto não é autorização para publicação, TestFlight ou merge.

## 2. Achados que determinam o desenho

1. `LegacyUserStateReader.collections()` da V2 lê `source_collection_member.source_url`, mas a V1 moderna possui **também** `source_identity`; a V2 gravava o valor lido como `source_key`. URL de aquisição e identidade canônica **não são intercambiáveis**.
2. O importador `LegacyUserStateImport.run` importa nomes de caixas, coleções e parte dos smart feeds, mas **conta e descarta os artigos salvos**. `bookmark_item` é a autoridade de pertencimento na V1; `bookmark_snapshot` guarda conteúdo, inclusive após remoção do item no banco de conteúdo.
3. Os toggles da V1 são mantidos em `UserDefaults` (`toggleDisabled`, `toggleEnabledOverrides`, incluindo chaves `url:`, `cat:`, `region:`). A tabela V1 `imported_source` mantém fontes pessoais e seu flag `enabled`. Portanto o transporte só do SQLite é insuficiente.
4. Parte do estado pessoal pode existir no banco de conteúdo ou em preferências: `source_history_access`, intenção pendente `user_operation`, playback e outras escolhas. Nem tudo tem uma contraparte operacional direta na V2.
5. V1 pode ter `user.sqlite` em `Application Support/Feedmine` ou, em instalações antigas, `Documents`; a V1 possuía política de migração desses caminhos. A V2 possui `runtime.sqlite` em `Application Support/FeedMine` (atenção à capitalização e semântica do filesystem). A localização real no contêiner deve ser verificada; não deduzir a partir de uma configuração de testes.
6. `ReaderLibraryStore.reader_bookmark_memberships` da V2 referencia `published_cards` por `card_id`. Nunca inserir IDs V1, snapshots ou cards artificiais nessa relação.

## 3. Invariantes vinculantes (V1–V12)

**V1 — V1 intocada.** Ler as autoridades anteriores sem gravar, mover, apagar, redefinir ou modificar `user.sqlite`, WAL/SHM, banco de conteúdo, preferências e JSON legado. Fazer a leitura em modo consistente com WAL; não confundir cópia de `.sqlite` sem WAL com snapshot transacional.

**V2 — Uma autoridade durável V2.** O destino dos dados preservados é o `runtime.sqlite` existente, por migração aditiva em `RuntimeMigrations` e métodos do owner existente. Não criar um segundo banco V2, arquivo paralelo de verdade, novo cache ou scheduler.

**V3 — Artigos salvos completos quando possível.** Para cada `(list_id,item_id)` de `bookmark_item`, importar sua pertença à caixa, ordenação e data; associar o conteúdo de `bookmark_snapshot` quando existente (título, URL, fonte, texto, media URL, datas, captura). Se não houver snapshot, preservar a **referência legada irresolvida** e informar quantos dependem do banco de conteúdo. Se houver evidência íntegra nesse banco, a recuperação pode enriquecer o registro; nunca reconstruir título/URL por heurística.

**V4 — Identidade de salvos separada.** Manter chave estável composta pela origem legada, lista e `item_id`; o bookmark V1 é um artigo salvo, não uma ocorrência `PublicationCardID`. Não criar ou modificar `published_cards`, `feed_editions`, `feed_segments`, âncoras, bookmarks V2 existentes ou histórico editorial para acomodá-lo. Não fundir distintos artigos por URL/título aproximado.

**V5 — Recuperação acessível.** A caixa e a lista de Salvos devem exibir os registros V1 recuperáveis e seus snapshots offline, distinguíveis dos cards V2; ao abrir, mostrar o conteúdo guardado e oferecer URL original quando válida. Itens sem snapshot/conteúdo não podem simplesmente desaparecer: mostrar registro identificado como legado indisponível e opção de informação/recuperação, sem alegar que o artigo está disponível.

**V6 — Coleções e fontes sem chave órfã.** Para cada membro da V1, ler `source_identity` onde existir e preservar separadamente `source_url`, título, media e ordem como proveniência. Para layouts antigos que não tenham `source_identity`, derivar identidade com a função canônica de domínio e registrar a origem; não gravar `source_url` como chave V2. Resolver aliases apenas com as provas aceitas pelo P0D; entradas sem equivalência permanecem preservadas, não descartadas nem reassociadas arbitrariamente.

**V7 — Seleções e desabilitações.** Importar o estado efetivo de `toggleDisabled`, `toggleEnabledOverrides`, e flags de fontes pessoais. Chaves de categoria/região têm semântica de hierarquia V1: não tratá-las como URLs. Materializar na seleção V2 somente fontes e escolhas com equivalência demonstrável; preservar as outras preferências como legado recuperável e explicar divergências. Não substituir a intenção pessoal por seleção default silenciosamente.

**V8 — Presets e informação não conversível.** Preservar nomes, ordens e definições originais de smart feeds, curated feeds e escopos não mapeados, mesmo que um preset V2 equivalente não seja possível. O importador existente pode continuar criando equivalências comprovadas, mas não marcar os campos perdidos como migrados.

**V9 — Operações e histórico.** Inventariar `user_operation` por estado (`pending`, `applied`, `failed`), `source_history_access`, playback e demais preferências pessoais reais. Preservar os valores necessários à recuperação e informar explicitamente o que não consegue ser executado no runtime V2. **Não reexecutar cegamente** operações pendentes, pois `bookmark_item` pode já refletir a intenção; não duplicar nem inverter toggles.

**V10 — Transação, idempotência e retomada.** Com inventário validado, aplicar importação pessoal e marcador/recibo de origem numa transação V2. Reexecutar não duplica caixas, membros, fontes, salvos nem muda preferências V2 já modificadas pelo leitor. Falha intermediária não grava marcador de sucesso nem deixa biblioteca parcial. Se um lote transacional precisar ser limitado, só permitir protocolo explicitamente recuperável e testado, sem estados paralelos em memória.

**V11 — Preexistência na V2.** Se o leitor já tiver dados V2, acrescentar sem sobrescrever, renumerar IDs, alterar seleções posteriores ou apagar coleções. Colisões/ambiguidade são reportadas e ficam recuperáveis; preferência V2 explícita posterior prevalece sem destruir prova V1.

**V12 — Upgrade real e falha visível.** Migração ocorre no upgrade verdadeiro, no mesmo contêiner, offline e sem exigir gestos artificiais; erro não é traduzido em sucesso nem em biblioteca vazia/default. O leitor deve ter indicação verificável do estado e acesso aos dados importados. A migração não pode bloquear indefinidamente o primeiro quadro do feed por trabalho remoto; não há rede necessária.

## 4. Sequência de implementação (minimizar arquitetura)

**Etapa A — prova de origem e inventário antes de escrever.** Confirmar bundle ID e container real de ambas as versões; identificar `user.sqlite`, WAL, banco de conteúdo, JSON legado e `UserDefaults` da V1. Validar schema por introspecção. O detector de V1 não deve depender da existência de linhas em coleções: uma instalação sem coleções também deve migrar. Produzir contagens e fingerprints por categoria antes de modificar a V2. **Não confundir o reconhecimento de schema válido com a presença de linhas de usuário**; a V1 cria `source_collection` mesmo com zero coleções.

**Etapa B — importador determinístico e persistência.** Estender `LegacyUserStateReader` e `LegacyUserStateImport`; usar `RuntimeMigrations` **só aditivamente**, sem reescrever migrações antigas. Reutilizar `ReaderLibraryStore` como owner transacional. Uma representação durável tipada dos bookmarks legados é justificada porque `reader_bookmark_memberships` exige IDs de cards publicados. Para dados residuais não representáveis, usar representação durável mínima com proveniência e status, no mesmo DB; não criar duas autoridades concorrentes. Não adicionar tabelas desnecessárias só para refletir toda a V1.

**Etapa C — superfície de recuperação mínima.** Integrar salvos V1 às caixas existentes, contagens e visualização offline. Evitar reimplementar leitor/feed ou fabricar publicação. Distinguir no modelo de UI referência `.published` de referência `.legacy` e abrir cada qual pelo seu owner. Nunca construir `PublicationCardID` sintético.

**Etapa D — acionamento/retomada.** Integrar ao owner de lançamento da V2 somente depois de consolidar leitura/transação; registrar relatório durável de migrado, recuperável, irresolvido e falha. O marcador só é gravado na mesma transação do destino, não após tentativa parcial.

**Etapa E — ensaio real de upgrade.** Instalar V1 com dados conhecidos em simulador e instalar V2 **sobre o mesmo app**, preservando contêiner. Medir antes e depois; reabrir offline; repetir o início para verificar idempotência; provocar falha de injeção de escrita e retomar. `swift test` sozinho não certifica upgrade.

**Orçamento arquitetural, vinculante:** é proibido introduzir scheduler, timer, retry periódico, fila, cache ou banco paralelo de migração; evitar estado de coordenação redundante, dual-write e segunda normalização de URLs. Usar os owners V2 existentes e `FeedAddress.identity`/`FeedAddress.request`, reconciliados com P0D. O mecanismo deve ser execução local e determinística, sem HTTP público, sem exigir reconstrução do feed e sem inserir registros falsos em publicação. Não alterar `PD-4`/`PD-5`, `PublicationStore`, histórico publicado ou testes para esconder perda. Preferir menos tabelas e um recibo transacional mínimo ao espelhamento integral do schema V1.

## 5. Allowlist inicial — **somente V2** (18 caminhos)

**Produção (11)**
1. `Sources/FeedMinePersistence/LegacyUserStateReader.swift`
2. `Sources/FeedMinePersistence/ReaderLibraryStore.swift`
3. `Sources/FeedMinePersistence/RuntimeMigrations.swift`
4. `Sources/FeedMineComposition/LegacyUserStateImport.swift`
5. `Sources/FeedMineComposition/ReaderLibraryCoordinator.swift`
6. `Sources/FeedMineComposition/ReaderBookmarkBoxesBackend.swift`
7. `Sources/FeedMineDomain/ReaderLibrary.swift`
8. `Sources/FeedMineUI/FeedSavedListView.swift`
9. `FeedMineApp/FeedMineApp/AppComposition.swift`
10. `FeedMineApp/FeedMineApp/FeedMineApp.swift`
11. `Sources/FeedMinePersistence/ReaderPreferencesStore.swift`

**Testes (6)**
12. `Tests/FeedMineCompositionTests/LegacyUserStateImportTests.swift`
13. `Tests/FeedMinePersistenceTests/ReaderLibraryStoreTests.swift`
14. `Tests/FeedMinePersistenceTests/RuntimeMigrationTests.swift`
15. `Tests/FeedMineCompositionTests/BookmarkBoxesBackendTests.swift`
16. `FeedMineApp/FeedMineAppTests/CompositionTests.swift`
17. `Tests/FeedMinePersistenceTests/ReaderPreferencesStoreTests.swift`

**Evidência (1)**
18. `docs/reviews/MIG-V1V2-B_PERSONAL_MIGRATION_EVIDENCE.md` (novo)

**Arquivos e áreas PROTEGIDOS — separados da allowlist; NÃO editar:**

- `bench/**` — oráculos, drivers, corpus, hashes e campanhas existentes.
- `Tests/FeedMinePersistenceTests/AvailabilityPrecedenceTests.swift` e `Tests/FeedMinePersistenceTests/PublicationRunwayStoreTests.swift` — guardas históricas de migração/schema. Se uma migração aditiva produzir uma falha de snapshot, apresentar o delta e pedir extensão ANTES de atualizar expectativas; não afrouxar comparações exatas.
- `Sources/FeedMineComposition/SourceManagementCoordinator.swift` e `Sources/FeedMineComposition/ReaderSourceIdentity.swift` — contratos P0B/P0D de seleção/identidade, não reescrever.
- `Sources/FeedMineComposition/ReaderDiscoveryPool.swift` — boundary de descoberta preservado no P0D.
- `Sources/FeedMinePersistence/PublicationStore.swift` — história publicada e integridade das ocorrências.
- `Sources/FeedMineRuntime/**`, `Sources/FeedMineAcquisition/**`, `Sources/FeedMineEditorial/**` — runway, aquisição e editorial existentes.
- `Sources/FeedMinePersistence/CatalogInstallation.swift` e demais instaladores/ferramentas do catálogo público.
- `FeedMineApp/FeedMineApp.xcodeproj/**`, `Package.swift`, `.github/**`, projetos e entitlements de assinatura.
- Todo o repositório `wsmontes/feedmine-dev/**` (V1 somente leitura) e quaisquer dados reais desse aplicativo.
- Qualquer outro caminho não incluído entre os 18 da allowlist, inclusive distribuição e TestFlight.

**Protocolo de fronteira:** qualquer necessidade de editar um arquivo protegido ou fora da allowlist deve vir acompanhada de evidência e autorização do arquiteto **antes** da edição. A allowlist é um teto, não obrigação de tocar todos os arquivos. Um override de configuração via argumento de `xcodebuild` no Mac, sem alteração do projeto versionado, não amplia o escopo do implementador.

**Risco de integração:** os owners `AppComposition`, `ReaderLibraryStore`, `RuntimeMigrations` e a política de identidade devem ser reconciliados contra o P0D integrado na base congelada; preservar todos os testes e contratos P0B/P0D. **Nenhuma alteração a `ReaderSourceIdentity.swift` ou `ReaderDiscoveryPool.swift` por conta própria**: o primeiro pertence ao P0D, o segundo permanece fora da allowlist.

## 6. Provas mínimas (T01–T16)

- **T01 — Detector real:** V1 com banco válido mas zero coleções reconhecido; banco alheio rejeitado sem escrita.
- **T02 — URL não canônica:** coleção V1 com `source_identity != source_url` (`http`, `www`, query); identidade correta e URL de fetch preservada separadamente.
- **T03 — Aliases conflitantes:** um para vários, vários para um e alias sem prova não provoca união nem perda.
- **T04 — Salvo com snapshot:** permanece na sua caixa, título/texto/URL/metadata reproduzidos e aberto offline mesmo sem conteúdo na base V1.
- **T05 — Salvo sem snapshot:** vínculo exato preservado e contado como irresolvido, sem card fictício.
- **T06 — Duas caixas, mesmo item:** identidade de pertencimento por caixa preservada; sem duplicata por repetição de importação.
- **T07 — Default e ordem:** default V1 mapeado sem criar segundo default; demais listas, coleções e ordem preservadas ou discrepância explicitamente inventariada.
- **T08 — Imported_source:** chave pessoal, request_url, título, `enabled`, inclusive sem correspondência no catálogo V2.
- **T09 — Seleção:** `UserDefaults` disable/override de URL, categoria e região; distinguir seleção vazia explícita de ausência de preferência; não sobrescrever preferência V2 posterior.
- **T10 — Presets:** smart feed conversível e curated feed não conversível ambos permanecem acessíveis, com perda de capacidade explicitamente distinguida.
- **T11 — Pendências:** `user_operation` em `pending` com `bookmark_item` já presente; não aplicar duas vezes nem inverter toggle.
- **T12 — Falha transacional:** escrita recusada sem marcador e sem estado parcialmente importado; reabertura permite retomada.
- **T13 — Idempotência:** executar importação duas vezes e comparar contagens/IDs/hashes, posições e seleção versionada.
- **T14 — Respeito a V2 pré-existente:** importar depois de criar salvos/fontes/coleções no V2 sem apagá-los e sem retroativamente alterar `published_cards` ou âncoras.
- **T15 — Upgrade no simulador:** V1 preenchida → instalação real da V2 sobre mesmo bundle/container → inventário reconciliado; relançamento offline e acesso ao snapshot.
- **T16 — Ausência de V1:** primeiro uso da V2 não cria dados pessoais legados artificiais nem altera onboarding/seleção por ausência.

## 7. Medições obrigatórias no Mac

Antes/depois, registrar valores, hashes ou contagens que possam ser reconciliados sem expor dados pessoais reais:

- **M1:** contagem de membros V1 onde `source_identity != source_url` (se coluna disponível), por schema/revisão; provar a diferença efetiva nas fixtures.
- **M2:** quantidade de `(list_id,item_id)` com e sem `bookmark_snapshot` e quantos foram renderizáveis na V2.
- **M3:** `user_operation` por estado e discrepâncias entre journal e `bookmark_item`.
- **M4:** `source_history_access` e demais estados sem contraparte ativa, distinguindo preservação de funcionalidade restaurada.
- **M5:** estados de seleção em `UserDefaults` (`toggleDisabled`, `toggleEnabledOverrides`), entradas `imported_source` e seu flag `enabled`; contagem resolvida e irresolvida.
- **M6:** inventário final: migrados com funcionalidade V2, preservados em legado recuperável, irresolvidos, incompatíveis e falhas, por tipo.
- **M7:** contagens e identidade de caixas, coleções, presets e membros antes/depois, duplicação zero.
- **M8:** verificação de que V1 `user.sqlite`/WAL e demais entradas não foram modificados; a autoridade V2 apenas recebeu inserções/estado pessoal esperado.

A confirmação de `swift build`, `swift test`, `CompositionTests` e `git diff --check` é necessária, mas insuficiente. Se não houver espaço seguro para o ensaio de upgrade, marcar `BLOCKED — DISK`, não simular o teste com um banco vazio nem anunciar PASS.

## 8. Contrato de entrega e certificação

Entregar: SHA, base e tree; diff/allowlist; provas T01–T16; inventário M1–M8; resumo do que foi preservado com funcionalidade e do que só é recuperável; logs de upgrade real; vulnerabilidades residuais e arquivos:linhas. Não rotular `ATENDE` nenhum teste não executado. A aprovação desta **spec** não é aceite de implementação.

**Gate de release:** proibido chamar a atualização V1→V2 de transparente ou certificada enquanto o ensaio real de upgrade, recuperação offline de salvos, seleção pessoal e repetição idempotente não passarem. A publicação geral segue `NÃO CERTIFICADA` independentemente de os gates P0A–P0D estarem verdes; B03 e B06 são bloqueios independentes.

## 9. Fixture Mac de upgrade real — OWNER EXCLUSIVO: executor Mac

**Autorização de preparação, já concedida:** o executor Mac pode criar e registrar a fixture **agora, em paralelo ao implementador MIG-V1V2-B**, porque o P0D já está integrado. A fixture é externa ao repositório (em diretório temporário documentado) e não modifica os HEADs V1/V2, `bench/`, esquemas ou testes de produto. Não rodar builds pesados simultaneamente com a validação nativa do implementador; usar **simulador dedicado** à migração, não o de bancada do G-18F. A execução de upgrade contra a V2 candidata fica condicionada à implementação e à liberação do simulador.

### 9.1 Identidade do aplicativo: pré-condição bloqueante

- Conferido nos projetos: `feedmine-dev@712a6ba9` usa `PRODUCT_BUNDLE_IDENTIFIER = com.feedmine.app`. `feedmine_v2@dee94e2e` usa **`com.feedmine.development` em Debug** e **`com.feedmine.app` em Release**. Mesmo simulador com bundles diferentes **NÃO** é upgrade: são aplicativos/contêineres distintos.
- Preparar o ensaio com **o mesmo CFBundleIdentifier real `com.feedmine.app`** nos dois binários, por configuração de build/teste (por exemplo, override do build setting de Debug na V2, se tecnicamente viável), **sem editar o `.pbxproj`**. Não inferir a identidade do nome do app ou da pasta. Capturar `CFBundleIdentifier` de ambos os `.app`, `xcrun simctl get_app_container <UDID> com.feedmine.app data` antes/depois e demonstrar **mesmo contêiner de dados**.
- **Instalar V1, lançar para aplicar suas migrações e seed local, terminar V1, inventariar, instalar V2 por cima sem `uninstall`, sem `erase`, sem troca de bundle ID, sem reset de `UserDefaults` e sem apagar SQLite/WAL.** Se a V2 não puder ser instalada por cima em segurança, registrar `BLOCKED — UPGRADE PATH` e não chamar duas instalações independentes de upgrade.
- O `IPHONEOS_DEPLOYMENT_TARGET = 18.0` e o uso de Swift 6 nos projetos tornam o teste plausível no SDK iOS 26.5, mas **a efetiva compilação/instalação V1 ainda deve ser medida**, não presumida. Não alterar a V1 para fazê-la passar.

### 9.2 Inventário sintético mínimo a plantar na V1

Sem HTTP público, sem credenciais reais; URLs de `.example` e títulos determinísticos. Seed no storage real da V1 **após seu primeiro launch**, com o processo encerrado e respeitando SQLite/WAL/`UserDefaults`, ou preferencialmente por APIs V1 já existentes quando possível. Atribuir identificadores, timestamps e ordens fixos e capturar inventário antes de instalar V2. Dados obrigatórios:

| Categoria | Fixture mínima e verificação esperada |
|---|---|
| Caixas e itens | Default `Favorites` + `Longreads` + `Projetos`; ao menos 4 memberships em `bookmark_item`, incluindo **mesmo item em duas caixas**, dois itens distintos e timestamps/ordens diferentes |
| Snapshots | Pelo menos **2 bookmarks com** `bookmark_snapshot` completo (título, URL original, source_title, source_url, excerpt, media_url, authored_at, captured_at); um deles **sem** linha correspondente no banco de conteúdo; pelo menos **1 bookmark sem snapshot**, que fica irresolvido porém **não perdido** |
| Coleções | `Ciência` com ao menos 2 membros, um `source_identity` canônico de `http://www.news.example/feed/?utm_source=fixture&token=fixture` e a URL de fetch íntegra e distinta; incluir fonte cujo parâmetro de query **identifique** de verdade o feed e não deva ser descartado. M1 ≥ 1; testar também instalação sem coleções preenchidas, em fixture separada |
| Fontes do leitor | `imported_source` com **uma habilitada e outra desabilitada**, chaves estáveis, endpoints e títulos; não presumir que só o catálogo embarcado exista |
| Seleção | `UserDefaults` com `toggleDisabled` e `toggleEnabledOverrides`: uma fonte `url:`, uma categoria `cat:`, uma região `region:` e um override explícito que vence pai desabilitado; fixture complementar para **seleção vazia explícita** versus ausência de escolha |
| Presets | Smart feed com termos e filtros representáveis, smart feed com escopo de coleção não transportável, ao menos um `curated_feed` com definição/receita original |
| Operações | `user_operation`: uma `pending` cuja ação de salvar já está materializada em `bookmark_item`, uma `applied`, uma `failed`; IDs únicos e payloads coerentes |
| Histórico e posição | `source_history_access` com 2 URLs/tempos conhecidos no banco V1 em que realmente reside; `lastPodcastItemID`/`lastPodcastPosition` em `UserDefaults` se aplicáveis; representar ausência separadamente |
| Controle negativo | Um contêiner limpo V2 sem V1 e um V1 válido com zero coleções; nenhum deve resultar em perda ou falsa migração |

Os exemplos são **âncoras de fixture**, não licença para inventar campos ausentes ou ignorar variantes históricas. Confirmar `PRAGMA table_info`, existência de tabelas/colunas e regras reais antes do seed. Se `source_identity` ou `bookmark_snapshot` não existirem em versões históricas, testar tratamento versionado, não impor o schema mais novo a todos.

### 9.3 Evidência e decisão da fixture

**Preparação independente (agora, owner executor Mac):** logs dos dois builds, versões/configurações, UDID, bundle IDs, caminhos de contêiner, descrição do seed, inventário V1 com M1–M5, hash ou contagem por chave lógica e comandos de reprodução; `fixture-readiness = READY | BLOCKED` com motivo. Salvar em `/tmp/` do Mac e fornecer um manifesto copiável para o relatório versionado do gate; **não** colocar um banco com dados reais no Git.

**Ensaio após implementação:** V1 instalada e seeded → app encerrado → inventário → **install V2 no mesmo bundle** → lançamento/ativação de migração → inventário V2 M1–M8 → matar/reabrir offline → conferir salvos e seleção na UI → nova abertura e comparação idempotente. A matriz deve reconciliar cada registro de origem a um estado `convertido`, `preservado-recuperável`, `preservado-irresolvido` ou `falhou`; não esconder perdas nos agregados. Registros **não importados nem recuperáveis** causam `FAIL`, mesmo quando `swift test` está verde.

Comandos indicativos (ajustar `-destination`/UDID, configuração, assinaturas e caminhos sem alterar fonte):

```bash
# Descoberta e verificação da fixture — rodar no Mac, em simulador dedicado
xcodebuild -project feedmine.xcodeproj -scheme feedmine -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$V1_DD" build
# Conferir CFBundleIdentifier do produto antes do install; lançar V1, semear e inventariar.
xcrun simctl get_app_container "$SIM" com.feedmine.app data
# Build de ensaio da V2 com bundle ID IGUAL ao da V1; verificação do produto obrigatória.
xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$V2_DD" \
  PRODUCT_BUNDLE_IDENTIFIER=com.feedmine.app build
# Instalar por cima — nunca desinstalar V1 nem limpar o simulador entre snapshots.
xcrun simctl install "$SIM" "$V2_DD/Build/Products/Debug-iphonesimulator/FeedMine.app"
xcrun simctl get_app_container "$SIM" com.feedmine.app data
```

### 9.4 Execução nativa posterior ao commit

1. `git diff --check dee94e2e HEAD`, `git diff --name-only dee94e2e HEAD`, confirmar base SHA completo, tree, commit único e arquivos protegidos.
2. `swift build`; `swift test --filter LegacyUserStateImportTests`; `swift test --filter ReaderLibraryStoreTests`; `swift test --filter RuntimeMigrationTests`; `swift test` inteiro, todos sem falha não autorizada.
3. `xcodebuild test -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -destination "platform=iOS Simulator,id=$APP_SIM" -parallel-testing-enabled NO -only-testing:FeedMineAppTests/CompositionTests`, na árvore candidata; conferir contratos P0B/P0D e G-18F na política já definida.
4. Ensaio real do §9.3 no **mesmo contêiner**, sem HTTP externo; capturar inventário, UI, offline, idempotência e falha de importação/retomada.
5. Evidência em `docs/reviews/MIG-V1V2-B_PERSONAL_MIGRATION_EVIDENCE.md`: tabela de T01–T16, M1–M8 e cada comando com `PASS`, `FAIL`, `NOT_RUN` ou `BLOCKED` verídico. Sem `ATENDE` para prova não executada.

**Critério de aceite duplo:** (i) implementação sobre os owners existentes sem regressão de feed/runway/publicação; (ii) upgrade de V1 com dados conhecidos reproduzido no simulador e conciliado por identidade. **Nenhum dos dois substitui o outro**.


## 10. Ordem operacional após PD10-P0D integrado

- **Implementador (chat independente):** abrir `chatgpt/mig-v1v2-b-personal-preservation` **a partir exatamente de** `dee94e2ef251212ad33ecb422433be3d101e63f6`, ler esta spec e os owners V1/V2, implementar apenas na allowlist, publicar **um commit** e deixar a evidência com `NOT_RUN` para tudo que não foi executado. Entregar commit SHA, tree, diff, instruções nativas e pontos de fronteira. Não fazer merge.
- **Executor Mac (paralelo):** usar a seção 9 para construir, sem mudar fontes da V1, uma instalação V1 com dados sintéticos conhecidos; registrar `fixture-readiness`, inventário M1–M5, IDs e hash de origem, bundle id `com.feedmine.app`, mesmo contêiner. Preparar uma fixture negativa separada. Não chamar os testes de upgrade de PASS até receber e instalar a V2 candidata real.
- **Executor Mac (após commit MIG):** rodar seção 9.4 completa, medição M1–M8 e tabela T01–T16, incluindo consulta visual/offline. Resultados nativos são independentes da evidência textual do autor.
- **Arquiteto:** recebe SHA e evidências, audita a conformidade de V1–V12 e cada divergência; **nenhum merge** antes de provar upgrade real e consentimento específico para qualquer alteração fora da allowlist.

**Não é necessário aguardar outra autorização para delegar o implementador e a preparação da fixture.** A autorização presente é de execução do gate, não de aceite ou integração.
