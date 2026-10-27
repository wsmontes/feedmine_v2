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
