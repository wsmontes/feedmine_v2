# Integração do PD10-P0D no `main` — 2026-10-15

Registro de proveniência da integração do gate PD10-P0D, com o SHA publicado, os resultados nativos e a
história do bloqueio que reteve o primeiro aceite.

## 1. Veredito

**PD10-P0D — ACEITE DEFINITIVO. APROVADO PARA INTEGRAÇÃO** por `--ff-only`, com a guarda
`origin/main == 9f93bc29`. O veredito registra explicitamente:

| Critério | Veredito do arquiteto |
|---|---|
| Base `9f93bc29` | confirmada |
| Candidato `c8c1b508` | 1 commit à frente, sem divergência |
| Allowlist | 13 arquivos autorizados |
| Arquivos protegidos | nenhuma alteração |
| D1 — seleção durável no startup | ACEITO |
| D1 — toggle preserva fontes indisponíveis | ACEITO |
| D2–D10 — continuidade de identidade | ACEITOS nos limites documentados |
| Migrações e guardas de schema | ACEITAS |
| `swift build` / `swift test` / `CompositionTests` / G-18F | PASS |

## 2. Grafo e SHAs

```
base (main antes)                                9f93bc29
candidato (um commit sobre a base)               c8c1b508
tree do candidato                                c06d06f858a1142f37918de593ed064d3658faf0
merge aplicado                                   --ff-only (sem commit de merge)
main publicado                                   c8c1b508fe7f81acfe532cb83465a7eb00f4ec3f
```

Guarda verificada antes do merge: `origin/main == 9f93bc29`, `main` local == `origin/main`, árvore limpa,
parent do candidato == `9f93bc29`. `HEAD` depois do merge conferido contra o SHA aprovado, caractere a
caractere. Publicado sem force push.

## 3. Verificação nativa (árvore do candidato, que é a árvore publicada)

| Verificação | exit | Resultado |
|---|---|---|
| escopo | 0 | 13 arquivos, **1** commit, protegidos e `bench/` vazios, `git diff --check` vazio |
| `swift build` | 0 | `Build complete` |
| filtros `ReaderLibraryStoreTests` / `ReaderSourceIdentityTests` / `ReaderImportExportCoordinatorTests` / `RuntimeMigrationTests` | 0 | 12/0 · 6/0 · 6/0 · 2/0 |
| filtros `AvailabilityPrecedenceTests` / `PublicationRunwayStoreTests` | 0 | 7/0 · 12/0 |
| `swift test` (pacote) | 0 | `Executed 1357 tests, with 1 test skipped and 0 failures` |
| suíte do app (`CompositionTests`) | 0 | `Executed 63 tests, with 0 failures` — `** TEST SUCCEEDED **`, G-18F `passed` |

## 4. O bloqueio D1: primeiro aceite retido, correção, aceite definitivo

O primeiro veredito sobre `0ced0444` foi **ACEITE RETIDO — MERGE NÃO AUTORIZADO**, por um defeito semântico
encontrado por leitura e **não coberto** pelos 62 testes que passavam naquele commit:

- `AppComposition.toggleSource` gravava a seleção por substituição **absoluta**
  (`preferences.updateSources(next.map(\.principal))`), a partir de um conjunto que contém apenas as fontes
  **operacionalmente resolvidas**;
- consequência: uma chave persistida cuja fonte **desapareceu temporariamente do catálogo** era apagada no
  primeiro toggle de qualquer outra fonte. Sequência determinística: A, B, C persistidos → B indisponível →
  desabilitar A → resultado espúrio `C` em vez de `B, C`.

Correção autorizada e aplicada em `c8c1b508`, dentro da allowlist já aprovada:

1. `toggleSource` passou a usar `ReaderPreferencesStore.changeSources(adding:removing:)` — operação
   **incremental**, que preserva escolhas fora do escopo solicitado (`ReaderPreferencesStore.swift:61-63`
   documenta que a substituição absoluta fica reservada a quem explicitamente a quer);
2. regressão `testPD10P0DDisablingAvailableSourceKeepsMissingSelectionThroughReopen` em
   `CompositionTests.swift`, cobrindo a sequência com **versão de seleção** e **reabertura**;
3. remoção da asserção incidental da última migração em `AvailabilityPrecedenceTests.swift:74`, com as
   guardas exatas de schema de `PublicationRunwayStoreTests.swift` **preservadas**.

Varredura de todos os sítios de escrita absoluta de seleção no repositório, para garantir que o escopo era o
correto:

| Sítio | Natureza | Ação |
|---|---|---|
| `AppComposition.swift:218` `updateSources([])` | `#if DEBUG`, evidência de UI (`FEEDMINE_EMPTY_SELECTION=1`) | intencional, não tocado |
| `AppComposition.swift:227` (na base) | startup/repair | já corrigido pelo P0D (virou `rememberResolvedSources(_:)`) |
| `AppComposition.swift:500` | `toggleSource` | **o defeito** — corrigido em `c8c1b508` |
| `SourceManagementCoordinator.swift:181` `updateSources(keys)` | API wholesale **sem chamador de produção** (o fluxo de UI usa `setSourceEnabled`/`setEnabledTree` → `changeSources`), em arquivo **protegido** | decisão do arquiteto: **não tocar** |

## 5. Nota de método (para não confundir verde com veredito)

A regressão do D1 é um caso do **alvo do app**, não do pacote. O filtro `swift test --filter
testPD10P0DDisablingAvailableSourceKeepsMissingSelectionThroughReopen` devolveu **`Executed 0 tests`** — e o
executor registrou isso explicitamente em vez de contá-lo como verde. O veredito válido é o da suíte do app
(**63/0**, isto é, os 62 anteriores mais o caso novo).

Registrado também o que isso implica: no commit anterior (`0ced0444`), os 62 testes verdes **não mediam** a
sequência do D1. O gate só fechou porque a leitura adversarial apontou o defeito que a suíte não cobria.

## 6. Limites deste aceite

- O P0D preserva escolhas e identidades pessoais **dentro do V2**; quando não há prova suficiente de
  equivalência entre fontes, o comportamento correto é preservar a referência **sem inventar alias**.
- **Isto não certifica a migração V1 → V2**, que permanece no gate independente **MIG-V1V2-B**.
- `B03` (`BLOCKED — DISK`) e `B06` (sem iPhone físico) seguem com os seus próprios bloqueios. A release geral
  continua **não certificada**.
