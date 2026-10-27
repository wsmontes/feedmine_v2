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
