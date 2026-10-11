# F25 — SwiftUI estável sob mudanças assíncronas

**Tipo:** investigação de UX/plataforma Apple, sem modificação de runtime. **Prioridade:** P0. **Versão:** 2026-10-10. **Resultado atual:** NOT_RUN (não foi executado benchmark ou teste iOS nesta pesquisa).

**Autoridade:** [North Star](PRODUCT_NORTH_STAR.md), [PD-1–PD-10](PRODUCT_DECISIONS_2026-10-09.md), [invariantes](../architecture/PRODUCT_INVARIANTS.md), [benchmark B01–B06](DISCOVERY_ACCEPTANCE_BENCHMARK.md). Essas autoridades prevalecem sobre exemplos externos de Apple API.

**Relação com frentes existentes:** F02, F05, F06, F07, F14, F17. **Owner já existente:** SwiftUI/FeedScreenStore consomem FeedPresentationSnapshot; FeedSession publica transições; MediaBroker decodifica apenas local.

## Promessa de experiência
A tela de FeedMine mantém exatamente a história e a leitura sob seus dedos, mesmo quando chegam dezenas de mídias, uma consulta termina, fonte muda, o sistema redimensiona layout ou alguém volta de outro app.

## Contrato Apple → FeedMine
- **Identidade:** `PublicationCardID` é a única identidade de card publicada que chega à SwiftUI; posição de array não é ID.
- **Geometry:** `ScrollGeometry` e APIs nativas fornecem evidência visual; distinguir deslocamento feito pelo usuário de rearranjo causado por layout, teclado, orientações ou publicação de uma nova janela. A âncora semântica sobrevive à rematerialização.
- **UI local:** `View.body` nunca consulta DB, parser, rede, scheduler ou decode de imagem. Aplicação de snapshot é mínima; concorrência/async não podem produzir uma geração velha depois de uma nova.
- **Imagens:** mídia lenta ainda não pronta sai da fila publicável conforme F06/PD-5/PD-9; já publicado não troca geometria por download. Placeholder determinístico permitido quando contratado antes da publicação.
- **Estados:** full-screen loading somente quando realmente não existe história/supply para primeira apresentação. Trabalho futuro é silencioso; no-results, offline-exhausted e supply-exhausted são estados diferentes. Progress indicator determinado exige denominador real, nunca '100/100' fictício.
- **Acessibilidade e movimento:** Dynamic Type, VoiceOver, orientação, Reduce Motion e mudanças de tema não criam nova Edition nem exposição falsa.

## UX25 — cenários verificáveis
1. **UX25-A:** scroll contínuo de 30 minutos (B03) com aquisição intensa e publicação na cauda; sem salto, blank, duplicata ou flash.
2. **UX25-B:** deixar card no centro por 10 minutos com mídia/novos artigos chegando; pixels e posição do conteúdo visualizado não mudam involuntariamente (B04).
3. **UX25-C:** alterar tamanho de fonte/rotação e voltar ao mesmo PublicationCardID com geometria recalculada.
4. **UX25-D:** iniciar busca, abrir leitor, voltar, mudar filtro A→B→A e comparar identidades e âncoras.
5. **UX25-E:** capturar Instruments SwiftUI/Hitches e comprovar ausência de trabalho de I/O em `View.body`/MainActor.
6. **UX25-F:** preparar primeira instalação em rede lenta exibindo manchetes/nomes reais, sem porcentagens inventadas.

## Não-objetivos e prova
Não criar `onAppear → loadMore`, segundo view store, timer de scroll, cache de cards em View ou `AsyncImage(url:)` remoto. Evidência de aparelho físico com trace, frame/anchor IDs e capturas; testes de componentes não substituem a jornada. **Estado: NOT_RUN**.

## Documentação oficial Apple pesquisada
- [ScrollPosition](https://developer.apple.com/documentation/swiftui/scrollposition) — Ancorar scroll por ID e não por pixels.
- [ScrollGeometry](https://developer.apple.com/documentation/swiftui/scrollgeometry) — Medir movimento real sem confundi-lo com alteração de layout.
- [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance) — Identificar view-body updates longos e recomputações.
- [Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness) — Diagnosticar hitches, hangs e main thread.
- [HIG Progress indicators](https://developer.apple.com/design/human-interface-guidelines/progress-indicators) — Progresso determinado só para trabalho mensurável.
- [HIG Design principles](https://developer.apple.com/design/human-interface-guidelines/design-principles/) — Feedback consistente e controle compreensível.
- [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) — Dynamic Type e acesso universal sem alterar identidade publicada.

**Referências transversais:** [Índice Apple UI/UX e robustez](../research/APPLE_IOS_UI_UX_RELIABILITY_2026-10-10.md) · [Mapa F21–F27](PRODUCT_AUDIT_APPLE_FRONTS_21_27.md). Links são documentação de mecanismos possíveis, não prova de que estejam em uso no FeedMine; confirmar deployment target e disponibilidade antes de codificar.
