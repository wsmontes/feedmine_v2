# MIG-V1V2-B — evidência de implementação (não é certificação)

**Data:** 2026-10-15. **Base efetiva e autorizada:** `801f017dd3a65c19e47ae101f4a95de02457458c` (substitui a base textual da spec através da autorização posterior do arquiteto). **Branch:** `chatgpt/mig-v1v2-b-personal-preservation`. **V1 apenas leitura:** `wsmontes/feedmine-dev@712a6ba9`. **Integração:** nenhuma. **Gate upgrade:** **BLOCK / NÃO CERTIFICADO**.

Este arquivo registra código proposto e procedimentos de prova; **não afirma PASS sem execução**. O conector GitHub permitiu inspeção e publicação de objetos. Não houve ambiente Mac/iOS, simulador, fixture nativa ou checkout compilável nesta sessão.

## Contrato de migração e fronteira

- `RuntimeMigrations`: migração aditiva final `reader-legacy-personal-v1`, sem alterar DDL anterior; o conteúdo durável vai para `runtime.sqlite`.
- `LegacyUserStateReader`: reconhecimento de schema, leitura SQLite readonly consistente, preservação de `bookmark_item` mesmo sem snapshot, proveniência raw de coleções, smart/curated, fontes importadas, journal e `source_history_access` quando presente; `UserDefaults` whitelisted arquivados como binary-plist em JSON.
- `ReaderLibraryStore`: bookmarks na PK V1 `(legacy_list_id,item_id)`, arquivo de registros com origem, recibo SHA-256, fontes/caixas/coleções e preferências iniciais em **uma transação V2**. Colisões em registros pessoais provocam rollback e sem recibo; replay com mesmo recibo não reinsere. Um V2 preexistente tem precedência. Nenhum `PublicationCardID` é fabricado.
- `FeedSavedListView` e host: lista salvos V2 mais snapshots V1 discriminados, abertura offline do texto/metadados locais, URL externa apenas com http(s) válido; referência sem snapshot explícita. Caixas exibem contagem V1+V2. A ausência de artigo em `published_cards` não significa ausência do bookmark V1.
- `AppComposition`: lançamento real no diretório padrão procura `Application Support/Feedmine/user.sqlite` ou `Documents/user.sqlite`, recusa origens simultâneas ou schema inválido, executa a transação antes de inicializar seleção; preferências V2 anteriores não são alteradas; recibo evita reimportações. Falhas passam ao diagnóstico e mensagem de startup, não são transformadas em sucesso.
- Seleção: escolha inicial V2 pode excluir apenas `url:` explicitamente desativada com identidade comprovadamente canônica e `imported_source.enabled = false` correspondente. `cat:` e `region:` são **preservados no arquivo, não reexecutados** sem prova de equivalência taxonômica. Overrides de fonte e grupos ficam recuperáveis; não há garantia de equivalência comportamental completa à seleção efetiva V1.
- Smart feed com escopo `sourceCollectionID` incompatível não é instalado sob escopo ampliado. Smart/curated não convertíveis, operações `pending/applied/failed`, histórico e playback são **preservados como arquivo recuperável**, não executáveis automaticamente no V2. Falta de snapshot não é preenchida por heurística a partir do banco de conteúdo.

## Extensão da allowlist autorizada (18 → 19)

Autorização específica do arquiteto: **somente** `Tests/FeedMinePersistenceTests/PublicationRunwayStoreTests.swift`, em 244–247 (identificador ordenado de migração) e 435–456 (objetos novos em conjuntos exatos). Continuam as duas asserções `XCTAssertEqual` e os dois conjuntos de diferença completos. Nada é excluído do inventário; nenhuma asserção foi reduzida para `contains`, subconjunto ou contagem aproximada. `AvailabilityPrecedenceTests.swift` e os demais protegidos seguem intocados.

**Objetos novos esperados, derivados do DDL da migração**, enumerados literalmente no novo `legacyObjects`:

| Objeto | Forma autorizada |
|---|---|
| `reader_legacy_bookmarks` | `CREATE TABLE` com PK composta `(legacy_list_id,item_id)`, FK `list_id`, `status` snapshot/unresolved |
| `sqlite_autoindex_reader_legacy_bookmarks_1` | autoíndice da PK composta |
| `reader_legacy_bookmarks_list_order` | `CREATE INDEX` sobre `(list_id, added_at DESC, sort_order, item_id)` |
| `reader_legacy_records` | `CREATE TABLE` com PK `(category,legacy_key)` e status recoverable/unresolved |
| `sqlite_autoindex_reader_legacy_records_1` | autoíndice da PK composta |
| `reader_legacy_receipt` | `CREATE TABLE` com `origin TEXT PRIMARY KEY`, fingerprint, totais e data |
| `sqlite_autoindex_reader_legacy_receipt_1` | autoíndice da PK TEXT |

**Não há triggers, views nem outras tabelas/índices intencionais.** Qualquer objeto extra permanece uma falha no teste de diferença exata. As definições completas constam da asserção do teste, não foram extraídas de um banco observado.

## Inventário de provas T01–T16

Nenhuma execução nativa foi realizada. Os testes XCTest escritos/alterados são **candidatos**, não resultados.

| Prova | Estado | Nota de implementação / lacuna |
|---|---|---|
| T01 detector real | NOT_RUN | detecta schema sem exigir linhas de coleção; falta prova zero-coleções no Mac |
| T02 identidade vs. URL | NOT_RUN | mantém colunas separadas em arquivo, converte `source_identity` quando presente |
| T03 alias conflitante | NOT_RUN | nenhuma heurística de aliases, P0D não alterado |
| T04 salvo com snapshot | NOT_RUN | armazenamento tipado e abertura offline; teste de fixture local escrito |
| T05 salvo sem snapshot | NOT_RUN | PK e status unresolved, sem publicação |
| T06 mesmo item duas caixas | NOT_RUN | PK inclui `legacy_list_id`; fixture Mac ainda exigida |
| T07 default/ordem | NOT_RUN | default mapeado a `saved`; `sort_order` preservado |
| T08 `imported_source` | NOT_RUN | request URL e identidade tipados; flag original no arquivo |
| T09 seleção/overrides | NOT_RUN | URL own-off inicial tratado; grupos não materializados sem prova |
| T10 presets | NOT_RUN | conversíveis instalados, demais JSON íntegro arquivado |
| T11 pending/applied/failed | NOT_RUN | journal arquivado, não reexecutado |
| T12 rollback/retomada | NOT_RUN | caso XCTest de colisão em PK inserido |
| T13 idempotência | NOT_RUN | recibo e replay no XCTest, comparar hashes no Mac |
| T14 V2 pré-existente | NOT_RUN | preferência não sobrescrita, P0D protegido |
| T15 upgrade mesmo container | NOT_RUN | condição bloqueante de certificação |
| T16 V2 limpa sem V1 | NOT_RUN | branch de origem ausente não importa; falta prova nativa |

## Medições M1–M8

| Medição | Estado | Dado pendente do Mac |
|---|---|---|
| M1 identity != URL | NOT_RUN | contagem V1 e reconciliação |
| M2 bookmarks com/sem snapshot | NOT_RUN | antes/depois, renderizáveis, unresolved |
| M3 journal por estado | NOT_RUN | pending/applied/failed, sem execução duplicada |
| M4 histórico/playback | NOT_RUN | recorte V1, arquivo durável e perda operacional |
| M5 seleção/imported sources | NOT_RUN | disable, override, cat/region e identidades comprovadas |
| M6 inventário final | NOT_RUN | convertido / recuperável / irresolvido / falhou |
| M7 ids/posições/duplicações | NOT_RUN | antes/depois, replay, edições V2 |
| M8 V1 intacta | NOT_RUN | hashes DB/WAL/SHM/Defaults antes e depois |

## Comandos obrigatórios do executor Mac

Todos os comandos abaixo: **NOT_RUN** nesta sessão.

```bash
git fetch origin
git switch chatgpt/mig-v1v2-b-personal-preservation
git rev-parse HEAD HEAD^{tree} HEAD^
git diff --name-only 801f017dd3a65c19e47ae101f4a95de02457458c HEAD
git diff --check 801f017dd3a65c19e47ae101f4a95de02457458c HEAD
swift build
swift test --filter LegacyUserStateImportTests
swift test --filter ReaderLibraryStoreTests
swift test --filter RuntimeMigrationTests
swift test --filter ReaderPreferencesStoreTests
swift test --filter PublicationRunwayStoreTests
swift test
xcodebuild test -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine \
  -destination "platform=iOS Simulator,id=$APP_SIM" -parallel-testing-enabled NO \
  -only-testing:FeedMineAppTests/CompositionTests
```

**Mac: upgrade real (§9 da spec):** usar simulador dedicado, V1 Debug com bundle `com.feedmine.app`; confirmar `CFBundleIdentifier`; plantar fixture sintética e capturar M1–M5, `simctl get_app_container`; instalar V2 sobre V1 com `PRODUCT_BUNDLE_IDENTIFIER=com.feedmine.app` por override **sem editar pbxproj**, sem uninstall/erase/reset; comparar mesmo container e M1–M8; reabrir offline e verificar snapshot, caixas, coleção, seleção e segundo launch; simular falha de transação e retomar. Não confundir duas instalações independentes com upgrade.

## Diagnóstico da primeira rodada nativa e correção candidata (relato do executor Mac)

O executor Mac informou resultados reais da árvore anterior `2f90dd68a69eb33dd9c09555d70711f8bbff4574`. Eles **não são execuções desta sessão** e **não certificam o amend**:

| Comando / filtro | Resultado informado para 2f90dd68 |
|---|---|
| `swift build` | **PASS**, exit 0, 87,90 segundos |
| `LegacyUserStateImportTests` | **FAIL**, 7 testes, 1 falha |
| `ReaderLibraryStoreTests` | **PASS**, 12/0 |
| `RuntimeMigrationTests` | **PASS**, 2/0 |
| `PublicationRunwayStoreTests` | **PASS**, 12/0 |

**Falha literal:** `LegacyUserStateImportTests.swift:165`, `testImportRetainsUnresolvedItemsAndSurvivesOfflineDatabaseReopen`: `XCTAssertEqual failed: ("0") is not equal to ("2")`.

**Causa verificada por inspeção de fonte, não por acomodação de expectativa:** em `LegacyUserStateReader.personalState()`, a projeção do `LEFT JOIN bookmark_snapshot` definia `1 AS has_snapshot` mesmo quando `s.item_id` não existia. A fixture contém **3 linhas de `bookmark_item` e 1 linha de `bookmark_snapshot`**: portanto, por contrato de presença da PK V1, são precisamente **1 snapshot e 2 referências irresolvidas**. O teste já demonstrava 3 registros preservados; a classificação incorreta afetava `reader_legacy_bookmarks.status` e o recibo, incluindo a interface de recuperação.

**Correção proposta neste amend:** projetar `CASE WHEN s.item_id IS NOT NULL THEN 1 ELSE 0 END AS has_snapshot` quando existe tabela de snapshots, e manter `0 AS has_snapshot` quando a tabela não existe. Nenhuma tabela/migração ou contrato de id é alterado. O teste **não reduz o esperado de 2**: verifica contagem do inventário de origem, as 3 linhas reabertas, a partição 1/2, os três valores literais `status` no banco, as caixas, os totais do recibo e zero `published_cards`.

**Estado do commit emendado:** `NOT_RUN` para build, os quatro filtros, pacote completo, suíte do app e upgrade real, até nova validação Mac. O `FAIL` original permanece registrado como evidência histórica; não foi renomeado para PASS.

## Riscos reais, não escondidos

1. **T09 parcial:** taxonomia V1 `cat:`/`region:` e overrides derivados continuam arquivo de recuperação, não seleção V2 plenamente operacional. Provar equivalência requer validação específica; release deve continuar BLOCK enquanto houver perda de intenção de seleção.
2. **Snapshots ausentes:** vínculo preservado, mas conteúdo externo ou exclusivamente no banco V1 não foi recuperado. A UI informa indisponibilidade.
3. **V1 WAL/SHM:** open readonly e consistência precisam ser atestados pelo ensaio real com hashes e transações pendentes.
4. **V1 variantes históricas:** leituras opcionais foram limitadas ao schema conhecido; versões com colunas diferentes exigem inventário e teste, não fallback inventado.
5. **Sem CI nativa aqui:** não existe evidência de compilação, de `PublicationRunwayStoreTests` verde ou de integridade de upgrade. Revisão estática não certifica execução.

**Conclusão:** candidato de implementação submetido à validação nativa; **não é PASS, não é release, não é merge**.
