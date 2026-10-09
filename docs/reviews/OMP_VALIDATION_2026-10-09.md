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

Logs completos: `~/Documents/feedmine-evidence/2026-10-09/t1/` (OMP) e `~/Documents/feedmine-evidence/2026-10-09/codex/` (Codex). Arquivos xcresult ficam em `/tmp/feedmine-codex-*.xcresult`. Dispositivo físico e desempenho energético permanecem pendentes; Release no simulador compilou.

Os commits foram enviados à branch `codex/omp-plan-execution`; não houve integração em main. O GitHub bloqueou o upload LFS por cota excedida. O push do código usa `GIT_LFS_SKIP_PUSH=1`: o catálogo está preservado localmente, mas seu objeto LFS ainda precisa ser publicado antes de um clone remoto conseguir montar o bundle.

T2 residual corrigido com RED→GREEN: tracking churn na URL principal não republica; query significativa continua material. Domain agora possui ContentLocatorIdentity e MaterialContentIdentity usados por Editorial/Publication; Syndication mantém a mesma normalização anterior via adapter. Não há mudança nas URLs de transporte nem nos IDs de guid opacos. Suíte após a correção: 815 testes / 0 falhas (inclui uma prova T3 de lookup exato); testes iOS atuais 12 / 0 falhas. T2 concluído no simulador; dispositivo físico continua pendente do fechamento T8.

## T3 — Catálogo integrado

SQLite real empacotado em Copy Bundle Resources e armazenado via LFS. O pointer local contém checksum/tamanho esperados; teste no bundle comprova os bytes reais (SHA-256 por streaming), 77.443 fontes e quatro defaults com IDs estáveis. Lookup exato com parâmetros preserva request_url e não interpreta key como SQL. Recurso ausente/corrompido gera erro explícito no loader; Release não usa fallback BBC silencioso.

Provas: package 815/0; app integração 12/0 (`t3-app-green.txt`). Os dois novos testes cobrem recurso/checksum e falhas de distribuição. Release simulator build PASS (`t3-release-build.txt`). T3 concluído.

## T4–T7 — Implementação e provas

- T4: seleção de fontes persistida e versionada; contextos main/fonte/busca local com checkpoints separados. A→B→A restaura edição e posição offline. Busca usa dados locais e consultas limitadas; a última fonte não pode ser removida. A UI permite escolher fontes e salvar cards.
- T5: high-water de leitura monotônico; manutenção substitui somente a cauda não vista, arquiva publicações anteriores e preserva prefixo, posição e identidade. Transação rejeita lease vencida, alterações de disponibilidade ou memberships durante preparação. Lookup limitado às origens futuras encontra revisões mesmo atrás de novas entradas no head canônico.
- T6: uso de mídia e bookmarks persistidos. Pressão de disco preserva janela atual e assets salvos, distingue leitura recente de futuro não visto e contabiliza apenas exclusões efetivamente realizadas. Falha na remoção não infla bytes recuperados.
- T7: projeção reutiliza cards imutáveis da janela da mesma edição/contexto. Prova com PNG real: 100 atualizações passaram de 101 decodes para 1 decode; thumbnail 300×200, 240.000 bytes. Medidas de CPU/RSS pertencem ao processo de testes macOS, não representam consumo do iPhone. Fixture de 100 mil registros valida paginação por índice sem OFFSET; catálogo real tem 77.443 fontes. Reserva 16 é piso: estimativa com 8 cards/s e latência de 5 s calcula 48.

Revisão final identificou dois problemas, corrigidos com regressões RED→GREEN: cold bootstrap cancelado ainda poderia publicar depois de trocar contexto; disponibilidade/membership poderiam mudar sem alteração de revisão. A publicação cold agora exige autoridade ativa e a substituição da cauda revalida fatos dentro da transação.

## T8 — Fechamento e pendências

Código testado: `f8eb67e`. A rodada anterior de iOS passou 15 testes de integração + 3 XCUI, sem falhas (`t8-app-reviewed.txt`). Release simulator compilou (`t8-release-final.txt`). A repetição final do pacote e do iOS está registrada em `t8-package-final.txt` e `t8-app-final-code.txt`; os resultados finais são acrescentados abaixo após os comandos terminarem.

Pendências reais: iPhone 14 Plus e iPhone 15 aparecem indisponíveis em devicectl; falta validação em hardware de scroll prolongado, memória, energia, térmica e rede. Falta publicar o objeto do catálogo LFS após regularizar a cota ou mudar a distribuição. Não houve merge em main. O transporte 3R11A original permanece preservado e fora da compilação deste worktree; seu gate não foi implementado nesta rodada.

Resultados finais executados sobre o código `f8eb67e`: `swift test` PASS, 827 testes / 0 falhas, 21,008 s; `xcodebuild test` PASS, 15 integração + 3 XCUI / 0 falhas, iPhone 16 simulator iOS 26.5, `/tmp/feedmine-codex-final-code.xcresult`. Logs `t8-package-final.txt` e `t8-app-final-code.txt`. `git diff --check` PASS. Commits de documentação posteriores não alteram o código testado.
