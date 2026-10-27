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
