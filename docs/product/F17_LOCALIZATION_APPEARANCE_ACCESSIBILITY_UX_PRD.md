# F17 — Idiomas, identidade visual e acesso inclusivo

**Status:** especificação de produto/UX candidata, 2026-10-10. Não é implementação, prova executada ou autorização para substituir B01–B06.  
**Referências comuns:** [norte](PRODUCT_NORTH_STAR.md), [decisões](PRODUCT_DECISIONS_2026-10-09.md), [invariantes](../architecture/PRODUCT_INVARIANTS.md), [benchmark vigente](DISCOVERY_ACCEPTANCE_BENCHMARK.md), [mapa de impactos](PRODUCT_SPEC_DEPENDENCIES_F11_F20.md), [matriz V1→V2](../v1-study/UI_TRANSFER_MATRIX.md).

## 1. Promessa e o que é produto pronto

Uma pessoa entende a interface e lê confortavelmente no seu ambiente visual. **Idioma da interface não é idioma dos artigos**; o primeiro é a língua dos controles e mensagens, o segundo é uma restrição declarada sobre o conteúdo que o FeedMine procura.

**Pronto significa:** UX17 exige percursos A–E nos idiomas efetivamente anunciados e ambiente real, com itens controlados e provas visuais/assistivas. Zero controle suportado porém inacessível/inoperante, zero regressão de âncora; B04/B06 permanecem independentes.

## 2. Evidência V1/V2 e gargalo

`LocaleManager.swift` da V1 listava 39 **opções de idioma** e as configurações ofereciam escolha; isso não é prova de que 39 traduções estivessem completas. Na V2, `ReaderSettingsView.swift` registra explicitamente a ausência do seletor de idioma e String Catalog equivalente. Aparência e paleta circadiana foram parcialmente transferidas; a matriz não comprova screenshots comparáveis, bundle/locales e comportamento de RTL/night.

## 3. Contrato de experiência

- **R1 — Duas preferências independentes.** Alterar o idioma dos menus não pode trocar silenciosamente os idiomas dos artigos, países ou interesses selecionados; editar idiomas de leitura muda apenas a oferta futura elegível.

- **R2 — Promessa linguística verdadeira.** Cada idioma apresentado como disponível precisa ter textos essenciais traduzidos, incluindo primeiro contato, controles, erros, pesquisa, salvos, exportação, áudio e acessibilidade. Idiomas sem cobertura não são anunciados como completos; fallback é consistente.

- **R3 — Leitura em telas reais.** Texto ampliado, VoiceOver, contraste, fontes e componentes de mídia preservam significado, acesso a ações e leitura do título/origem; RTL preserva ordem compreensível e gestos navegáveis.

- **R4 — Aparência sem surpresa editorial.** Paleta/typografia circadianas, modo noturno, tamanho de fonte e rotação são preferências visuais; alteram renderização necessária sem mudar a sequência de artigos, falsificar exposição ou trazer mídias novas ao card publicado.

- **R5 — Preferências previsíveis.** A pessoa enxerga o efeito e pode desfazer mudanças; se há reinício necessário para alterar locale, isso é informado antes da confirmação.

- **R6 — Acessibilidade de estados críticos.** Abertura inicial, loading honesto, rede offline, erros, filtro vazio e destinos de ação são compreensíveis também sem ver a tela.

## 4. Benchmark UX17 (provas black-box)

| Caso | Cenário e gesto reais | Oráculo de aprovação |
| --- | --- | --- |
| **UX17-A — Idiomas distintos** | Escolher idioma de interface L e idiomas de conteúdo M/N em instalação limpa e depois alterar só L. | Controles e mensagens aparecem em L com cobertura real; conteúdo ainda respeita M/N. |
| **UX17-B — Acesso** | Percorrer primeiro uso, busca, card, filtro, leitor e salvos com VoiceOver e Dynamic Type máximo suportado. | Controles rotulados, foco/ordem utilizáveis, nenhum texto essencial truncado inacessível. |
| **UX17-C — RTL** | Executar percurso em idioma RTL **que o produto declarar suportado**. | Hierarquia, foco, navegação e números/links coerentes; nenhum falso suporte anunciado. |
| **UX17-D — Aparência** | Parar em card X, trocar night/paleta/tipo, rotacionar e retornar do background. | Mesmo artigo/âncora, apenas rematerialização visual justificada, nenhuma mutação editorial. |
| **UX17-E — Fallback** | Sistema em idioma não suportado ou locale com tradução parcial. | Fallback conhecido, sem mistura incoerente de labels e sem esconder controles. |

Executar com dados/versão/dispositivo identificados, evidências de gestos reais, capturas e identidades de entrada/saída. Cada caso recebe **PASS / FAIL / NOT_RUN / BLOCKED** e motivo. Os gates B01–B06 não são substituídos nem reduzidos; percentuais e durações do benchmark vigente não são convertidos em cotas de produção.

## 5. Documentos conectados e limites

[F02 — idioma/lugar inicial](F02_DISCOVERY_FEED_ONBOARDING_PRD.md); [F06 — estabilidade](F06_SACRED_FEED_CARD_READINESS_PRD.md); [F07 filtros](PRODUCT_AUDIT_10_FRONTS.md); [F10 acessibilidade/release](PRODUCT_AUDIT_10_FRONTS.md); [V1 UI quality](../v1-study/05-ui-app-quality.md).

**Fronteira:** F10 decide o gate físico e técnico de acessibilidade; F17 especifica a **experiência de idioma e apresentação**. A lista de idiomas da V1 não deve virar promessa V2 sem verificação de recursos.

**Não-objetivos:** copiar automaticamente a V1, exigir conta/servidor próprio, criar UI com ações mortas, quebrar o prefixo publicado ou definir soluções técnicas nesta etapa.

## 6. Estado e conflitos em aberto

**Jornada UX17 integral: NOT_RUN.** O que existe nos componentes/testes do repositório é evidência de capacidade, não certificação desta promessa. Diferenças deliberadas da V1 devem ser aceitas ou revertidas **por decisão de produto explícita** e não por presunção de paridade.
