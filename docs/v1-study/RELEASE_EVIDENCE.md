# Release evidence ledger

O conselheiro pediu isto e a razão dele está certa: as provas deste projeto foram obtidas em condições diferentes ao
longo de semanas, e nada respondia à pergunta que importa no fim — **a candidata atual satisfaz todos os contratos?**

Este arquivo é o registro. Ele é atualizado por gate, não reescrito: cada linha diz *sobre o que* a medida foi feita, e
uma medida cuja candidata não é a corrente **não conta** para o release, mesmo que tenha passado.

## 1. A identidade da candidata — e por que o commit não basta

O `bench/run.sh` grava `identity.txt` em cada corrida com `stamp`, `commit`, `dirty: N files` e o `git status` completo.
**Isso não identifica a build sob teste.** Medido em 2026-10-11: `HEAD` era `609ced6d` com **117 arquivos sujos** (57
modificados, 60 novos) — o trabalho inteiro daquele dia, não commitado. Duas corridas com o mesmo `commit` podem ter
medido árvores diferentes, e o `dirty: N` não distingue "N arquivos mudaram" de *quais* bytes.

**A identidade que serve é de conteúdo:**

```
git stash create      # um snapshot de conteúdo da árvore suja; não toca no índice nem no worktree
```

Ele devolve um hash de commit que endereça a árvore inteira. A candidata corrente é o par **`commit` + `tree`**, e é
isso que o ledger registra.

> **Pendência de instrumentação, aberta:** o `bench/run.sh` deve passar a gravar o hash do `git stash create` no
> `identity.txt`. Enquanto não gravar, o ledger cita o hash que eu calculei à mão no momento de lançar a corrida, e uma
> corrida lançada por outro caminho não é atribuível a uma árvore.

## 2. Os gates

`corpus` é o `inputs.sha256` da corrida (catálogo do corpus + itens); `avaliador` é a verificação do `EVALUATOR.sha256`
selado; `resultado` é o veredicto do oráculo.

| corrida | gate | commit | árvore | corpus | avaliador | resultado |
|---|---|---|---|---|---|---|
| `20261011T174133Z` | B05 | — | — | — | ok | **PASS** |
| `20261011T174453Z` | B03 | — | — | — | ok | **FAIL** (1 paralisação, t+343,77 s) |
| `20261011T182906Z` | B05 | — | — | ok | ok | **PASS** |
| `20261011T183318Z` | B05 | — | — | ok | ok | **PASS** |
| `20261011T183632Z` | B03 | 609ced6d | — | ok | ok | **NOT_RUN** (invocação sem `--full-trace`; erro meu) |
| `20261011T183832Z` | B03 | 609ced6d | — | ok | ok | **FAIL** (1 paralisação, t+244,80 s) |

**As corridas anteriores a hoje têm `commit` vazio neste ledger por uma razão honesta: eu não os coletei quando elas
rodaram.** O `identity.txt` delas existe em disco e pode ser lido a qualquer momento; o que não existe é a árvore, que
o runner não gravava e que eu não anotei. Um PASS sem árvore não é um PASS para o release — é um PASS histórico.

## 3. A coerência da candidata, hoje

**As medidas de B05 e B03 que existem foram feitas em árvores anteriores à atual.** Durante o dia de 2026-10-11
entraram, nesta ordem: a ligação do app ao `CatalogInstallation`, o conserto do harness (traço bruto preservado nos dois
modos e injeção do par catálogo+descritor), a oportunidade de atualização no `foreground()`, o compilador de catálogo,
o caminho completo de payload (download → verificação → staging → ativação atômica) e a instrumentação da reposição.

Nenhuma dessas mudanças foi medida por um gate de release. **Portanto: a candidata corrente não tem B05 nem B03
válidos**, e os PASS desta tabela não podem ser apresentados como evidência de release.

O que fazer, e está em curso: remedir B05 e B03 na árvore corrente. B03 exige máquina quieta (ele mede paralisações
≥1 s; um build concorrente fabrica FAIL falso) e cerca de 3 GB livres.

## 4. O que cada gate mede, para o registro não virar números sem significado

| gate | o que ele julga |
|---|---|
| B01, B02 | as superfícies de apresentação contra os capturas da V1 |
| B03 | 30 minutos de avanço sem paralisação visível ≥1 s por falta de runway, sem repetição e sem pares consecutivos da mesma fonte |
| B04 | — |
| B05 | a persistência e a retomada: o app aberto antes e depois, com o transporte bloqueado |
| B06 | o mesmo no aparelho físico, com o coletor de energia e hitches |
| PD-10 | os critérios 2–7 do bootstrap: instalação, recusa, degradado declarado, política de sincronização, atualização |

## 5. O que ainda não tem evidência nenhuma

- **B04** e **B06**: B06 depende do aparelho físico e da permissão de Rede Local, ambas pendências humanas.
- **PD-10 critério 4**: o mecanismo está provado ponta a ponta (`CatalogueUpdateAcceptTests`, árvore local de revisão 6,
  ativação e preservação do store do leitor), mas a `wawasoft/feed-repository` publica a revisão 5, que é a ativa — a
  primeira atualização real depende de a autoridade publicar uma revisão 6.
- **A transição de filtro de 95 s**: bloqueador de release declarado pelo arquiteto e ainda aberto.
