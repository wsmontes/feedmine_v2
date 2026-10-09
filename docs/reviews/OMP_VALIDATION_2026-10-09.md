# Execução do plano OMP — 2026-10-09

Base `fe91c0f`; branch de trabalho `codex/omp-plan-execution`; checkout `/tmp/feedmine-t1-base`. Codex assumiu a execução após OMP. Plano: `docs/superpowers/plans/2026-10-09-omp-proximos-passos.md`.

## T1 — Resultados executados

- Base rastreada isolada, com cópias do trabalho 3R11A preservadas fora dos diretórios compilados.
- OMP: package describe/build PASS; alvo de testes inicialmente não compilava. Três correções de testes preservadas: existential FeedConnector, helper static sem captura de XCTestCase e testable import Editorial.
- Codex: teste sliding-window falhava (0 requests iniciadas em vez de 2) e pendurava, por barreiras liberadas após quantidade fixa de yields. Agora aguarda eventos reais, limita a espera e libera trabalho em caso de timeout: 5 testes de aquisição / 0 falhas.
- Primeira suíte completa executada: 813 testes / 21 falhas (2 unexpected). As expectativas antigas não incorporavam primaryLink, publicação parcial de cold, limite visual mínimo e clamp de datas futuras. Fixture RSS tinha ampersands sem escape; inspeção SwiftUI precisava atravessar o wrapper do badge. Corrigidos os testes, preservando as regras de produto novas.
- Suíte após correções: 813 testes / 0 falhas; build PASS.
- Suíte incluindo prova T2 de prefetch explícito: 814 testes / 0 falhas, 33,43 segundos.
- App: integração inicial 7 testes / 4 falhas. Fonte única no contexto main não produz adjacência; fixtures agora usam duas fontes. Composição respeita timeout injetado, mantendo 20 segundos apenas para configuração padrão. Recuperação espera publicação real se retry agendado já iniciou launch. Integração atual antes de novos testes T2: 7 / 0 falhas.
- XCUI encontrou consulta limitada a Other: cards novos com externalURL são botões. SQLite confirmou histórico/checkpoint preservado; teste agora consulta identidade de publicação em qualquer tipo de elemento. Rodada completa atual PASS: 10 testes de integração + 2 XCUI / 0 falhas, `/tmp/feedmine-codex-t1-t2-verified.xcresult`. T1 concluído.

## T2 — Provas

Mídia: 6 testes / 0 falhas. Inclui deadline enquanto download está suspenso, recuperação após timeout/cooldown, falha permanente text-only e lista editorial explícita com deduplicação sem baixar revisão alheia.

Novas provas de app PASS: cold se recupera sem gesto; background cancela retry; fonte rápida publica enquanto outra permanece suspensa; ao liberar a segunda fonte, reserva parada contém anchor + 16 cards e adjacência alternada.

## Evidências

Logs completos: `~/Documents/feedmine-evidence/2026-10-09/t1/` (OMP) e `~/Documents/feedmine-evidence/2026-10-09/codex/` (Codex). Arquivos xcresult ficam em `/tmp/feedmine-codex-*.xcresult`. Dados de dispositivo físico, desempenho energético e release não foram comprovados.

Não houve push nem integração em main.

T2 residual corrigido com RED→GREEN: tracking churn na URL principal não republica; query significativa continua material. Domain agora possui ContentLocatorIdentity e MaterialContentIdentity usados por Editorial/Publication; Syndication mantém a mesma normalização anterior via adapter. Não há mudança nas URLs de transporte nem nos IDs de guid opacos. Suíte após a correção: 815 testes / 0 falhas (inclui uma prova T3 de lookup exato); testes iOS atuais 12 / 0 falhas. T2 concluído no simulador; dispositivo físico continua pendente do fechamento T8.
