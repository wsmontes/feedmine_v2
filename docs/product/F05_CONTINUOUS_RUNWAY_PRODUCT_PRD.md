# F05 — Continuidade do feed e exploração progressiva
## PRD de produto e critérios de aceitação — revisão 1, 2026-10-10

**Estado:** contrato de comportamento acordado com o product owner, informado por revisão do código atual. **Não é prova de implementação, não altera B03/B04 nem aprova o release.**  
**Autoridade:** [norte](PRODUCT_NORTH_STAR.md), [PD-3, PD-5, PD-8, PD-9](PRODUCT_DECISIONS_2026-10-09.md), [INV-04, INV-05, INV-08, INV-09, INV-16, INV-17](../architecture/PRODUCT_INVARIANTS.md), [F06](F06_SACRED_FEED_CARD_READINESS_PRD.md), [benchmark B03/B04](DISCOVERY_ACCEPTANCE_BENCHMARK.md), [diagnóstico F05](../reviews/F05_RUNWAY_CONTINUITY_DIAGNOSIS_2026-10-10.md).

> **Promessa:** o leitor consome um feed local, contínuo e estável enquanto o FeedMine antecipa a reposição e amplia a exploração de fontes. Capacidade, velocidade e prioridade variam conforme fatos; nenhum tamanho fixo de fila, página, janela ou catálogo determina o horizonte editorial.

## 1. Comportamentos obrigatórios

**F05-R1 — Apresentar o local antes da rede.** Reabrir, voltar de uma leitura ou estar offline deve apresentar imediatamente a melhor sequência válida já preparada localmente. A UI nunca aguarda HTTP para manter visível o que já estava admitido. Primeira instalação sem conteúdo é exceção honesta, com progresso real, não suposta instantaneidade.

**F05-R2 — Runway relativo ao consumo e ao custo de reposição.** Antecipar publicação e mídia suficientes para o ritmo *observado* de avanço, a variabilidade de latência, a diversidade editorial necessária e a folga operacional do dispositivo. Se a pessoa percorre mais rápido, a prioridade de reposição aumenta; com consumo lento e runway confortável, capacidade pode ser usada para aquisição exploratória, mídia e retenção. Não presumir que uma reserva de 16/20/50 cards compra qualquer tempo mínimo. Limites por chamada para evitar pressão física podem ser finitos; não são metas editoriais nem garantia de continuidade.

**F05-R3 — Não esperar a fila esvaziar.** O primeiro lote visível não encerra a produção. Reposição é proativa e baseada em observações de consumo, custos reais e recursos. Não exigir gesto adicional para "acordar" o sistema quando já existe demanda e uma oportunidade válida de trabalho. O resultado de trabalho de fundo nunca injeta novos cards no prefixo admitido sem avanço legítimo do leitor ou transição deliberada.

**F05-R4 — Um candidato pendente sai da fila, sem interromper a publicação.** Quando o próximo candidato ainda depende de imagem, link, texto, mídia ou validação, ele **sai imediatamente da fila pronta para publicar**. Não fica na cabeça da fila, não reserva posição e não retarda os prontos que vêm depois. Retém identidade e fatos de preparação nos responsáveis existentes. Quando puder ser consumido, volta a concorrer à seleção editorial futura — sem reivindicar posição antiga. Não converter timeout de rede nem contagem mágica de tentativas em degradação automática. Um link morto não é card pronto; texto puro é apresentação intencional ou decisão respaldada por evidência. Isto estende PD-5/PD-9/INV-17, **não autoriza construir outra fila paralela**.

**F05-R5 — O catálogo completo continua sendo explorado.** Runway saudável não significa que aquisição terminou. Na capacidade permitida, ampliar progressivamente a cobertura das fontes elegíveis, inclusive as ainda não visitadas, sem monopolização eterna pelas favoritas. Revisita das melhores fontes pode ter prioridade, mas isso não condena outras a nunca receberem oportunidade. Restrição explícita de idioma determina elegibilidade; assunto/lugar normalmente orientam ordem e relevância. A aquisição exploratória usa **o mesmo pipeline e os mesmos donos**, sem dois motores competindo. Uma rodada limitada não equivale a um universo limitado.

**F05-R6 — Um trabalho lento não bloqueia os demais.** Feeds, imagens e preparação independentes podem progredir concorrentemente dentro do orçamento real do dispositivo/rede. Uma fonte lenta, temporariamente offline ou em backoff não congela as fontes saudáveis, a UI, o cursor ou a publicação de conteúdo já válido. Retentativas oportunistas usam classificação de falha, custo e estado do sistema, sem polling incessante ou repetição indefinida na mesma tentativa. Falha local não é evidência automática de escassez remota.

**F05-R7 — Proteger a leitura e aproveitar os recursos.** Runway visível e seu abastecimento têm prioridade sobre trabalho especulativo. Em aparelhos com folga real de disco, rede, memória e energia, aumentar exploração/preparação/retensão útil; sob pressão, reduzir custo proativamente sem destruir gratuitamente conteúdo aproveitável. Considerar sinais reais do iOS; não prometer execução livre após suspensão do aplicativo.

**F05-R8 — Contexto e história continuam estáveis.** Trocar A→B reprioriza trabalho futuro; voltar a A reaproveita edição, assets, seleção preparada e âncora válidos. Callbacks de A não contaminam B. Publicação congelada não muda por imagem atrasada, refresh nem edição externa. Falta verdadeira de oferta offline pode ser comunicada no final, preservando histórico, em vez de apagar a sessão.

## 2. Estados que não podem ser confundidos

- **Alvo de catálogo elegível** ≠ fonte já contactada ≠ fonte que entregou histórias válidas.
- **Supply canônico adquirido** ≠ história pronta para publicar ≠ história publicada em reserva ≠ card admitido ao leitor.
- **Pendente recuperável** ≠ item rejeitado definitivamente ≠ fonte temporariamente em backoff ≠ universo esgotado.
- **Janela operacional examinada** ≠ fim do catálogo ou fim de todas as histórias elegíveis.
- **Runway saudável** ≠ autorização para interromper toda descoberta futura.
- **Sem resposta do iOS durante suspensão** ≠ fracasso do produto: a obrigação é aproveitar as oportunidades concedidas, não inventar serviços de background.

Os responsáveis existentes devem preservar estas distinções. Proibir soluções que resolvam um estado ficticiamente alterando outro (por exemplo, marcar imagem pendente como definitivamente ausente para retirar o bloqueio).

## 3. Cenários de aceitação da Frente 05

**F05-01 — B03 real sem alteração da régua.** Corpus controlado com no mínimo 5.000 itens elegíveis, avanço efetivo de 30 minutos a 1 card/s, rajadas de até 3 cards/s durante 20 s a cada cinco minutos, medindo posições e cards realmente distintos. **Nenhum fim artificial**, repetição de cards ou congelamento de ≥1 segundo por falta de runway quando existe oferta. Não declarar PASS por simulação curta ou por deixar app aberto sem scroll.

**F05-02 — Alterar velocidade do leitor.** Durante o mesmo ensaio, consumo lento, rápido e rajadas; evidenciar mudança da prioridade e do runway preparada a partir das observações reais e do custo da reposição, sem limite fixo determinando a disponibilidade futura.

**F05-03 — Primeiro candidato pendente.** Primeira história aguarda imagem indefinidamente; as seguintes têm link, texto e mídia prontos. Elas são publicadas sem aguardar a primeira, sem posição reservada. Posteriormente imagem chega e a história suspensa é reconsiderada sem reordenar cards já apresentados. Repetir com link temporariamente inválido e com recurso comprovadamente inutilizável.

**F05-04 — Cobertura progressiva durante runway saudável.** Fonte(s) já conhecidas abastecem a reserva; existem muitas outras elegíveis ainda não contactadas. Com tempo e recursos permitidos, o sistema contacta progressivamente novas fontes sem consumir o runway, sem ficar apenas nas mesmas primeiras N. Registrar alvos elegíveis, contatados, resultados, elegibilidade e progresso entre oportunidades.

**F05-05 — Resiliência heterogênea.** Feeds lentos, resposta vazia/304, erro transitório, duplicação, mídia tardia e fontes sadias. Uma falha não interrompe as demais, nem confunde ausência local/erro com escassez de todo o catálogo. Reconsideração futura não é busy loop.

**F05-06 — Pressão e folga de recursos.** Mesmo corpus com rede rápida/lenta, restrição de dados, bateria/temperatura/memória/disco diferentes; documentar o ritmo adaptado e estabilidade de consumo, sem impor permanentemente o perfil do pior aparelho a todos os usuários.

**F05-07 — Filtro, retorno, offline e restauração.** A→B→A, pausa/reabertura, rede cortada durante leitura e reentrada com assets locais. Preservar âncora, histórico e trabalho reutilizável sem atrasar o primeiro paint pela rede.

**F05-08 — B04 junto ao runway.** Novos cards, imagem pronta, atualização de artigo e fonte lenta chegando com o leitor parado ou rolando. Confirmar identidade, geometria física, posição e âncora **inalteradas** sem ação explícita.

**F05-09 — Nenhuma perda silenciosa de candidatos.** Os candidatos que saíram da fila pronta por problemas recuperáveis continuam descobríveis, com resultados de tentativa identificáveis; quando retornam, são avaliados pelas regras editoriais atuais. Uma fila finita não exclui candidatos permanentemente.

## 4. Diagnóstico específico da V2 inspecionada

**A favor:** `RunwayPolicy` combina consumo em cards/s com latência de reposição p95, `RunwayController` diferencia pressão e exaustão local, `FeedRunwayDriver` coordena efeitos causais; `RunwayAcquisitionCycle` executa alvos em paralelo e oferece `selectedSourceCoverage` com runway saudável. `FeedSession` só admite extensão do leitor por avanço válido.

**Lacunas observáveis:**

1. Em `FeedMineApp/FeedMineApp/AppComposition.swift`, `presentationBounds` usa 8 atrás/16 à frente, e `resources` fornece `reserveCards: 16`, `examinedCandidateCapacity: 32`, probe 32/256, lote externo finito, além do `catalogOrDevelopment(limit: 64)` inicial. Alguns são limites físicos aceitáveis; **não foi demonstrado que o tamanho de reserva acompanha de fato o consumo/custo e que a janela inteira progride pelo universo elegível**.
2. `RunwayPolicy.evaluate` tem política medida de p95, mas o piso `reserveCards` vem de um 16 fixo na composição; a proteção de primeira sessão não pode se transformar em regra permanente de produto.
3. `MediaReadiness.presentation(for:)` retorna `.textOnly` quando imagem ainda não está pronta. `AppComposition.prepare` monta os inputs de **todos** os `orderedCandidates` sem excluir pendências. `LocalProductionSlice.run` prepara e publica o lote inteiro após seleção; não demonstra a saída imediata do candidato pendente da fila pronta nem sua futura reconsideração (PD-9/F06).
4. A execução de cobertura `selectedSourceCoverage` percorre alvos das **fontes selecionadas pela sessão**, não o catálogo integral de aproximadamente 77.443 entradas. Provar alcance global exige a ligação F01 catálogo → elegibilidade → alvos → oportunidades, sem uma segunda infraestrutura.
5. `HiddenTailMaintenance` pode substituir uma cauda publicada ainda não vista; isso merece reconciliação explícita com a PD-5 revisada (imutabilidade após publicação). **Não** resolver essa tensão introduzindo mutação no feed admitido.
6. O ensaio histórico de aproximadamente 135 cards em quatro minutos com poucas fontes **não** certifica o B03 de 30 minutos. Não atribuir causa única sem trace de onde a oferta acabou.

## 5. Execução em ordem de impacto

1. **Instrumentar/provar o percurso já existente** em corpus representativo: cobertura ao longo de oportunidades, readiness por candidato, crescimento do runway, momento da publicação, admissão do leitor e intervalos de falta de conteúdo. Não inventar métrica de sucesso substituta a B03.
2. **Corrigir primeiro bloqueio/perda de candidatos pendentes** no caminho de preparação/seleção atual, de modo que os outros progridam e os suspensos possam retornar — sem criar segunda fila ou outro scheduler.
3. **Fazer a configuração refletir o runway relativo**, distinguindo limites por operação de reserva/estratégia. Evitar simplesmente trocar 16 por 40 ou 100; adotar fatos de consumo/reposição já existentes.
4. **Garantir cobertura progressiva do universo elegível** e justiça entre contatos, reaproveitando `AcquisitionPlanner`, `AcquisitionCoordinator` e drivers existentes.
5. **Executar B03 e B04 integralmente** em condições apropriadas, inclusive aparelho físico, registrando FAIL/NOT_RUN/BLOCKED conforme evidência real. Não declarar PASS apenas por testes unitários verdes.

**Critério de saída:** feed que acompanha consumo prolongado sem fim artificial ou perturbação visual, alimentado por aquisição progressiva de fontes elegíveis e preparação independente por card, demonstrado pelo benchmark congelado. **Estado atual: ainda não comprovado.**

## 6. Ganchos de jornada para a segunda onda

A continuidade do runway é necessária também quando a pessoa usa [busca F11](F11_UNIFIED_SEARCH_RESULTS_UX_PRD.md), [biblioteca e contextos F16](F16_PERSONAL_LIBRARY_SMART_FEEDS_UX_PRD.md) e [volta/novidades F20](F20_RETURN_FRESHNESS_LIFECYCLE_PRD.md). A experiência de [podcast F15](F15_PODCAST_PLAYBACK_CONTINUITY_UX_PRD.md) não deve disputar o scroll nem exigir bytes completos de áudio para admitir cards. O [mapa de impacto F11–F20](PRODUCT_SPEC_DEPENDENCIES_F11_F20.md) define provas adicionais sem mudar o teste B03 de 30 minutos ou os invariantes da fila publicada.
