# F21 — Ciclo de vida da cena e continuidade da sessão

**Tipo:** investigação de UX/plataforma Apple, sem modificação de runtime. **Prioridade:** P0. **Versão:** 2026-10-10. **Resultado atual:** NOT_RUN (não foi executado benchmark ou teste iOS nesta pesquisa).

**Autoridade:** [North Star](PRODUCT_NORTH_STAR.md), [PD-1–PD-10](PRODUCT_DECISIONS_2026-10-09.md), [invariantes](../architecture/PRODUCT_INVARIANTS.md), [benchmark B01–B06](DISCOVERY_ACCEPTANCE_BENCHMARK.md). Essas autoridades prevalecem sobre exemplos externos de Apple API.

**Relação com frentes existentes:** F06, F09, F20. **Owner já existente:** FeedScreenStore / FeedSession / SessionCheckpoint; SwiftUI observa scenePhase e encaminha intenções, sem adquirir nem selecionar.

## Promessa de experiência
Alternar para outro app, atender uma chamada, bloquear a tela ou voltar após uma suspensão não deve parecer que o FeedMine foi reiniciado. A primeira apresentação útil é a última publicação válida e seu cursor; a rede só tenta melhorar a oferta futura.

## Contrato operacional Apple → FeedMine
- **Cenas não são sessões editoriais:** `ScenePhase.inactive` é possível em interrupções e transições; não significa que o conteúdo precise ser descartado. `background` informa mudança de foco, mas não promete janela de trabalho suficiente para completar aquisição.
- **Um owner da sessão:** preservar associação FeedScreenStore↔FeedSession enquanto ela permanecer válida; não reconstruir o Store a cada `.active` nem aplicar callbacks da sessão antiga à nova.
- **Checkpoint durável:** armazenar EditionID, PublicationCardID e placement nos mecanismos duráveis já existentes; `@SceneStorage` serve, no máximo, como pista visual leve, sem ser fonte de verdade para cards ou cursor.
- **Trabalho assíncrono:** ao reaparecer, revalidar a identidade da sessão antes de aplicar snapshots; resultado tardio de outra Edition não modifica a atual. Mudança de tamanho, Dynamic Type ou cena exige rematerialização de apresentação, não reedição editorial.
- **Retorno:** se app process morreu, restaurar de SQLite/publicação local, sem depender do histórico do processo, tarefas em RAM ou requisições ainda ativas.

## UX21 — cenários verificáveis
1. **UX21-A:** abrir um card, ir à Home e voltar, inclusive após chamada/overlay do sistema; conservar contexto, card e âncora.
2. **UX21-B:** deixar o aplicativo em background, provocar suspensão/terminação pelo sistema, relançar offline e confirmar que a história publicada e os salvos aparecem sem espera de rede.
3. **UX21-C:** trocar A→B→A rapidamente enquanto um resultado antigo termina; retorno de A reaproveita material válido e B não pode instalar apresentação em A.
4. **UX21-D:** mudar Dynamic Type/orientação enquanto a cena fica inativa; posição semântica permanece, sem exposição falsa.
5. **UX21-E:** abrir leitor externo, cancelar e retornar ao card correto; sem sessão duplicada nem refresh involuntário.

## Não-objetivos e prova
Não adicionar novo session manager, observador global por View, timer de foreground, ou exigir `@SceneStorage` para durabilidade. Evidência: vídeos de ida/volta, IDs de Edition/anchor antes e depois, logs locais de transições aceitas/rejeitadas e medição warm restore; testes em simulador e aparelho. **Estado: NOT_RUN** nesta pesquisa; não é certificação de funcionalidade.

## Documentação oficial Apple pesquisada
- [SwiftUI ScenePhase](https://developer.apple.com/documentation/swiftui/scenephase) — Cenas .active/.inactive/.background; valor observado no escopo da cena.
- [Restoring your app’s state with SwiftUI](https://developer.apple.com/documentation/swiftui/restoring-your-app-s-state-with-swiftui) — Restauração declarativa e limites do estado associado à cena.
- [SceneStorage](https://developer.apple.com/documentation/swiftui/scenestorage) — Persistência por cena leve, sem garantia de quando é gravada.
- [ScrollPosition](https://developer.apple.com/documentation/swiftui/scrollposition) — Posição semântica por ID visível, sem depender de offsets persistidos.
- [Reducing terminations in your app](https://developer.apple.com/documentation/xcode/reduce-terminations-in-your-app) — Terminações normais e recuperação como parte do produto.

**Referências transversais:** [Índice Apple UI/UX e robustez](../research/APPLE_IOS_UI_UX_RELIABILITY_2026-10-10.md) · [Mapa F21–F27](PRODUCT_AUDIT_APPLE_FRONTS_21_27.md). Links são documentação de mecanismos possíveis, não prova de que estejam em uso no FeedMine; confirmar deployment target e disponibilidade antes de codificar.
