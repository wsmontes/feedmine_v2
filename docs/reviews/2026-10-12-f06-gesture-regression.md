# F06 — investigação da regressão de gesto da build 30

Base: 00b26054; fonte da compensação: f4bfabc2. Checkout isolado codex/scroll-gesture-regression. Nenhuma alteração de produto no main durante a investigação.

## Medições e causa

Oito flings rápidos, fixture com 95 itens por feed. Na base, três escritas de offset durante gesto ativo; em duas, decelerating true antes do setter e false imediatamente depois. Uma escrita durante drag ocorreu com velocidade -1368 pt/s. Regressão vermelha, sem expected failure.

A guarda isolada zera essas escritas e preserva os casos parados normal/Grande. NÃO resolve F06: o teste ampliado continua vermelho, máximo de 314,666667 pt de passo com o mesmo card visível e ambos os offsets parados. Exemplo com guarda: frame 217,666667 -> 60,333333; proofOffset e nativeOffset 1686,333333 -> 1686,333333; decelerating true. A poda durante rolagem continua alterando o layout.

A hipótese de contar offset duas vezes não explica a fórmula atual: offset = local.minY - frame.minY; logo frame.minY + offset = local.minY. Isso não garante continuidade de gesto nem impede escrita nativa indevida.

## Desenho antes de editar a troca visual

- Runtime continua sendo a única autoridade de admissão/publicação; FeedScreenStore mantém uma única apresentação canônica.
- UI toma emprestada SOMENTE a janela desenhada no começo de uma interação nativa. Esse único valor transitório fica limitado à janela existente; não guarda histórico nem decide admissão.
- Enquanto tracking/drag/deceleração/rolagem animada duram, atualizações canônicas continuam, mas a janela desenhada mantém IDs e geometria. Novas sugestões também aguardam o fim da interação; ofertas já hospedadas continuam onde estavam.
- No idle, liberar o valor visual e desenhar a apresentação canônica mais recente. A compensação faz uma medição nova dessa transição em repouso, nunca reproduz delta calculado durante gesto.
- Troca de associação, contexto, edição ou sequência de proveniência invalida a retenção visual. Desaparecimento cancela o estado.
- Nenhum List, persistência de offsets, timer ou segundo cache de conteúdo.
- Aceite: atualização canônica realmente ocorre durante gesto (não vacuidade), zero mudanças de janela desenhada/escritas/steps de layout enquanto ativo; poda e reinserção em repouso <1 pt; continuidade e sugestões/regressões pertinentes.

## Leitor real ainda na janela tomada emprestada

Uma carta desenhada pode ter saído da janela canônica durante o gesto. O Runtime emite evidência pequena, não persistida, da apresentação desenhada (contexto, edição, sequência, posição, IDs já admitidos e ordinal de input). A observação só pode rematerializar IDs dessas janelas já admitidas, do store local; outra associação ou ordinal atrasado é recusado. Nenhuma rede é iniciada por renderização.

A associação recebe a projeção local comprometida antes de aguardar o trabalho de runway. Um receipt atrasado não sobrescreve input mais novo nem converte a rejeição causal em falha do feed. A liberação visual aguarda a presença do card realmente observado; um novo gesto cancela a liberação pendente, sem aplicar delta antigo.

Revisão independente encontrou duas ligações ausentes (callback de evidência na raiz e membership canônica no callback de geometria); ambas corrigidas antes de validar o fluxo completo. Testes executados: rematerialização do card antigo e recusa de outra sequência; ordinal atrasado rejeitado; retenção até acknowledgement e descarte por outro owner. Zero falhas nos casos direcionados.

Tentativa de seleção Xcode às 14:54 nomeou o alvo de unitários em vez do alvo de UI: executou ZERO testes. Não é validação. A corrida seguinte nomeia FeedMineUITests e exige atualizações canônicas em movimento, zero mutações da janela desenhada ativa e zero escritas nativas ativas.

## Ação de card retido

A revisão de integração encontrou outra guarda duplicada em `FeedAssociation.open`: o store já validava a apresentação renderizada, mas a associação voltava a exigir pertencimento à janela canônica. A nova regressão exige poda real, abre o card ainda renderizado e recusa a mesma ação depois de encerrar a associação. Primeiro arranjo não compilou (ordem dos argumentos do evento); não contou como RED. Arranjo corrigido executou e falhou `opens=0` contra `1`, com poda confirmada. A guarda duplicada foi removida; `active` e `visible` permanecem, e o alvo continua sendo resolvido no histórico local.

## Medição exportada do fluxo completo

Bateria 14:55: 3/3 UI. Anexo `fast-fling-native-state`: janela inicial17, final25; deferredWindows45; activeWrites0; activeWindows0; activeLayoutSteps0; activeLayoutStep0; uma compensação em repouso, medida, visualResidual0. Resultados e anexos preservados em `/Users/<user>/Desktop/feedmine-f06-gesture-fix-20261012/`.

Bateria seguinte: app83/83; UI11/11 (três rolagens, sugestões em catálogo real e sete leituras). Nas sugestões: responder/desfazer/esconder 132,083328 ->132,083328 pt. A leitura de card retido é alteração posterior e recebe bateria nova; esses números anteriores não são usados como validação desse novo ramo.

As cinco falhas intermediárias do pacote eram asserções estáticas sobre a estrutura anterior. O contrato continua uma única apresentação canônica e nenhuma execução por renderização; foram descritos explicitamente o callback de evidência, o ordinal e o bit visual, e a limpeza no desaparecimento. O pacote foi reexecutado integralmente:1245, um pulado, zero falhas. O corpus ausente foi copiado sem mutação do original; os dois skips de corpus da primeira tentativa não são parte do resultado final.

Limites: iPhones indisponíveis na consulta `devicectl`; execução visual no device dedicado FeedMine OMP. Não houve sessão humana de VoiceOver, teste de conectividade global desligada, nem execução integral do benchmark B04 nesta investigação. Nenhum oráculo de produto ou critério de estabilidade foi afrouxado.

Correção do arranjo da ação: em suíte, uma única oportunidade não garantia poda; a rematerialização `.restore` na mesma sessão ativa também é intencionalmente recusada (não serve de arranjo). Nenhuma dessas falhas foi tratada como defeito de produto ou GREEN. O arranjo final usa o mesmo recurso de gerações distintas do teste de navegação longa, produz reserva antes de admitir e exige o ID antigo realmente fora da janela canônica. Restaurada temporariamente somente a guarda antiga de `open`, o arranjo final executou e falhou `opens=0` contra `1`, com a pré-condição de poda satisfeita; a guarda correta foi restaurada antes da bateria final. Nenhuma expectativa de poda foi retirada.

## Toque sem movimento entre a rolagem e a troca idle

O pending deve ser cancelado ao iniciar outro gesto. Porém a última medição da janela ainda desenhada é válida no espaço de conteúdo e pode ser a única testemunha disponível se o toque interromper a rolagem sem mover conteúdo. A transição tracking descarta o pending/visualWitness, conserva apenas essas amostras limitadas e nunca escreve offset; desaparecimento/escopo descarta tudo. O teste iOS usa UIScrollView real e fase explícita: offset500 durante tracking; após idle e retirada acima, offset200 com o mesmo card de volta a y100. É verificação da ponte UIKit, não medição de um dedo físico.

## Acknowledgement idle sem gesto fabricado

Se o leitor termina a interação numa carta já podada da apresentação canônica, a UI pede explicitamente uma reconciliação com a evidência Runtime da janela ainda desenhada. O modo apenas rematerializa conteúdo local e confirma a posição; não submete outra oportunidade ao runway, não conta exposição, não faz growth, não agenda retries nem executa aquisição. A guarda vale também no caminho de erro. O ordinal recusa acknowledgement atrasado; owner/contexto/edição/proveniência continuam validados. A identidade lembrada serve para escolher o card, nunca como prova de estabilidade em pixels.

Teste `testRenderedPositionReconciliationDoesNotEnterRunwayOrAcquire`: âncora realmente muda, snapshot inteiro do runway não muda, chamadas HTTP dos dois transportes permanecem zero. Executado, verde. Revisão independente final apontou o retry no catch; corrigido antes da bateria final. Teste UIKit do toque sem movimento também verde (ReadingCompositionTests6/6).

## Seleção final de UI: prova fisicamente offline não aplicável

A seleção inteira de ReadingSurfaceUITests incluiu `testStoredContentIsReadableWithTheDeviceActuallyOffline`, que exige intervenção física/MODO AVIÃO e um namespace previamente semeado. No simulador conectado dedicado, o teste recusou a alegação offline. É erro de seleção do executor, não regressão de leitura nem PASS de offline. O resultado dessa corrida será preservado, e a seleção automatizável exclui somente esse caso; o teste/manual/oráculo não foi alterado.

## Evidência final da rolagem (fonte congelada desta correção)

Pacote1246 testes,1 pulado,0 falhas (61,999s). App85/85 (197,916s). As três UI de rolagem passaram: flings30,981s; fonteGrande179,179s; fonteNormal101,841s. Na execução final de flings, IDs mudam17→25 e há19 atualizações canônicas adiadas durante interação; activeWrites/activeWindows/activeLayoutSteps=0. Esse caso não precisou compensação idle (contador0), portanto seu residual0 não é alegado como medição de compensação. Na fonte normal, o anexo após poda tem corrections1,measured1,visualResidual0,activeWrites0,activeWindows0; retorno da carta e repouso são exigidos separadamente. FonteGrande também exige correções medidas, não apenas identidade/placement.

Release generic iPhone: BUILD SUCCEEDED, assinatura desativada; é compilação, não distribuição nem execução em aparelho. A imagem pós-reinserção com fonteGrande foi inspecionada. Bateria ampla com o caso manual incluído saiu exit65 exclusivamente nas duas asserções de precondição desse caso (rede ativa/namespace não semeado); app85 e demais UI passaram. A seleção automatizável de leitura é registrada separadamente abaixo.

Seleção final automatizável de ReadingSurfaceUITests, excluindo exclusivamente o caso físico/manual:7/7, TEST SUCCEEDED (70,466s). Nenhuma edição de critério para obter esse resultado.
