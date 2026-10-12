# F26 — Integrações iOS: leitura, links, arquivos, compartilhamento e áudio

**Tipo:** investigação de UX/plataforma Apple, sem modificação de runtime. **Prioridade:** P1. **Versão:** 2026-10-10. **Resultado atual:** NOT_RUN (não foi executado benchmark ou teste iOS nesta pesquisa).

**Autoridade:** [North Star](PRODUCT_NORTH_STAR.md), [PD-1–PD-10](PRODUCT_DECISIONS_2026-10-09.md), [invariantes](../architecture/PRODUCT_INVARIANTS.md), [benchmark B01–B06](DISCOVERY_ACCEPTANCE_BENCHMARK.md). Essas autoridades prevalecem sobre exemplos externos de Apple API.

**Relação com frentes existentes:** F08, F14, F15, F18, F19, F20. **Owner já existente:** FeedSession publica Actions/handles, InteractionCoordinator executa; UI usa APIs nativas para intenção explícita e recebe o resultado.

## Promessa de experiência
Qualquer ação de sistema — abrir link, compartilhar, importar OPML, copiar URL, ouvir podcast, receber uma chamada e voltar — parece extensão natural do FeedMine e não desfaz a descoberta atual.

## Contrato Apple → FeedMine
- **Leitor web:** escolher SFSafariViewController para navegação integrada simples; WKWebView somente quando necessidade documentada justificar controle e carga extras. Falha do site externo não destrói FeedEdition.
- **ShareLink/Transferable:** compartilhar attribution/title/URL do payload efetivamente publicado. Preparar preview sem fazer fetch remoto no renderer ou compartilhar revisão editorial futura por engano.
- **Arquivos:** exportar OPML como *lista de subscriptions*, não backup integral de bookmarks/estado. Importer e export devem indicar exatamente quais dados ficam incluídos, com segurança e sem tornar importação requisito para onboarding.
- **Clipboard:** pedir leitura/importação por gesto explícito; não sondar clipboard no foreground para iniciar qualquer operação não solicitada.
- **Deep links:** Universal Links dependem de site controlado e associated domains, inclusive arquivo AASA; FeedMine sem servidor de conteúdo pode optar por não adicionar isso na baseline. Se implementados, URLs externas são inputs não confiáveis: validar e não executar ação destrutiva automática.
- **Áudio:** background playback com AVAudioSession/background capability apropriada, se necessário à jornada F15; tratar interrupções, retomar conforme orientação do sistema e recuperar posição local, não explorar o modo audio para aquisição invisível.
- **Retorno:** ao fechar sheet, leitura ou import, preserva Scene/Session identity e anchor.

## UX26 — cenários verificáveis
1. **UX26-A:** abrir artigo de card, voltar exatamente a ele; ao abrir URL inválida mostrar falha local e preservar a Edition.
2. **UX26-B:** compartilhar publicação e conferir link/título/Provider congelados e ausência de requisição adicional.
3. **UX26-C:** importar e exportar OPML de corpus real, inclusive sem rede, preservando elementos pessoais fora do catálogo.
4. **UX26-D:** colar URL voluntariamente, negar clipboard permission e continuar usando feed sem penalidade.
5. **UX26-E:** reproduzir podcast, trocar de aplicativo, bloquear tela, receber ligação, mudar rota Bluetooth e retornar à mesma posição.
6. **UX26-F:** caso Universal Links sejam oferecidos, validar parâmetros malformados e ausência de operações com side effects automáticos.

## Não-objetivos e prova
Não exigir site backend, Handoff/Share Extension/App Intents/notifications/deep links só porque o iOS os suporta; cada integração precisa de gesto e benefício de produto. Não misturar execução de ação com renderização. Capturar passos e resultado real por superfície/ambiente. **Estado: NOT_RUN**.

## Documentação oficial Apple pesquisada
- [SFSafariViewController](https://developer.apple.com/documentation/safariservices/sfsafariviewcontroller/) — Leitura de página externa in-app.
- [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview) — Alternativa quando a UX exigir controle maior.
- [ShareLink](https://developer.apple.com/documentation/swiftui/sharelink) — Compartilhamento nativo com Transferable.
- [Uniform Type Identifiers](https://developer.apple.com/documentation/uniformtypeidentifiers/) — OPML, arquivos e representações interoperáveis.
- [Supporting universal links](https://developer.apple.com/documentation/xcode/supporting-universal-links-in-your-app) — Deep links apenas com associated domain controlado e URL validada.
- [Supporting associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains) — Requisito website↔app real de universal links.
- [AVAudioSession](https://developer.apple.com/documentation/avfaudio/avaudiosession) — Sessão do sistema para reprodução.
- [Handling audio interruptions](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions) — Chamadas, áudio externo, route changes.
- [UIPasteboard](https://developer.apple.com/documentation/uikit/uipasteboard) — Entrada por clipboard em ação explícita.

**Referências transversais:** [Índice Apple UI/UX e robustez](../research/APPLE_IOS_UI_UX_RELIABILITY_2026-10-10.md) · [Mapa F21–F27](PRODUCT_AUDIT_APPLE_FRONTS_21_27.md). Links são documentação de mecanismos possíveis, não prova de que estejam em uso no FeedMine; confirmar deployment target e disponibilidade antes de codificar.
