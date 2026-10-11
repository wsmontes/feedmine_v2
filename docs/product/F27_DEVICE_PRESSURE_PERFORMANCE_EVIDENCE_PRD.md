# F27 — Pressão de recursos, desempenho e evidência física

**Tipo:** investigação de UX/plataforma Apple, sem modificação de runtime. **Prioridade:** P0. **Versão:** 2026-10-10. **Resultado atual:** NOT_RUN (não foi executado benchmark ou teste iOS nesta pesquisa).

**Autoridade:** [North Star](PRODUCT_NORTH_STAR.md), [PD-1–PD-10](PRODUCT_DECISIONS_2026-10-09.md), [invariantes](../architecture/PRODUCT_INVARIANTS.md), [benchmark B01–B06](DISCOVERY_ACCEPTANCE_BENCHMARK.md). Essas autoridades prevalecem sobre exemplos externos de Apple API.

**Relação com frentes existentes:** F05, F06, F09, F10, F17, F23. **Owner já existente:** Resource policy existente adapta intensidade; Diagnostics + Instruments medem; F10 e B01–B06 continuam donos da aprovação de release.

## Promessa de experiência
Em aparelho quente, com pouco espaço/memória, bateria baixa, rede restrita ou múltiplos apps abertos, o FeedMine prioriza leitura e história local, reduz atividades especulativas antes de travar ou ser encerrado e restaura o mesmo conteúdo após terminar.

## Contrato Apple → FeedMine
- **Sinais observáveis:** Low Power Mode, thermal, memory pressure, rede cara/constrained, armazenamento livre e cena background são inputs à **mesma** política operacional/adaptive runway; nenhum deles altera relevância editorial intrínseca.
- **Adaptação:** desacelerar especulação e decodes distantes, reduzir footprint de memória, conservar assets protegidos e priorizar operações do usuário/runway. Condição de recurso melhora? Retomar exploração progressiva oportunamente, sem timer universal de polling.
- **Instrumentação com dono:** usar Instruments SwiftUI, Hitches, Time Profiler, Allocations, Network e Energy; MetricKit para regressões de campo quando disponível. Não exigir tracking remoto.
- **Testes de robustez:** Crash/termination por pressão não é exceção patológica no iOS; aplicativos precisam restaurar corretamente. Priorizar evidência de hitches/semântica do produto sobre milissegundos isolados.
- **Hardware:** simulador é útil para testes determinísticos; energia, jetsam, proteção de arquivos e decisão do scheduler exigem aparelho real. Não declarar B06 PASS sem execução física.
- **Código:** nenhuma pressão de recursos deve induzir reinicialização do feed visível, reset de filtros ou reclassificação do Provider.

## UX27 — cenários verificáveis
1. **UX27-A:** Low Power Mode + Low Data Mode durante navegação, medir queda da especulação mas manter runway útil.
2. **UX27-B:** memory pressure/prolonged scroll: reduzir decodes e cache efêmero sem perder anchor ou conteúdo publicado.
3. **UX27-C:** CPU/thermal pressure: comparar hitches e taxa de requests antes/depois, sem suprimir fontes elegíveis permanentemente.
4. **UX27-D:** disco quase cheio + remoção de cache e reinício offline: preservar livros, sessões e conteúdo protegido.
5. **UX27-E:** background sem execução concedida, foreground após horas: medir disponibilidade imediata e reabastecimento não bloqueante.
6. **UX27-F:** Instruments em iPhone físico: registrar traces reproduzíveis de scroll, app switch, decode e repetição de filtros.

## Não-objetivos e prova
Não criar segundo governor, camada de telemetria em rede, timer de limpeza ou cache para cada pressure state. Métricas vinculadas ao cenário e à versão/commit, não 'PASS' por ausência de crash em unit tests. **Estado: NOT_RUN**.

## Documentação oficial Apple pesquisada
- [ProcessInfo.isLowPowerModeEnabled](https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled) — Low Power Mode afeta trabalho discricionário.
- [Analyzing your app's battery use](https://developer.apple.com/documentation/xcode/analyzing-your-app-s-battery-use) — Energia foreground/background com Xcode, MetricKit e Instruments.
- [Reducing your app's memory use](https://developer.apple.com/documentation/xcode/reducing-your-app-s-memory-use) — Pressure, limites e recuperação.
- [Reducing terminations in your app](https://developer.apple.com/documentation/xcode/reduce-terminations-in-your-app) — Jetsam/termination e estado local recuperável.
- [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance) — View update/hitch instrumentado.
- [Diagnosing performance issues early](https://developer.apple.com/documentation/xcode/diagnosing-performance-issues-early) — Priority inversions e I/O na main thread.
- [Diagnosing memory/thread/crash issues](https://developer.apple.com/documentation/xcode/diagnosing-memory-thread-and-crash-issues-early) — Address/Thread Sanitizer e Main Thread Checker.
- [MetricKit performance](https://developer.apple.com/documentation/metrickit/monitoring-app-performance-with-metrickit) — Métricas locais/produção; não dependência de telemetry remota.

**Referências transversais:** [Índice Apple UI/UX e robustez](../research/APPLE_IOS_UI_UX_RELIABILITY_2026-10-10.md) · [Mapa F21–F27](PRODUCT_AUDIT_APPLE_FRONTS_21_27.md). Links são documentação de mecanismos possíveis, não prova de que estejam em uso no FeedMine; confirmar deployment target e disponibilidade antes de codificar.
