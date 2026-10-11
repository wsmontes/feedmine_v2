# FeedMine V2 — Apple Platform Deep Dives F21–F27

**Status:** sete frentes complementares de investigação e especificação observável, sem certificação. **Data-base:** 2026-10-10. **Origem:** documentação Apple oficial, confrontada com as promessas da V2 e com as frentes existentes. **Índice técnico:** [Pesquisa Apple UI/UX](../research/APPLE_IOS_UI_UX_RELIABILITY_2026-10-10.md).

F01–F20 e os documentos normativos continuam prevalecendo; estes deep dives não adicionam módulos, engines ou recursos de produto automaticamente, e **não alteram B01–B06**. Cada frente toma como entrada um comportamento existente, documenta os limites da plataforma e formula oráculos verificáveis num iPhone real.

| Frente | Tema | Pai | Prioridade | PRD |
|---|---|---|---|---|
| F21 | Ciclo de vida da cena e continuidade da sessão | F06, F09, F20 | P0 | [Abrir PRD](F21_IOS_SCENE_SESSION_CONTINUITY_PRD.md) |
| F22 | Rede variável, uso offline e conectividade explicável | F01, F03, F05, F09, F13 | P0 | [Abrir PRD](F22_NETWORK_OFFLINE_CONSTRAINED_UX_PRD.md) |
| F23 | Execução limitada em background e transferências | F01, F03, F05, F09, F15, F20 | P0 | [Abrir PRD](F23_BACKGROUND_EXECUTION_TRANSFERS_PRD.md) |
| F24 | Durabilidade local, proteção de arquivos e recuperação | F01, F08, F09, F10, F18 | P0 | [Abrir PRD](F24_IOS_STORAGE_PROTECTION_RECOVERY_PRD.md) |
| F25 | SwiftUI estável sob mudanças assíncronas | F02, F05, F06, F07, F14, F17 | P0 | [Abrir PRD](F25_SWIFTUI_PRESENTATION_STABILITY_UX_PRD.md) |
| F26 | Integrações iOS: leitura, links, arquivos, compartilhamento e áudio | F08, F14, F15, F18, F19, F20 | P1 | [Abrir PRD](F26_IOS_SYSTEM_INTEGRATIONS_PRD.md) |
| F27 | Pressão de recursos, desempenho e evidência física | F05, F06, F09, F10, F17, F23 | P0 | [Abrir PRD](F27_DEVICE_PRESSURE_PERFORMANCE_EVIDENCE_PRD.md) |

## Resumo das fronteiras
- **F21:** F20 decide novidades/retorno do produto; F21 valida contratos reais da cena/sessão no iOS.
- **F22:** F03/F05 definem aquisição/runway; F22 testa limites de rede, observabilidade e UX offline/Low Data.
- **F23:** F01/F20 definem por que atualizar; F23 explicita quais jobs o iOS pode executar e como sobreviver ao não agendamento.
- **F24:** F09 decide durabilidade; F24 mapeia directories, proteção, backup, purge e recovery.
- **F25:** F06 define cards sagrados; F25 mede SwiftUI, ancoragem, loading e atualização visual.
- **F26:** F14/F15/F18/F19 definem jornadas; F26 fixa contratos de integração iOS e a necessidade real de cada capacidade.
- **F27:** F10 mantém release gate; F27 é diagnóstico de memory/energy/thermal/threads em dispositivo físico.

## Ordem de execução sugerida
Primeiro F21 + F23 + F24 (lifecycle/durabilidade), em paralelo com F22 + F25 (network/UX); depois F27 (pressão real) e F26 (integrações conforme relevância). Avaliar evidências de F05/F06/F09/F20 antes de criar código novo.

## Condições transversais
- Nada em SwiftUI inicia rede; nada no renderer depende de arquivos purgáveis para existir; nenhuma transição implícita substitui Edition.
- Quando trabalho assíncrono continua depois do foco, o resultado só altera estado futuro e passa pela admission/transaction já existente.
- Novas APIs Apple exigem verificação do deployment target; ações do sistema devem ser semanticamente distintas do background acquisition.
- Benchmark cumprido significa execução do cenário black-box e prova física quando exigida, não somente suite de Swift tests verde.
