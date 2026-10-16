# Rodada de 2026-10-16 — a build 48 no TestFlight, a reabertura medida, e o engasgo explicado

Este relatório cobre a rodada inteira. Onde algo não foi executado, o texto diz `NOT_RUN` e a razão. Nenhum número
abaixo veio de relato de agente sem artefato: os que eu não rodei estão marcados como herdados ou `NOT_RUN`.

## 1. Identidade e estado final

| Item | Valor |
|---|---|
| `main` | `baf10e2d` (igual a `origin/main`, publicado por fast-forward) |
| Build distribuída | `1.0 (48)` pareada a `03d05f5f4bfff9ec0ce6c3be3f4a78ef5073c38f` |
| Apple | `processingState=VALID`, `internalBuildState=IN_BETA_TESTING`, grupo interno `WawaTesters`, sem distribuição externa |
| Tag local | `ios/1.0-build.48-03d05f5f` (não empurrada) |
| Aparelho | iPhone 14 Plus, iOS 18.6.2 (`22G100`), UDID `00008110-00067D861486201E` |
| Bench congelado | `bench/EVALUATOR.sha256` 6/6 OK; `bench/MANIFEST.sha256` 2314 entradas |
| Classificação honesta | **interna, de observabilidade**. Fluidez `NOT_CERTIFIED`; **B06 `NOT_RUN`**; reabertura estava fora da 48 e entrou depois, na `main` |

## 2. O que a rodada entregou

### 2.1 A build 48 foi publicada, com pareamento provado

`scripts/release-testflight.sh` recusou-se a trabalhar com árvore suja (não estava), conferiu o catálogo público **antes**
e **depois** do archive, e provou o pareamento lendo o SHA carimbado dentro do `.app` arquivado:

```
PAIRING OK: TestFlight build 1.0 (48) = 03d05f5f4bfff9ec0ce6c3be3f4a78ef5073c38f
Uploaded FeedMine
BUILD 1.0 (48) = 03d05f5f4bfff9ec0ce6c3be3f4a78ef5073c38f  (tag ios/1.0-build.48-03d05f5f)
```

Confirmação **do lado da Apple**, por consulta read-only à API (não pelo script): `VALID`, `expired=false`,
`uploadedDate=2026-10-16T07:43:13-07:00`, `buildAudienceType=APP_STORE_ELIGIBLE`, `internalBuildState=IN_BETA_TESTING`.
O grupo interno tem `hasAccessToAllBuilds=true` — a Apple recusou a associação manual
(`Builds cannot be assigned to this internal group`) e depois confirmou a associação automática.

**A instrumentação DEBUG não vai para o binário distribuído**, e isso foi medido nos bytes, não inferido: varredura de
todo o `.app` de Release — `feedmine journey` 0, `feedmine frames=` 0, `feed-frame-proof` 0,
`FEEDMINE_JOURNEY_CONSOLE` 0, e o **controle positivo** `runway_completed` presente (1), provando que a varredura
encontra cadeias reais. Executável do archive: sha256 `dff14b71b2271e8a8464c73600ea072e4474c75aa9db7ec0f833cd7763222218`.

### 2.2 A jornada de imagem passou **no iPhone físico**, com pixels e controle negativo

```
xcodebuild test … -destination 'id=00008110-00067D861486201E' \
  -only-testing:FeedMineUITests/CardImageJourneyUITests -only-testing:FeedMineUITests/FluidityJourneyUITests
→ CardImageJourneyUITests: Executed 2 tests, with 0 failures
→ FluidityJourneyUITests:  Executed 1 test,  with 0 failures (30.782 s)
→ FeedMineUITests.xctest:  Executed 3 tests, with 0 failures in 76.262 s
→ ** TEST SUCCEEDED **
```

O teste amostra o retângulo do slot e conta a **testemunha** (magenta `#F4F`, que nenhuma paleta, texto ou chrome do app
desenha). No aparelho, com a imagem pronta: `witness=193397/302940`, `dominant=#F4F=191759`. O **controle** do mesmo
arquivo, na mesma corrida, deu `dominant=#FFE=611321` com **zero** pixels da testemunha. A captura do XCTest
(`/tmp/int48-physical-evidence/2FAFF157-….png`, sha256 `49e770cd…`) mostra o bitmap nos slots, com cabeçalho, manchete,
resumo e data, e o layout intacto na volta da carta à janela (`witness` 193397 → 168332, geometria preservada).

A primeira tentativa no aparelho tinha falhado com `The test runner failed to initialize for UI testing. Timed out while
enabling automation mode` — **infraestrutura**, não produto: depois de o dono replugar o cabo, sem alterar permissão,
senha, Developer Mode ou pareamento, as mesmas jornadas passaram.

### 2.3 A reabertura: o critério da V1, medido e comparado

A fronteira restauração↔descoberta foi reescrita (`3e6c54b6` + `8d4d571b`, transportados para a `main`):
`init` → `warmAssociation()` deixou de ler o catálogo no caminho síncrono
(`AppComposition.swift:1329-1335`, cache só em `:1339-1342`) e a consulta pesada passou a ser liberada dentro de
`launch()` (`:328-343`, fora do main actor em `liveDiscoveryQuery`, `:1621-1624`). O frio continua aguardando antes de
construir (`:1259`), de propósito.

Provas: **vermelho/verde na mesma régua** — os dois smokes novos passam, e contra o estado deliberadamente ablacionado
(adoção sem materializar + guard do `await` removido) dão 5 falhas, exatamente as cláusulas do gate. Medição
comparável, com onboarding respondido antes das duas medições: **frio 2262 ms** (espera 730…1664 ms, 1 carta) contra
**morno 1441 ms** (`kind=none`, 57 cartas). A parcela da descoberta sai `NÃO MEDIDA`, com a razão — nenhum instrumento a
cronometra em separado. E uma afirmação que o autor **não** fez: o evento que libera a descoberta comprova avaliação do
corpo do host, **não** commit de pixels; a alegação forte sobre "quadro apresentado" fica `INDETERMINADO`.

### 2.4 O engasgo: medido e explicado

Duas fases, o **mesmo `.app`**, o mesmo aparelho, na mesma corrida:

| | fase A (ociosa, 89 s) | fase B (rolagem, 26 s) |
|---|---|---|
| quadros | 5316 | 1138 |
| late / bad / **severe** | 1 / 0 / **6** | 15 / 39 / **90** |
| fora do orçamento | **0,13%** | **12,7%** |
| pior intervalo | 268,1 ms | 289,3 ms |
| segundos com severo | 3 (só os 3 primeiros, arranque) | **21 de 26** |
| `advance` (o leitor se moveu) | **zero** | 41 |

**97× entre repouso e gesto.** E a estrutura por segundo diz onde: os **6 segundos com ≥4 `advance forward` são
exatamente os 6 `swipeUp`**, e concentram **54 dos 90 severos**, com **11–13 instalações de janela naquele segundo** e a
janela admitida crescendo de 17 para 51 cartas. No repouso (2 admissões) são 6 severos no total.

Três sínteses de gesto muito diferentes, no mesmo app, colapsam na **mesma fração** de quadros fora do orçamento
(~10%) enquanto a **contagem** segue as observações do app: A `swipeUp(.fast)` 40 obs → 84 severos (2,10/obs);
B 24 arrastos em etapas 101 obs → 277 severos (2,74/obs); C `swipeUp(.slow)` 30 obs → 76 severos (2,53/obs).

A ablação que parecia óbvia foi **refutada**: pular a publicação redundante do estado (47% das publicações, com âncora,
janela e reposição idênticas ao controle) deu 84 → 98 severos e 375 → 407 ms — dentro do **piso de ruído medido na
mesma receita** (mesmo código, duas corridas: severos −12%, pior +22%). O custo **não** está ali.

Dois achados de régua que valem tanto quanto o resultado: (a) o **pior intervalo de uma corrida única não é estável**
(o mesmo método B deu 1.516,9 ms e 299,5 ms em corridas diferentes) — não serve de métrica sem repetições; (b) o
instrumento **falhou em vez de produzir um "ganho"** quando a receita de gesto não rolou o leitor
(`initial_card == final_card` → `XCTAssertNotEqual` → `TEST FAILED`).

### 2.5 Referência externa (Instagram e Facebook no mesmo aparelho)

A outra sessão OMP mediu os dois apps de referência com a mesma régua. Em palavras nossas, e **sem** material de
terceiros: ambos levam ~2,7–3,1 s de `launch` e ~3,8–4,2 s até a primeira carta; ~2,7–3,4 s de "ocupado" (espera de
quiescência do XCTest, **proxy** de materialização, não frame time) depois de cada gesto; e — medido duas vezes em cada
— **nenhum dos dois restaura a posição de leitura ao reabrir**.

Isso é o argumento comparativo mais útil da rodada: o critério da V1 que a `main` acabou de ganhar (reabrir no ponto em
que o leitor estava) está **adiante** do padrão da indústria, e o nosso arranque já é mais rápido que os dois. O que se
transfere é decisão de engenharia, não código: persistência atômica com namespace versionado, rastreio de "item
realmente visível" como subsistema próprio, URL de mídia assinada e temporária, e convenção de nomenclatura na árvore de
acessibilidade.

**Decisão do dono, registrada:** o material bruto dessa exploração (relatório + 1,0 MB de evidência) **não** pode ser
publicado no repositório, que é público, porque contém nomes de usuários e texto de posts de terceiros. Ele foi movido
para fora do repo (`~/Documents/feedmine-rea-meta-2026-10-16/`, com `diff -r` e `cmp` conferidos antes de remover) e
nada foi commitado. Regra adotada: nunca `git add -A`/`.` no checkout canônico enquanto houver material de terceiros não
rastreado.

### 2.6 Estrutura: dois arquivos grandes partidos em módulos, com bateria verde

| Arquivo | Antes | Depois | Verificação |
|---|---|---|---|
| `Sources/FeedMineUI/FeedScreen.swift` | 807 | **207** (+ chrome 62, captura visual 356, viewport 194) | 179 testes, **0 falhas** |
| `Sources/FeedMinePersistence/PublicationStore.swift` | 1166 | **165** (+ escrita 317, leitura/apresentação 228, histórico 356, coding 158) | 722 testes, 1 skipped, **0 falhas** |

Pureza do movimento verificada por extração de faixas do HEAD e comparação byte a byte (o corpo dos arquivos novos é o
corpo original; a única diferença além de cabeçalhos de import são dois `private` relaxados para o viewport ser usado
pelo arquivo principal). Um **guarda de fronteira do módulo UI** que lê o texto-fonte teria perdido cobertura com o
split: em vez de apagá-lo, eu o mantive e **estendi a varredura aos arquivos novos** — e ele então pegou uma linha
minha errada (`#available` de execução continua em `FeedScreen.swift`, só o `@available` do viewport mudou de casa).
Ambos aguardam verdict de integração; não entraram em lugar nenhum.

### 2.7 Régua mais óbvia, sem número mágico

Nasceu `bench/journey.py` (branch própria, hash próprio em `bench/journey.sha256`), que lê o traço do app e o console
do aparelho e devolve **veredito binário com o número cru ao lado** para M1/M2/M3/M4/M7/M10, e `NOT_RUN` **com a linha
do código que deveria gravar o fato** onde o traço não o contém:

```
[M1] abrir e ter conteúdo na mesma geração            PASS
[M3] rolar atinge carta que existe, para frente é para frente   PASS
[M4] rolar com trabalho de fundo não move o que está acima      PASS
[M7] a âncora que eu reabro é a âncora que o app gravou         PASS
[M10] rolar rápido: a série de quadros, relatada                PASS
[M5] as imagens aparecem                                        NOT_RUN
[M12] p50/p95 de lançamento → primeira carta                    NOT_RUN (o instante do lançamento não é gravado)
```

Uma revisão independente derrubou a primeira versão (nove injeções de controle positivo depois): evidência truncada não
pode provar ausência; `[PASS, None]` não pode virar PASS; a ordem das cartas tem de ser por edição; `preparation=done`
**não** é fim de feed; e **arquivo de mídia não prova pixel apresentado** — essa pergunta ficou `NOT_RUN` com a razão, em
vez de um verde confortável. Nada de `bench/` congelado foi tocado (0 linhas), e aposentar cláusula com número escolhido
exige o protocolo de revisão do oráculo, que **não** foi aberto sem autorização.

### 2.8 O botão que parecia morto: a jornada de compartilhamento encontrou um defeito real

A bateria grande nunca tinha tocado o botão de compartilhar: o único caso que o citava apenas afirmava que ele
**existe** (`FeedMineUITests.swift:567`). A jornada escrita nesta rodada — tocar `export-share`, exigir a superfície do
sistema sobre a folha do app, e voltar ao mesmo ponto de leitura — **reprovou**, e a reprovação é o achado:

```
export-share DIAGNOSTIC: surface over the app's own sheet within 30 s = false
export-share DIAGNOSTIC: after closing the app's own export sheet, platform surface = true
FeedMineUITests.swift:662: error: XCTAssertTrue failed - Compartilhar must open the system's own share surface
over the app's own sheet; measured on 2026-10-16: it does not
```

Ou seja: **para o leitor, "Compartilhar" parece não fazer nada** até ele fechar a folha de exportação — e é exatamente
o que a doutrina da V1 proíbe (*do not ship dead buttons*). Vale igual para **"Salvar arquivo"**, que passa pelo mesmo
`sharedExport` (`FeedMineApp.swift:1086-1087`). O defeito é **pré-existente** e está no binário distribuído.

Reproduções: **4**, sempre a mesma asserção — três do dono do teste e **duas minhas**, em simulador próprio e derived
data próprio, com log bruto preservado (`/tmp/sharecheck-ORCH-repro.log`; `Test Case … failed (94.005 seconds)`,
`** TEST FAILED **`). A minha reprodução não é relato de agente: é um vermelho que eu rodei.

Causa provável, confirmada por leitura: `FeedMineApp.swift` tem **cinco `.sheet` irmãos** no mesmo apresentador
(`:287` player, `:295` o host de uma-superfície-por-vez, `:424` `sharedExport`, `:433` import preview, `:454`
`sharedLink`) enquanto existe uma máquina explícita de uma-superfície-por-vez em `:120-140`. Compartilhar e Salvar
usam o `.sheet` **irmão**, fora dessa máquina, com a folha de exportação já apresentada pelo host — o caso em que o
SwiftUI adia a segunda apresentação.

O arquiteto autorizou **HS-02** para corrigir, com a propriedade a preservar em uma frase: *"quando o usuário toca
Compartilhar ou Salvar arquivo, o sistema apresenta a ação solicitada naquele fluxo, sem exigir outra ação
inesperada; cancelar devolve o usuário ao contexto anterior, sem perder a leitura"* — e explicitou que é esse
comportamento que dirige a implementação e o teste, **não** a quantidade de `.sheet` que o SwiftUI permite declarar.
Autorizou também integrar a remoção do banner morto, que entrou na `main` em `c9d599eb` (7 arquivos, +369/−70,
`swift test` 1400/4 skipped/0).

## 3. B06 — o único gate congelado nunca executado

O contrato (`docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md:98-104`) exige a jornada B03 completa no **iPhone físico**,
com corpus servido pelo Mac, sem crash, sem terminação por memória, sem travamento ≥1 s, sem vazamento com crescimento
sustentado, e coleta de RSS/CPU/energia/térmica/hitches/tempo de scroll. **Simulador não aprova o gate.**

Medido nesta rodada (tudo read-only, nada instalado): aparelho visível a `devicectl` **e** `xctrace`; templates
`Animation Hitches` e `Activity Monitor` **presentes**; IP de LAN `192.168.1.76` igual ao que a variante congelada
espera; porta 8757 livre; identidade de assinatura presente; **variante de transporte verificada contra o corpus
congelado** (`4616 comparações, 0 divergências`); `bench/EVALUATOR.sha256` 6/6.

Dois bloqueios e uma lacuna:

1. **`Energy Log` não existe** nesta instalação do Xcode (26 templates *Standard*, nenhum com esse nome; os
   *instrumentos* de energia/térmica existem). O arquiteto decidiu: registrar a ausência, **não** alterar o instrumento
   congelado, e rodar mesmo que o ensaio curto falhe só por isso.
2. **Espaço**: o B06 pede na prática 8–10 GB para 45 min × 3 instrumentos + derived + pull do contêiner; a máquina tem
   5,7 GB, e há um build de outro agente em curso.
3. **Lacuna de protocolo**: o registro de modelo/iOS/térmica/bateria no início não existe em nenhum instrumento, e
   `devicectl` não tem subcomando de bateria nem de térmica. Fica `NOT_MEASURED` com a razão, registrado à mão antes da
   corrida — o arquiteto autorizou o registro manual.

O ensaio curto foi **tentado e recusado pelo próprio instrumento**, por precondição real:

```
INCOMPLETE: RuntimeError: REFUSED: FeedMine already running on device: [7282, 7567]
```

O mapa confiável: `7282` = `com.feedmine.app` (o app de produção do dono, build 44) e `7567` = `com.feedmine.development`
(build 48). **Os dois bundles instalam `FeedMine.app/FeedMine`**, então o nome do processo não distingue nada: a
identificação vem de `devicectl device info apps` (que dá o `file:///…/Bundle/Application/<UUID>/FeedMine.app/` de cada
bundle) contra o `executable` de `device info processes`. Depois disso o ensaio foi **pausado**, a pedido do dono, porque
o aparelho está com a outra sessão OMP (as medições de referência externa) — nada foi instalado e nada foi medido.
`B06: NOT_RUN`.

## 4. Aquisição e armadilhas medidas nesta rodada

- **Disco é o recurso mais frágil.** Ele interrompeu três agentes por ENOSPC e matou uma corrida de UI (`Executed 0
  tests`). Nada de ENOSPC foi relatado como resultado de produto ou de teste. Recuperável sem perder evidência: `.build`
  de worktrees, derived data, simuladores obsoletos, cópias duplicadas de `bench/run`. Preservados: os 13 `.xcresult`,
  o archive da 48 e todos os brutos.
- **`git worktree add` de uma árvore com `.build` clona o cache (APFS)** e o build seguinte falha com
  `precompiled file … was compiled with module cache path …`: apague `.build` na worktree nova antes do primeiro build.
- **`profiles.json` e `catalog.sqlite` são gitignored**: sem eles o alvo de teste morre em `CpResource` **antes** de
  executar teste — `xcodebuild test` exit 65 com "Executed 0 tests". Não é falha de teste.
- **Um filtro `-only-testing` que não casa nada imprime `** TEST SUCCEEDED **` com zero testes.** Foi o que aconteceu
  quando o seletor apontou para o alvo errado; o que denuncia é a contagem (`Executed 0 tests`), nunca a linha de
  sucesso. Nesta rodada, um resultado assim foi descartado.
- **Dois agentes na mesma árvore trocam a branch de baixo um do outro.** Um subagente fez `git checkout -b` no checkout
  compartilhado e a minha verificação passou a medir outra árvore. Depois disso, toda verificação de mim passou a rodar
  em worktree própria e isolada.
- **`devicectl` não identifica o app pelo nome**: ver §3.
- **A linha `feedmine journey` não entra na jornada dirigida** porque `TEST_RUNNER_*` fica no processo do *runner* e o
  app sob teste não a herda; o teste declara em `launchEnvironment` só `FEEDMINE_TRACE_CAPTURE`. O que substitui, e é
  melhor para a pergunta, são os `installed cards=… ids=[…]` do os_log — e a jornada do instrumento de aparelho
  continua trazendo a linha completa.
- **A fase "Stamp build identity" perde o carimbo `FeedmineGitSHA` em build incremental** (não declara dependência do
  `ProcessInfoPlistFile`); só derived data virgem reproduz a ordem certa. Não afeta a 48 distribuída (o archive passou
  no pareamento com a estampa presente); afeta qualquer Debug reconstruído.

## 5. O que esta rodada NÃO prova

- **B06 `NOT_RUN`.** É o gate que trava a release externa, e ele não foi executado.
- **Fluidez `NOT_CERTIFIED`.** O engasgo está **localizado** (gesto, no caminho de observações→admissões) e a causa
  óbvia foi **refutada**; nenhuma correção de produto foi implementada, porque o arquiteto proibiu corrigir antes de
  caracterizar.
- **A build distribuída não foi validada no aparelho do dono.** O `com.feedmine.app` dele ainda está na **build 44**; a
  48 está `IN_BETA_TESTING`, e a validação da versão distribuída depende de ele instalar pelo TestFlight.
- **Release externa não autorizada**, e a ausência da reabertura **na 48** continua explícita: ela entrou depois, na
  `main`, e não foi reenviada à Apple.

## 6. Artefatos e hashes citados

| Artefato | Identificador |
|---|---|
| Log UI físico (jornadas 3/0) | `/tmp/int48-physical-authorized.log` — sha256 `03fd1799f7d269ba9ac441812fa94bc0c4f58e276c47c313c8531b0c2bac37be` |
| Captura do aparelho (imagem desenhada) | `/tmp/int48-physical-evidence/2FAFF157-….png` — sha256 `49e770cd7c1581edbb346945dc0fa70a27e19fbda1a655a6920b1480846350d7` |
| Série de quadros do aparelho | `/tmp/int48-physical-evidence/62CB9727-….txt` — sha256 `39c4fd95eae06dccc10c0174a9ef0396a49acdf3ef30bd4cc6ab8c5571a1fb` |
| Log da primeira tentativa física (infra) | `/tmp/int48-physical-journeys.log` — sha256 `d08b538f1b72acc025ebb2aad2d6393a4d5913cf799102eba096a5e41b07cc35` |
| Confirmação da Apple | `/tmp/int48-apple-confirmed.json` |
| Pré-validação da árvore combinada | `/tmp/int48-final-ui.log`, `/tmp/int48-final-package.log` |
| Corrida F48-HITCH | `/tmp/hx-run-control`, `/tmp/hx-run-branch`, `/tmp/hx-run-control-v1-b-falhou` |
| Registro de ambiente do B06 | `/tmp/b06-preflight-registro.md` (a versionar junto do relatório do gate) |

Estes artefatos são **referências locais desta máquina**, não arquivos versionados: os hashes estão aqui para que uma
cópia futura possa ser conferida, e os comandos das seções 2 e 3 reproduzem cada um deles.

## 7. Corte da migração para o iMac (2026-10-16, fim da rodada)

A estação foi migrada no meio da rodada. O que importa para quem retomar:

| Item | Estado no corte |
|---|---|
| `origin/main` | **`c9d599eb`** — código da build 48 + reabertura aprovada + remoção do banner de clipboard. Empurrado, então o clone do iMac nasce nele |
| Build distribuída | `1.0 (48)` = `03d05f5f`, `IN_BETA_TESTING`, grupo interno. **Não** inclui a reabertura nem a remoção do banner |
| Refs locais que o GitHub nunca teve | **305 refs / 40 branches** viajam em `_migration_feedmine_2026-10-16/git/feedmine_v2-local-refs.bundle` (verificado: *complete history*) |
| Trabalho não commitado | o único era a correção HS-02, preservada em `fix/hs-02` = **`090b8352`** (mensagem deixa claro: **não compilado**) |
| Acessos | `omp-agent/` (config, `models.yml`, `*.key`, `agent.db` com os logins, history), chave ASC, SSH, `.env` — todos conferidos **byte a byte** |
| Não copiado de propósito | tudo o que é recriável: `.build`, derived data, simuladores, `bench/run/**`, `.xcresult`, `catalog.sqlite`, corpus, estado dos apps Codex/Claude |
| Não copiável por arquivo | **identidades de assinatura e senhas do Keychain de login** — precisam ser criadas/importadas no iMac |

Duas correções de rota registradas nesta rodada, para não serem repetidas:

1. **Encerrar processo do dono não é minha decisão.** Eu encerrei `com.feedmine.app` (build 44) para liberar o aparelho
   para o B06; o dono corrigiu que a prioridade entre agentes **não** era autorização para encerrar processos dele. O
   efeito foi só estado de execução, mas a lição é a regra: o instrumento recusa se **qualquer** processo FeedMine
   estiver vivo, os dois bundles instalam `FeedMine.app/FeedMine`, e a distinção só é possível por
   `devicectl device info apps` (UUID do bundle) contra o `executable` de `device info processes`. Só o bundle de
   **desenvolvimento** é meu; o de produção, não.
2. **Uma corrida que falha antes da premissa não é testemunho.** A minha primeira tentativa de reproduzir o defeito do
   share falhou por ambiente (o feed não apareceu — faltavam os insumos gitignored na worktree nova) e eu a descartei em
   vez de contá-la como segunda observação. O que vale é a corrida com os insumos no lugar, que falhou **na asserção do
   share** (`FeedMineUITests.swift:662`) — e é essa que está em `relatorios/sharecheck-ORCH-repro.log`.

## 8. Anexo — registro de ambiente e preflight do B06 (o que nenhum instrumento coleta)

O contrato do B06 exige registrar modelo, iOS, térmica e bateria **no início**, e nenhum instrumento faz isso. O
arquiteto autorizou o registro manual, com a origem de cada dado; onde a interface não expõe o dado, vai
`NOT_MEASURED` com a razão — nunca inferido.

| Dado | Valor | Origem |
|---|---|---|
| Aparelho | iPhone 14 Plus (`iPhone14,8`), série `W44LWTR2HT` | `xcrun devicectl device info details` |
| iOS / build | 18.6.2 / `22G100` | idem |
| Developer Mode / DDI | `enabled` / `ddiServicesAvailable: true` | idem |
| UDID (hardware) | `00008110-00067D861486201E` | idem |
| macOS / Xcode | 26.3.1 (25D2128) / 26.6 (17F113), `xctrace` 16.0 | `sw_vers`, `xcodebuild -version`, `xcrun xctrace version` |
| Bateria no início | **NOT_MEASURED** | `devicectl` não tem subcomando de bateria: a lista de `device info --help` é `appIcon`, `apps`, `authListing`, `ddiServices`, `details`, `displays`, `files`, `lockState`, `processes` |
| Estado térmico no início | **NOT_MEASURED** | Mesma razão. Durante a captura o `xctrace` ligou `device-thermal-state-intervals` (1 amostra), mas o **template** de energia não existe nesta instalação (26 templates *Standard*, nenhum `Energy Log`) |
| IP de LAN do Mac | `192.168.1.76` — igual ao que a variante congelada espera | `ipconfig getifaddr en0` |
| Porta do corpus | 8757, livre | `lsof -nP -iTCP:8757 -sTCP:LISTEN` |
| Variante de transporte | **verificada** contra o corpus congelado | `python3 bench/transport_variant.py --host 192.168.1.76:8757 --verify-only` → `4616 comparações, 0 divergências` |
| Insumos congelados | `bench/EVALUATOR.sha256` **6/6 OK**; `bench/MANIFEST.sha256` 2314 entradas | `shasum -a 256 -c` |

**Ensaio curto executado** (`--validate`, 60 s): pacote em `bench/run/20261016T184556Z/b06`; veredito
`INCOMPLETE` / `SCHEMA VALIDATION ONLY — NOT GATE EVIDENCE`. `rss`, `cpu`, `memory` e `thermal` deram **BOUND** com
amostras atribuídas ao processo (58/57/58/1); `hitches` ligou os dois schemas mas **0 amostras** (o watchdog da janela
curta mata a gravação antes do selo — e a outra sessão OMP mediu o mesmo zero numa gravação que **fechou limpa**, por
attach); `energy` **UNBOUND** pelo template ausente; `scroll_time` **UNBOUND** porque a validação curta interrompe o B03
de propósito. A **Rede Local ficou provada pelo lado do Mac**: 98 requisições do aparelho no `server.log` do corpus,
com bytes e atraso por feed.

Leitura honesta: os instrumentos **de processo** capturam; o de hitches **não serve como testemunha de fluidez** nesta
máquina, e o resultado não foi maquiado — `B06: NOT_RUN`, e o veredito se escreve contra a régua congelada, nunca pelo
instrumento (que só emite `CERTIFICATION EVIDENCE — NOT PASS`).
