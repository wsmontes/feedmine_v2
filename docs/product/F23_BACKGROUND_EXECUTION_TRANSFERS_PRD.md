# F23 — Execução limitada em background e transferências

**Tipo:** investigação de UX/plataforma Apple, sem modificação de runtime. **Prioridade:** P0. **Versão:** 2026-10-10. **Resultado atual:** NOT_RUN (não foi executado benchmark ou teste iOS nesta pesquisa).

**Autoridade:** [North Star](PRODUCT_NORTH_STAR.md), [PD-1–PD-10](PRODUCT_DECISIONS_2026-10-09.md), [invariantes](../architecture/PRODUCT_INVARIANTS.md), [benchmark B01–B06](DISCOVERY_ACCEPTANCE_BENCHMARK.md). Essas autoridades prevalecem sobre exemplos externos de Apple API.

**Relação com frentes existentes:** F01, F03, F05, F09, F15, F20. **Owner já existente:** BackgroundFeedRefresh usa os mesmos AcquisitionDemand/Planner/Coordinator/Admission e o mesmo banco; não existe um segundo feed engine.

## Promessa de experiência
FeedMine chega ao foreground com o melhor estado local possível. Ele pode aproveitar oportunidades de background para atualização de catálogo e reposição limitada, mas sua confiabilidade **não depende** de o iOS conceder execução periódica.

## O que o iOS realmente permite
- `BGAppRefreshTask`: esforço **curto, oportunista, agendado pelo sistema**, não cron a cada X horas. Pedido com `earliestBeginDate` não estabelece deadline nem garantia de horário.
- `BGProcessingTask`: manutenção mais custosa quando o sistema disponibiliza oportunidade e condições; não ideal como fundamento do scroll infinito.
- `beginBackgroundTask`: tempo adicional **limitado** para concluir gravação/commit iniciado, com expiration e chamada balanceada de `endBackgroundTask`; não permite manter a aquisição rodando indefinidamente.
- `URLSessionConfiguration.background`: mecanismo de **transferência de arquivos** e eventos de conclusão gerenciados pelo sistema; não transporta magicamente stream de RSS/JSON em memória ou WebSocket genérico quando a app está suspensa. Ao force quit do usuário, não contar com relaunch automático nem com a continuidade prometida de transfers.
- **Áudio:** playback explicitamente solicitado pode ter integração própria com audio session/background mode; não usar essa capacidade para justificar aquisição editorial contínua.
- **Catálogo PD-10:** ~24h é uma meta de **elegibilidade para verificação** em oportunidade concedida por launch/foreground/background, não horário de atualização garantido.

## UX23 — cenários verificáveis
1. **UX23-A:** pedir BGAppRefresh e negar execução por horas/dias; ao reabrir, leitura aparece imediatamente e verificação atrasada é agendada sem bloquear.
2. **UX23-B:** iniciar lote de admission e enviar para background no meio da operação: consistência de checkpoint/commit apesar de cancelamento ou task expiration.
3. **UX23-C:** tarefa disparada pelo sistema conclui sem gerar nova Edition visível; nova oferta só muda futuro da seleção.
4. **UX23-D:** suspender durante download de arquivo genuíno: testar conclusão/reconexão apenas quando houver uso real de background URLSession; não usar o resultado para inferir suporte a RSS data tasks.
5. **UX23-E:** force quit, low-power, Background App Refresh desligado e device locked: reabertura correta sem supor background work.
6. **UX23-F:** podcaster escuta áudio com tela bloqueada e volta: preservar posição de playback separada da sessão editorial.

## Não-objetivos e prova
Não criar timer em background, silent push sem infraestrutura própria, serviço de polling externo, promessa de 'atualizado toda manhã', nem duplicar scheduler. Verificar Xcode capabilities/Info.plist antes de implementar qualquer mode. Provas em aparelho físico e logs de expiration/commit; cenários simulados não substituem comportamento real do scheduler. **Estado: NOT_RUN**.

## Documentação oficial Apple pesquisada
- [Choosing Background Strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app) — Escolher tarefa curta, processamento adiado ou transferência de arquivos.
- [Using background tasks to update your app](https://developer.apple.com/documentation/uikit/using-background-tasks-to-update-your-app) — Registrar BGTaskScheduler, handler, cancelamento e conclusão.
- [Extending your app's background execution time](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time) — Tempo limitado para finalizar operações críticas já iniciadas.
- [Downloading files in the background](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background) — Transfers de arquivos sob gerenciamento do sistema.
- [URLSessionConfiguration.background(withIdentifier:)](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background%28withidentifier%3A%29) — Continuar downloads ao suspender, com restrição após force quit.
- [BGTask expirationHandler](https://developer.apple.com/documentation/backgroundtasks/bgtask/expirationhandler) — Interromper/deferir com consistência.
- [AVAudioSession](https://developer.apple.com/documentation/avfaudio/avaudiosession) — Áudio de playback explícito é caso distinto de coleta RSS.

**Referências transversais:** [Índice Apple UI/UX e robustez](../research/APPLE_IOS_UI_UX_RELIABILITY_2026-10-10.md) · [Mapa F21–F27](PRODUCT_AUDIT_APPLE_FRONTS_21_27.md). Links são documentação de mecanismos possíveis, não prova de que estejam em uso no FeedMine; confirmar deployment target e disponibilidade antes de codificar.
