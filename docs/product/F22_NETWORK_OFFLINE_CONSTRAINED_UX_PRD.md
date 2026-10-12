# F22 — Rede variável, uso offline e conectividade explicável

**Tipo:** investigação de UX/plataforma Apple, sem modificação de runtime. **Prioridade:** P0. **Versão:** 2026-10-10. **Resultado atual:** NOT_RUN (não foi executado benchmark ou teste iOS nesta pesquisa).

**Autoridade:** [North Star](PRODUCT_NORTH_STAR.md), [PD-1–PD-10](PRODUCT_DECISIONS_2026-10-09.md), [invariantes](../architecture/PRODUCT_INVARIANTS.md), [benchmark B01–B06](DISCOVERY_ACCEPTANCE_BENCHMARK.md). Essas autoridades prevalecem sobre exemplos externos de Apple API.

**Relação com frentes existentes:** F01, F03, F05, F09, F13. **Owner já existente:** Acquisition/Connector/Network policy decide requests; FeedSession projeta estado útil; a UI não consulta NWPathMonitor para decidir seleção.

## Promessa de experiência
Rede ausente, oscilante, lenta, cara, bloqueada por portal ou com Low Data Mode não apaga a leitura. O usuário distingue: existe história local; estamos reabastecendo; o conteúdo elegível local se esgotou; não foi possível acessar a origem.

## Contrato Apple → FeedMine
- **Separar caminho da rede e sucesso de aquisição:** `NWPathMonitor` informa capacidade/qualidade do caminho, mas não substitui erro de URLSession ou HTTP do target. Não usar `path.status == .satisfied` como licença para assumir que um site responde.
- **URLSession é transporte:** timeouts, `waitsForConnectivity`, `allowsConstrainedNetworkAccess`, `allowsExpensiveNetworkAccess`, caching e downloads pertencem ao connector/planner existente, por `AcquisitionPurpose`.
- **Local read first:** `URLCache` não é FeedEdition/asset-store; uma resposta HTTP em cache não garante publicação, ordenação ou media readiness. Renderer nunca chama rede.
- **Degradação compreensível:** erro de request afeta apenas próxima oferta e, se necessário, o estado do tail; não se transforma em full-screen error ou toast a cada host falho.
- **Privacidade e energia:** limitar requests redundantes, hosts, redirecionamentos e especulação por sinais reais; respeitar rede restrita sem declarar fontes menos relevantes editorialmente.
- **Repetição:** retry só por owner de aquisição, com causalidade/identidade corretas. Scroll e tela nunca agendam novos retry loops.

## UX22 — cenários verificáveis
1. **UX22-A:** iniciar online, entrar em modo avião em meio ao scroll: conteúdo local continua navegável; eventual falta é mostrada no tail.
2. **UX22-B:** recuperar rede após esgotar supply: reposição reaparece sem resetar Edition visível.
3. **UX22-C:** simular HTTP 304, timeout, 429, 500, redirect e DNS falho por diferentes origens; não bloquear origens saudáveis nem alterar qualidade editorial.
4. **UX22-D:** Wi-Fi→celular e Low Data Mode com mesmo contexto: medir bytes/hosts por purpose e priorização de runway.
5. **UX22-E:** voltar a contexto previamente preparado estando offline: reaproveitar local, sem spinner desnecessário.

## Não-objetivos e prova
Não introduzir segunda URLCache sem justificativa, monitor de rede por componente, endpoint de conectividade, polling de status, banner permanente 'offline' mesmo com cards disponíveis, nem prometer funcionamento de links externos sem rede. Evidência: interceptação URLProtocol, capturas UI, histórico de requests por purpose e comparação de IDs publicados. **Estado: NOT_RUN**.

## Documentação oficial Apple pesquisada
- [URLSessionConfiguration](https://developer.apple.com/documentation/foundation/urlsessionconfiguration) — Timeout, cache, conexões permitidas e sessões.
- [waitsForConnectivity](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/waitsforconnectivity) — Espera de conectividade para requests adequadas.
- [NWPathMonitor](https://developer.apple.com/documentation/network/nwpathmonitor) — Observa mudanças de caminho; não prova acesso ao host específico.
- [NWPath isExpensive](https://developer.apple.com/documentation/network/nwpath/isexpensive) — Sinal de interface potencialmente cara.
- [Accessing cached data](https://developer.apple.com/documentation/foundation/accessing-cached-data) — URLCache/cache policy com semântica HTTP, não autoridade editorial.
- [Low Data Mode property](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/allowsconstrainednetworkaccess) — Controle de acesso a redes restritas.
- [HIG Progress indicators](https://developer.apple.com/design/human-interface-guidelines/progress-indicators) — Feedback proporcional a progresso mensurável.

**Referências transversais:** [Índice Apple UI/UX e robustez](../research/APPLE_IOS_UI_UX_RELIABILITY_2026-10-10.md) · [Mapa F21–F27](PRODUCT_AUDIT_APPLE_FRONTS_21_27.md). Links são documentação de mecanismos possíveis, não prova de que estejam em uso no FeedMine; confirmar deployment target e disponibilidade antes de codificar.
