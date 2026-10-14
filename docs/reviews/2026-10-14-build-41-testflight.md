# Build 41 no TestFlight interno (2026-10-14)

## O que foi enviado

`1.0 (41)` = `2e6cda672e559b22670fd5c2e2029d6a73822b0f`, tag anotada
`ios/1.0-build.41-2e6cda67` (empurrada para `origin`). `PAIRING OK` antes da exportação: o SHA
embutido no `Info.plist` do archive confere com `HEAD`, e o archive é de `Release` para
`generic/platform=iOS`, bundle `com.feedmine.app`.

Build anterior no canal: `1.0 (40)`. `CFBundleVersion` foi movido para 41 nesta rodada.

## O que mudou desde a 40

| Commit | O quê |
|---|---|
| `e78b691a` | O deadlock da posição: o modificador de viewport voltou a seguir a janela **segurada** durante o gesto, não a publicada. Reprovação e números no registro do B01. |
| `326bb45c` | Cadência de convites: a **primeira** resposta da sessão volta o próximo intervalo ao primeiro convite (4 cards); da segunda em diante vale o intervalo base (12). |
| `2e6cda67` | Registro do B01 PASS, da causa-raiz e da evidência; `CFBundleVersion` 41. |

## Prova que acompanha este envio

`B01 A+B` **PASS** em `326bb45c` (`bench/run/20261014T071443Z`, corpus e oráculo congelados,
`dirty files: 0`): as cinco cláusulas verdadeiras, 271 fontes no conjunto de aquisição, 40
contribuindo nos primeiros 300 cards, 202 cards publicados, dois assuntos declarados dentro do feed
em cada perfil. Suíte do pacote no mesmo commit: 1.255 testes, 1 skipped, 0 falhas. Reprodutor do
scroll: `TEST SUCCEEDED`, com `activeWrites=0`, `activeWindows=0`, `activeLayoutStep=0` e resíduo
`0.000000`.

## Limites que ficam registrados (revisão independente do QA)

- **`matchesScope` ficou vazio.** Com `presented` de volta à janela segurada, a comparação
  `presentation(for:)?.window == presented.window` é uma tautologia; o que resta protegendo o
  escopo é a identidade do dono (`renderOwner`) e as checagens de contexto/edição/sequência. É a
  semântica que existia antes de `c4edf3bc` e é o que o B01 provou; **não** é uma prova de que todos
  os caminhos de reconciliação continuam cobertos.
- **A evidência passou a provar "estava na janela que eu desenhei".** Com `rendered: presented`, o
  `admittedIDs` de `RenderedViewportEvidence` é a janela desenhada, então `belongs(to:)` não afirma
  mais "está na publicada agora". Mascarado por `keepsAdmittedHead` e coberto explicitamente pelo
  ramo de reconciliação de posição — mas é um afrouxamento, não uma equivalência.
- **`deferredWindows` ainda invalida a lista.** O contador é incrementado dentro de `capture` (o
  `@State` que o corpo da lista lê) e **não** é `#if DEBUG`; só o seu consumo no label é. Cada
  mudança de janela durante um gesto reavalia o corpo do feed (36 em 8 flings na correção). É custo,
  não correção: se a meta continuar sendo "zero reavaliação por avanço", este contador é o resto.
- **`invalidateLayout()` deixou de rodar por avanço durante o gesto** (o `.onChange(of:
  presented?.window)` passou a observar a janela segurada). Defensável — nada mudou sob o dedo — mas
  é mudança de comportamento, e a prova de viewport não é renovada enquanto a janela publicada cresce
  durante o hold.

## O que esta build NÃO prova

- **B02, B03, B04, B05 e B06 seguem NOT_RUN** nesta baseline. B03 está em execução; B06 exige iPhone
  físico (memória, energia, térmica, hitches) e nunca foi executado.
- Disponibilidade no TestFlight interno não certifica produção: a régua continua sendo os seis gates
  integrais PASS mais PD-10 comprovado.
- Instalação no aparelho do dono não foi observada por nenhuma sessão; o que está provado é o acesso
  interno.

## Fluxos prioritários para o dono testar

1. Rolagem longa e contínua (rajadas e flings): o feed deve continuar produzindo, sem fim prematuro.
2. Passar um card ainda desenhado, abrir artigo, voltar à âncora.
3. Responder a um convite: a próxima sugestão deve chegar em poucos cards, e "Desfazer" e "Meus
   interesses" devem continuar funcionando.
4. Troca A→B→A, reopen, salvos, retorno offline.
5. Esconder as dicas e voltar a habilitá-las nas preferências.
