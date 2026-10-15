# Integração do PD10-P0B no `main` — 2026-10-15

Registro de proveniência da integração do candidato PD10-P0B, exigido pelo veredito do arquiteto
("o relatório deve registrar o SHA final, a árvore Git e o resultado de cada verificação").

## 1. Autorização

Veredito de 2026-10-15: **PD10-P0B `40bc9fa1` ACEITO — MERGE TÉCNICO AUTORIZADO**, condicionado à validação da
árvore integrada. A suspensão anterior (investigação do G-18F) foi **revogada** no mesmo veredito, que encerrou o
G-18F como **`NOT_REPRODUCED` na investigação adicional** e **`FLAKY — ROOT CAUSE UNDETERMINED`** no histórico do
produto.

Condições fixadas pelo arquiteto e como cada uma foi cumprida:

|Condição|Cumprimento|
|---|---|
|Preparar o merge em branch temporária derivada do `main`; validar; só então promover|feito: `integration/p0b-into-main` a partir de `4f02efd1`; promoção por `--ff-only` só após as três verificações|
|Escopo: os 15 arquivos do P0B, sem alterações adicionais indevidas|`git diff --name-only <main pré-merge> <merge>` = **exatamente os 15 arquivos do P0B** (conjunto idêntico ao delta próprio do candidato)|
|Histórico: preservar P0C, spec P0D e evidências G-18F|preservados: merge P0C `bb8a94f8`, spec P0D `1dafd144`, evidências G-18F `52e445c5`, `e3493421`, `21b7b271`, `4f02efd1`|
|`git diff --check` zerado (inclusive staged)|vazio (`git diff --check HEAD^1 HEAD`)|
|`swift build` exit 0|**exit 0**|
|`swift test` exit 0, zero falhas|**`Executed 1353 tests, with 1 test skipped and 0 failures`**|
|`CompositionTests` executado por inteiro|**`Executed 60 tests, with 0 failures`** — `** TEST SUCCEEDED **`|
|PD10: os sete testes passam|**7 passed / 0 failed**|
|Política para o app: só o G-18F idêntico seria exceção; outra falha interromperia|**nenhuma falha** — o G-18F passou, a exceção não precisou ser invocada|
|Margem de disco ≥ 1 GB, monitorada|2,8 GB no início da suíte do app e 1,5 GB no fim|

## 2. Grafo e SHAs

```
main pré-merge (base efetivamente usada)          4f02efd1
candidato P0B                                     40bc9fa1
ancestral comum do P0B e do main                  f47a7aab
commit de merge (--no-ff, estratégia ort, 0 conflitos)   3f4f8131
```

Nota de proveniência: o arquiteto conferiu o GitHub em `main = 21b7b271`; entre a conferência e a preparação do
merge, o `main` avançou **um commit exclusivamente documental** (`4f02efd1`, o registro da rodada da
sequência-predecessora do G-18F). A base usada para preparar o merge é `4f02efd1`, que era o `origin/main` no
momento da preparação — a condição de publicação ("origin/main == base usada") está satisfeita, e a divergência
fica declarada aqui em vez de implícita.

## 3. Verificações executadas (árvore do merge `3f4f8131`)

|Verificação|Comando|Resultado|Log|
|---|---|---|---|
|Escopo|`git diff --name-only 4f02efd1 HEAD`|15 arquivos (os do P0B)|—|
|Conflitos|`git merge --no-ff 40bc9fa1`|`Merge made by the 'ort' strategy`, 0 conflitos|—|
|Integridade|`git diff --check HEAD^1 HEAD`|vazio|—|
|Build|`swift build`|exit 0|`/tmp/p0b-merge-build.log`|
|Pacote|`swift test`|`Executed 1353 tests, with 1 test skipped and 0 failures`|`/tmp/p0b-merge-test.log`|
|App|`xcodebuild test … -only-testing:FeedMineAppTests/CompositionTests`|`Executed 60 tests, with 0 failures`, PD10 7/7, G-18F passed, `** TEST SUCCEEDED **`|`/tmp/p0b-merge-composition.log`|

Ambiente: macOS arm64, Xcode 26.6, simulador dedicado de bancada `FeedMine Bench (16DA3DB5-C9E0-4190-AF2F-AFAADC7EB7AE)`,
`-parallel-testing-enabled NO`.

## 4. Higiene de disco (transparência)

A validação foi preparada com margem acima de 1 GB, sem reduzir critérios. Para mantê-la: o `.build` do pacote
(993 MB) foi removido **depois** de a validação `swift build`/`swift test` estar registrada em log (é cache, não
evidência), e o derived data do app (`/tmp/p0b-merge-dd`, 1,1 GB) foi removido **depois** da suíte. Nenhuma etapa
falhou por espaço e nenhum log de veredito foi descartado.

## 5. Promoção

`main` avança por `git merge --ff-only integration/p0b-into-main`, publicando o commit de merge já validado mais
este registro. **Nenhuma alteração de código** foi feita durante as verificações; a árvore validada é a árvore
publicada.
