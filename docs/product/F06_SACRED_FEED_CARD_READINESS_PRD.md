# Frente 06 — O feed é sagrado
## PRD de experiência — 2026-10-10

**Status:** decisões de produto; não há aceite de implementação. Aplicam-se [PD-5 e PD-9](PRODUCT_DECISIONS_2026-10-09.md), [INV-08, INV-09 e INV-17](../architecture/PRODUCT_INVARIANTS.md) e [benchmark B04](DISCOVERY_ACCEPTANCE_BENCHMARK.md).

### Regra central: candidato pendente SAI da fila de publicação

Um candidato escolhido que ainda não pode oferecer experiência válida — imagem pendente, link temporariamente indisponível, texto ou mídia incompleta, falha de preparação — **sai imediatamente da fila pronta para publicar**. Não segura a cabeça da fila, não reserva posição nem impede que os candidatos seguintes sejam apresentados. Não é apagado do supply elegível: identidade, trabalho aproveitável e motivo de suspensão continuam disponíveis para reconsideração quando houver prontidão ou alternativa legítima.

Ao voltar, o candidato concorre **na seleção editorial atual**, respeitando idade contextual, relevância, filtros, diversidade e alternância; não retorna ao lugar antigo nem se insere no histórico já admitido. Um candidato irrecuperável recebe motivo rastreável, não vira card quebrado.

### Imagem e degradação

Imagem lenta ou falha temporária não significa imagem definitivamente impossível. Enquanto recuperável, a história aguarda fora da fila pronta, e as demais avançam. Texto puro é uma apresentação editorial legítima desde o início ou uma decisão posterior fundada em evidência de mídia realmente defeituosa/indisponível. **Não existe tempo mágico de espera ou número fixo de retries que transforme automaticamente uma imagem pendente em texto puro.** Limites por operação protegem rede, memória e energia; não representam abandono editorial.

Um link que não permite consumir a matéria não vira card válido. Pode-se tentar destino alternativo legítimo ou texto integral autorizado localmente; caso contrário, suspender ou rejeitar com motivo verificável.

### Fronteiras

Até a publicação, candidato, prioridade e preparação podem evoluir. Depois da publicação, identidade, texto, ação, mídia referenciada e contrato visual ficam imutáveis, mesmo se ainda não vistos. Depois da admissão à leitura, ordem, geometria e âncora também ficam protegidas. Rede e mídia tardias não alteram a tela, nem criam gesto de scroll. Só o avanço legítimo ou transição explícita admite novas histórias. Decodificar novamente os mesmos pixels de um slot fixo não autoriza transformar um card de texto em card com imagem.

Trabalho continua em paralelo, limitado pela capacidade real, usando os responsáveis existentes — sem nova fila paralela, timer periódico, cache ou mecanismo de retry duplicado.

### Provas de aceitação

- **F06-A:** primeiro candidato permanece pendente, mas todos os seguintes prontos avançam; nenhum bloqueio de fila, ordinal reservado ou repetição infinita.
- **F06-B:** imagem antes lenta chega, candidato retorna à seleção futura; cards anteriores não mudam.
- **F06-C:** imagem realmente quebrada leva a decisão intencional de texto puro; falha transitória não é confundida com definitiva.
- **F06-D:** link temporariamente indisponível não bloqueia outras histórias; link sem ação válida nunca vira card morto.
- **F06-E:** falhas misturadas de texto, link e mídia não bloqueiam conteúdo pronto; pendentes permanecem recuperáveis e a alternância editorial continua válida.
- **F06-F:** teste B04 completo com imagem tardia, fonte lenta, edição, app parado, rotação, Dynamic Type, background e retorno, medindo IDs, ordem, bounds, âncora e deslocamento físico em dispositivo real.
- **F06-G:** políticas de rede e mídia mudam com recursos observados, sem quantidades arbitrárias.

### Observação sobre a V2

O código já possui `PublishedCard` e `RenderContract` imutáveis, `FeedSession` com admissão controlada e `MediaPrefetcher` concorrente. Porém, `MediaReadiness.presentation(for:)` atualmente responde `.textOnly` quando uma imagem simplesmente ainda não está pronta. Isso **pode conflitar** com a regra de suspensão recuperável. Precisamos demonstrar com teste ponta a ponta que o candidato pendente realmente sai da fila pronta sem desaparecer do universo elegível. Ainda não há prova de B04 integral em iPhone físico.
