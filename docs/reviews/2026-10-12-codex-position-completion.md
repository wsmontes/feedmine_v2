# Execução Codex — bloqueio de posição do PR #3

O usuário transferiu a execução ao Codex. Base: 93dd1fb0, checkout limpo, sem builds ativos.

## Causa e desenho

O protótipo de espaçador guardava IDs/alturas de todo o histórico e tratava remoção de cauda como remoção acima. A regressão de cauda falhou antes da mudança. Substituição: uma testemunha visível que sobrevive à mudança de IDs, em memória. A diferença de coordenada de conteúdo (frame + offset) fornece o deslocamento exclusivamente de layout; um adaptador estreito ajusta o offset do UIScrollView existente, sem animação. Reprojeções não atuam. Uma correção é consumida uma vez; nova interação, nova associação ou geometria incompatível invalida a captura. Nenhum estado persistido, cache ou List novo.

## Validação exigida

- Testes de separação gesto/layout, consumo único, reprojeção e descarte.
- Percurso offline limitado já coberto por regressões existentes.
- UI com fixture de 190 itens: exigir retirada/reentrada de IDs e posição da testemunha, verificar log de mutação/correção.
- Fonte ampliada e regressões do app/pacote no SHA final.
- Nenhum merge antes de confirmar resultado visual. Logs em /tmp/codex-scroll-*.

## Execução e limites

- O antigo ledger de alturas/IDs do histórico foi removido. O cálculo retém apenas geometrias da janela atual e uma testemunha visível sobrevivente; reprojeção com IDs idênticos não gera correção.
- O adaptador atua no UIScrollView existente, sem reconstruir associação, persistir offsets ou adicionar outra lista. Eventos programáticos de correção não são gestos do leitor.
- Alvo de produto validado: iOS. A biblioteca compila em macOS, mas este adaptador UIKit não fornece compensação AppKit; não há aceite visual de um produto macOS.
- Teste de tela exige IDs admitidos realmente retirados/reinseridos, correção executada e frame da mesma testemunha no primeiro callback coerente com o offset nativo corrigido. O resíduo visual deve ficar abaixo de 1 pt. O valor não é apenas a aritmética do setter de offset.
- Isso prova a primeira geometria coerente e a posição assentada. Não é medição por câmera de cada frame físico do display.
- Primeiro alvo do app: 83 testes, 0 falhas. Leitor: 7 testes, 0 falhas na repetição; a execução anterior foi contaminada por SQLite resultCode 13 (disco cheio).
- Dois testes de poda (normal + acessibilidade máxima): 2/2, 187,558 s, resultado `/tmp/codex-scroll-derived/Logs/Test/Test-FeedMine-2026.10.12_09-11-25--0700.xcresult`.
- Prova com iPhone totalmente sem conectividade continua manual e não foi apresentada como executada.

Controle negativo: retirada temporária do ajuste nativo, mesmo teste de poda real, FAIL com resíduo 157,333 pt e nenhuma confirmação coerente. Fonte GOOD restaurada; alteração do controle não faz parte da entrega. Log `/tmp/codex-scroll-negative.log`.

## Fechamento de verificação

- Pacote final: **1241 testes, 1 pulado, 0 falhas** (`/tmp/codex-final-package.log`).
- App final com histórico fortalecido: **83 testes, 0 falhas**, 184,734 s (`/tmp/codex-completed-app.log`).
- Leitor local: **7/7**, 65,565 s; teste físico com conectividade desligada foi explicitamente excluído.
- Poda normal + fonte máxima no código final e sugestões sobre catálogo real: **3/3**, 494,405 s (`/tmp/codex-final-interaction.log`). A jornada das sugestões inclui responder/desfazer/esconder, árvore de acessibilidade, reativação e relaunch.
- Auditoria exige `measuredCorrections == appliedCount` e resíduo visual <1 pt para cada correção da corrida. O controle negativo removeu só o ajuste nativo e falhou; foi restaurado antes desta verificação.
- Revisão independente somente leitura: nenhum defeito UIKit importante estabelecido. Confirmados os limites de observação: primeira geometria coerente e quadro assentado; sem afirmação sobre cada frame físico do display.
- As provas de histórico agora acumulam IDs **realmente admitidos** por lotes distintos, exigem mais de 25 e verificam o alcance offline. O primeiro fortalecimento encontrou 105 IDs não visitados porque o teste parava ao cruzar IDs já vistos no avanço. Ajustada apenas a condição de percurso: parar quando a cabeça da janela realmente para. Resultado final verde sem mudar runtime ou reduzir a exigência.
- Gates de benchmark completos não foram reexecutados nesta execução Codex; resultados antigos não são reapresentados como resultado deste diff.
- TestFlight: o fluxo `release-testflight.sh --dry-run` recusou com exit 9 porque ASC_KEY_ID não está configurado; ASC_ISSUER_ID também está ausente nesta sessão. Nenhum upload declarado ou executado por esta frente.

Compilação Release iPhone (sem assinatura/distribuição): **BUILD SUCCEEDED**, sobre `0d38f102` (merge apenas documental após `f4bfabc2`). Log `/tmp/codex-release-build.log`. Não é archive pareado nem upload TestFlight.
