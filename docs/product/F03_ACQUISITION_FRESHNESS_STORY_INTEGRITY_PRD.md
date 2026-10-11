# F03 — Aquisição, atualidade e integridade das histórias
## Especificação de produto e experiência (PRD) — revisão 1, 2026-10-10

**Estado:** decisões de experiência consolidadas com o product owner; **não** é aprovação da implementação, resultado de teste ou desenho de arquitetura.
**Autoridade:** [Norte de produto](PRODUCT_NORTH_STAR.md), [dez frentes](PRODUCT_AUDIT_10_FRONTS.md), [benchmark de aceitação](DISCOVERY_ACCEPTANCE_BENCHMARK.md), [decisões de produto](PRODUCT_DECISIONS_2026-10-09.md), [invariantes](../architecture/PRODUCT_INVARIANTS.md). Os gates B01–B06 permanecem vigentes e inalterados.

> **A experiência em uma frase:** o FeedMine encontra histórias legítimas na internet heterogênea, preserva o que vale a pena descobrir, apresenta conteúdo que pode realmente ser consumido e evita que o leitor receba notícia vencida, paywall inesperado ou a mesma matéria repetida sob cinco nomes.

## 1. Promessa e limite da frente

A Frente 03 responde à pergunta: **a história chegou, continua editorialmente válida e leva a uma experiência real de leitura, visualização ou reprodução?** Ela não deve medir sucesso só por resposta HTTP, número de itens traduzidos ou quantidade de cards publicados.

A internet real contém feeds bons, incompletos, inconsistentes, lentos e defeituosos. O FeedMine deve absorver essa irregularidade **sem transferi-la desnecessariamente ao leitor**, respeitando segurança, autoria, direitos de acesso e recursos do dispositivo.

**Dentro da F03:** aquisição de histórias; identidade; preservação de conteúdo elegível; frescor e datas; abertura/consumo; acessibilidade econômica do conteúdo (gratuito versus paywall); duplicações de uma mesma obra entre fontes; recuperação quando fontes falham.

**Conexões, sem duplicar responsabilidades:** F01 descobre/amplia as fontes; F02 estabelece a primeira descoberta; F04 equilibra assuntos, fontes e relevância editorial; F05 mantém o runway; F06 apresenta cards; F08 executa leitura e ações. Os requisitos desta frente devem aparecer na jornada de ponta a ponta com essas frentes, **não** justificar um segundo selecionador, cache, scheduler, pipeline ou mecanismo de expiração.

## 2. Decisão A — a idade sempre conta, com peso contextual

**Regra aprovada:** a idade **sempre influencia** a prioridade de apresentação. O que varia é a intensidade: histórias cujo valor depende de novidade envelhecem depressa; artigos explicativos e outros conteúdos duráveis envelhecem mais lentamente. A qualidade excepcional pode compensar a idade, mas **nunca fazê-la contar como zero**.

- Uma notícia de uma semana atrás não deve ser apresentada como novidade recente simplesmente porque acabou de chegar ao aplicativo.
- Um artigo de astronomia com cinco anos pode continuar excelente; ainda assim, em condições comparáveis de qualidade e pertinência, o conteúdo mais recente normalmente tem vantagem.
- O assunto **isoladamente** não determina a regra. Uma notícia sobre astronomia é temporalmente diferente de uma explicação atemporal sobre buracos negros.
- O tratamento da idade considera a **natureza da história** e seu contexto editorial, não uma data de validade única para toda a internet.
- **Momento de aquisição não é data de publicação.** Consultar hoje um feed que republica um item antigo não o transforma em conteúdo novo.
- Uma **alteração material verificável** pode justificar apresentar uma nova versão; uma troca superficial de data, parâmetro de URL ou metadado não pode fabricar novidade.
- Datas desconhecidas, conflitantes, futuras ou pouco confiáveis não devem ser arbitrariamente exibidas como "hoje" nem permitir alegação falsa de novidade. A incerteza deve afetar a confiança editorial e a apresentação de forma honesta.

**Resultado esperado:** o feed mistura atualidade e profundidade sem confundir histórias antigas valiosas com notícias recém-ocorridas.

## 3. Decisão B — priorizar acesso real, especialmente sem paywall

**Regra aprovada:** acessibilidade efetiva do conteúdo é um critério **forte** de prioridade editorial. Como o FeedMine abre a leitura em um navegador cuja sessão pode não estar autenticada, um link formalmente válido não garante que a pessoa conseguirá ler.

Preferência no **fluxo de descoberta automática**, sempre considerando a qualidade e a pertinência:
1. **Conteúdo de boa qualidade, gratuito e efetivamente acessível:** prioridade alta.
2. **Acesso incerto ou variável:** pode aparecer, mas não deve dominar a experiência.
3. **Conteúdo conhecido como bloqueado por assinatura:** prioridade muito baixa na descoberta automática.

A classificação ideal é **por artigo**, não por marca ou prestígio do publicador. Um veículo com assinatura pode publicar conteúdo aberto; um site habitualmente gratuito pode bloquear artigos específicos. Distinguir, quando houver evidência: conteúdo aberto, cadastro requerido, acesso limitado por leituras, assinatura e situação desconhecida. **Não afirmar certeza quando não for possível verificá-la.**

Regras de experiência:
- O FeedMine **não tenta contornar paywalls** nem promete acesso que não possui.
- Uma chamada à assinatura após o toque, quando previsível, representa uma falha de qualidade da **descoberta automática**, mesmo que a abertura técnica tenha funcionado.
- A preferência por leitura aberta deve favorecer também fontes independentes de qualidade; **gratuidade sozinha não substitui credibilidade ou relevância**.
- Conteúdo que está integralmente consumível de maneira legítima dentro do aplicativo pode cumprir a promessa de acesso mesmo quando o destino externo seja limitado; não inferir que um resumo equivale ao texto completo.
- Não bloquear ou apagar da biblioteca local uma matéria que a pessoa já salvou/seguiu apenas por sua condição de assinatura. Política de descoberta automática não deve destruir histórico ou escolha explícita.

**Resultado esperado:** a descoberta gera mais leituras concluíveis e menos cliques frustrados. A condição de acesso deve ser tratada como sinal editorial, não como julgamento de qualidade do jornal.

## 4. Decisão C — nenhum card sem consumo válido

**Regra discutida e incorporada:** nenhum card deve ser apresentado como história pronta se não houver uma **ação real e coerente** que permita consumir o que promete: abrir o artigo correto, ler legitimamente conteúdo integral já disponível no aplicativo, assistir à mídia ou reproduzir áudio correspondente.

- Um link sintaticamente válido que aponta a erro, destino evidentemente incorreto ou recurso não consumível **não atende** à promessa.
- A identidade e a origem da história não podem se perder em redirecionamentos, URLs de rastreamento e variações triviais.
- Se a fonte só oferece resumo e o texto externo está indisponível, **não mascarar o resumo como matéria completa**.
- Histórias incompletas ou temporariamente impossíveis de preparar não devem ser transformadas em cards quebrados para inflar a oferta.
- A ausência de imagem, por si, **não invalida** uma boa matéria: a apresentação textual é legítima, desde que a experiência de consumo exista.
- Ao regressar da leitura, preservar a continuidade da sessão e a posição (F08/F05).

Não é possível prever todas as falhas transitórias de sites externos. O compromisso é **não publicar defeitos detectáveis como se fossem conteúdo íntegro**, comunicar limites reais quando apropriado e evitar que a falha de um destino prejudique as outras fontes.

## 5. Decisão D — suprimir republicações; preservar perspectivas independentes

**Regra aprovada:** a mesma matéria publicada ou sindicada por vários sites deve aparecer como **uma descoberta**, não como cinco cards. Porém, cinco análises independentes do mesmo acontecimento **podem ser cinco histórias diferentes** e não devem ser eliminadas só porque falam do mesmo fato.

- A deduplicação deve funcionar **entre diferentes fontes**, não apenas entre entradas de um feed.
- URLs distintas, parâmetros de rastreamento, redirecionamentos ou republicação autorizada não devem criar falsas descobertas da mesma obra.
- A publicação original, sua autoria e a fonte pela qual foi descoberta devem ser tratadas com honestidade; não atribuir uma obra a quem apenas a redistribuiu.
- Não reduzir diversidade de opinião por semelhança temática, título parecido, assunto comum ou cobertura de um mesmo evento.
- Mudanças **materiais** numa matéria seguem as regras vigentes de identidade/versionamento (PD-1); modificações cosméticas não simulam uma nova obra.
- Se a identidade comum é incerta, evitar deduplicação agressiva que apagaria cobertura independente; registrar ambiguidade e verificá-la com corpus rotulado.

**Resultado esperado:** a pessoa não lê repetidamente o mesmo texto, mas consegue descobrir interpretações distintas de um acontecimento.

## 6. Decisão E — não perder silenciosamente histórias elegíveis

A ingestão pode recusar dados inválidos ou perigosos; o produto não pode tratar todos os descartes como sucesso invisível.

- Fontes saudáveis continuam contribuindo mesmo quando outras falham, atrasam, redirecionam ou entregam formatos defeituosos.
- Uma história **elegível e recuperável** não deve desaparecer silenciosamente por variação trivial de protocolo, HTML, charset, identidade ou data.
- Quando a integridade mínima não pode ser estabelecida, o sistema pode deixar de publicar aquele item, mas a razão precisa ser identificável em diagnósticos/evidência de teste.
- A seleção automática não deve confundir **fonte contactada**, **fonte traduzida**, **história elegível**, **história publicada** e **história efetivamente consumível**. Números de transporte não substituem sucesso percebido.
- O trabalho de aquisição e preparação continua proativamente para manter o runway local, sem reorganizar o que o leitor já está vendo.

**Resultado esperado:** robustez diante de fontes reais, sem maquiar escassez ou sacrificar a experiência por volume de cards.

## 7. Jornadas obrigatórias de aceitação

**US-01 — Notícias versus conteúdo durável.** Dado um corpus com notícias antigas, notícias recentes e artigos duráveis antigos de qualidade, a seleção penaliza idade em **todos**; penaliza fortemente notícias envelhecidas; admite artigos duráveis mais antigos quando justificáveis. O teste verifica que a matéria baixada hoje **não herda** a data de hoje.

**US-02 — Atualização legítima.** A mesma URL ou obra com metadado alterado superficialmente não cria descoberta nova. Uma atualização de conteúdo substancial é reconhecida como revisão, seguindo PD-1.

**US-03 — Leitura aberta.** Dadas matérias comparáveis em qualidade e relevância, a descoberta privilegia as que podem ser lidas sem assinatura. Caso uma fonte tenha tanto artigos pagos quanto abertos, não classificar automaticamente todos de modo idêntico.

**US-04 — Paywall variável e desconhecido.** Testar artigos abertos, restritos, com cadastro, limitação de leitura e classificação incerta. O produto não contorna bloqueios nem representa acesso desconhecido como garantido. A fonte premium não domina injustificadamente o feed aberto.

**US-05 — Card consumível.** Abrir cards reais com destino externo, texto integral legitimamente disponível ou mídia reproduzível; conferir o conteúdo de destino. Incluir URL ausente, redirecionamento defeituoso, feed apenas com resumo e mídia que falha.

**US-06 — Duplicata entre fontes.** Republicar a **mesma obra** em diferentes feeds, hosts e URLs: **zero apresentações duplicadas como descoberta nova** na mesma edição, conforme B02.

**US-07 — Perspectivas independentes.** Publicar reportagens e análises de autores diferentes sobre o mesmo evento: podem aparecer separadamente, sem deduplicação semântica cega.

**US-08 — Fontes heterogêneas.** Exercitar RSS, Atom, JSON Feed, redirects, charset, resumo com HTML, datas defeituosas, itens grandes e falhas temporárias. A falha de uma fonte não impede fontes sadias de contribuir.

**US-09 — Perda rastreável.** Para cada história rotulada como elegível no corpus, rastrear resultado de aquisição até publicação ou motivo verificável de não publicação; separar rejeição legítima de perda indevida.

**US-10 — Leitura prolongada.** Executar a mesma aquisição/seleção no feed real, com catálogo amplo, conteúdo de múltiplas fontes e scroll efetivo; conteúdo válido continua sendo preparado enquanto o leitor avança, sem repetir histórias, deslocar cards nem interromper a leitura.

**Método:** corpus externo rotulado e execução integrada, não apenas testes unitários dos componentes. Aplicar o [benchmark B01–B06](DISCOVERY_ACCEPTANCE_BENCHMARK.md), sem reduzir nem substituir os critérios existentes. Os cenários acima acrescentam **evidência de comportamento de F03**; não reescrevem os gates vigentes nem afirmam que já passaram.

## 8. Estado observado e pendências para execução

**Evidência parcial já identificada na V2:** suporte a RSS/Atom/JSON Feed, separação de aquisição e interpretação, identidade/versões, isolamento de falhas e testes de componentes. Isso não certifica acesso real, corpus amplo ou histórias sem duplicação entre fontes.

**Riscos a provar ou corrigir, não defeitos todos já reproduzidos:** rejeições de histórias recuperáveis; equivalência canônica entre publicadores; cards sem destino consumível; confusão de publicação/observação/atualização; classificação e priorização de acesso sob paywall; ausência de demonstração integrada com escala real.

**Situação da F03:** **especificação de produto consolidada; implementação e aceitação ponta a ponta não aprovadas / ainda não demonstradas**. Não declarar PASS sem prova real. Priorizar correções dentro das responsabilidades existentes; não prescrever novos motores, filas, timers, caches ou camadas.

## 9. Critério de conclusão

A Frente 03 estará pronta do ponto de vista do produto quando uma pessoa conseguir descobrir, abrir e consumir histórias verdadeiras de fontes diferentes, com frescor contextual honesto, forte preferência por acesso aberto, sem republicações repetitivas nem supressão de perspectivas independentes, e quando itens elegíveis não sumirem sem razão identificável. **A prova deve acompanhar a história de ponta a ponta: fonte → aquisição → identidade → conteúdo → decisão editorial → card → consumo efetivo.**

## 10. Ganchos para a experiência de consumo (F11–F20)

A F03 define quando um artigo, link e mídia são **conteúdo legítimo e consumível**. A experiência de **abrir/fechar e voltar sem perda** pertence à [F14](F14_READER_LINK_NAVIGATION_UX_PRD.md); reprodução explícita de áudio e posição de episódio pertencem à [F15](F15_PODCAST_PLAYBACK_CONTINUITY_UX_PRD.md); compartilhar o destino e atribuição sem falsificar origem pertence à [F19](F19_SHARING_DISCOVERY_UX_PRD.md). Todos devem respeitar F03, [F06](F06_SACRED_FEED_CARD_READINESS_PRD.md), B04 e B05. A dependência completa aparece na [matriz de impacto](PRODUCT_SPEC_DEPENDENCIES_F11_F20.md).
