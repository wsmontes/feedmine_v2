# FeedMine V2 — Mapa de impactos e aceitação de produto F11–F20

**Data:** 2026-10-10  
**Estado:** análise de especificação; **não é implementação, benchmark executado nem release PASS**.  
**Escopo:** costura entre as frentes [F01–F10](PRODUCT_AUDIT_10_FRONTS.md), as [F11–F20](PRODUCT_AUDIT_FRONTS_11_20.md), os PRDs, as regras vigentes e novas definições de experiência.

## 1. Hierarquia e modo de interpretação

1. [Norte do produto](PRODUCT_NORTH_STAR.md): descoberta da internet aberta; não exigir assinatura, URL ou OPML para começar.
2. [Decisões PD-1–PD-10](PRODUCT_DECISIONS_2026-10-09.md) e [invariantes INV](../architecture/PRODUCT_INVARIANTS.md): conteúdo e apresentação publicados são imutáveis; autonomia e cobertura progressivas; idioma de conteúdo é restrição; catálogo público e estado pessoal têm autoridades diferentes.
3. [Benchmark de aceitação B01–B06](DISCOVERY_ACCEPTANCE_BENCHMARK.md): **contrato P0 congelado**, obrigatório para release, não relaxado por estas frentes.
4. [F01–F10](PRODUCT_AUDIT_10_FRONTS.md) e PRDs específicos [F02](F02_DISCOVERY_FEED_ONBOARDING_PRD.md), [F03](F03_ACQUISITION_FRESHNESS_STORY_INTEGRITY_PRD.md), [F05](F05_CONTINUOUS_RUNWAY_PRODUCT_PRD.md), [F06](F06_SACRED_FEED_CARD_READINESS_PRD.md): promessa macro e domínios responsáveis.
5. **F11–F20**: provas adicionais de experiência **UX11–UX20**, com referência aos gates já existentes. Estes critérios só avaliam aquilo que a frente declara oferecer; não criam uma segunda estratégia de seleção nem substituem B01–B06.

Os documentos de [arquitetura](../architecture/ARCHITECTURE.md), [contrato apresentação](../architecture/RUNTIME_PRESENTATION_CONTRACT.md) e [modelo de domínio](../architecture/DOMAIN_MODEL.md) são **restrições e referências**, não autorização para especificar classes, algoritmos, caches ou schedulers nesta rodada. [UI V1→V2](../v1-study/UI_TRANSFER_MATRIX.md) é **evidência de inventário**, não decisão irrevogável de portar a UI inteira.

## 2. Matriz de impacto: onde cada frente pega

| Frente | Frentes-mãe / documento vigente | Gargalo de produto ou tensão documental | O que define a conclusão | Prova complementar |
| --- | --- | --- | --- | --- |
| [F11](F11_UNIFIED_SEARCH_RESULTS_UX_PRD.md) | F01, F07, F08; [contextos/filtros](../superpowers/specs/2026-10-09-reader-filters-and-context-identity.md) | A V1 tinha fontes + histórias + salvos na mesma busca; contexto de busca V2 ≠ painel unificado | Pessoa distingue tipos, navega aos resultados certos e volta à consulta/leitura | **UX11** + B05/B04 |
| [F12](F12_SOURCE_TAXONOMY_NAVIGATION_UX_PRD.md) | F01, F02, F04, F07; [catálogo/taxonomia V1](../v1-study/04-catalog-editorial.md) | Ter catálogo com 77.443 Sources não prova que navegar e entender uma Source seja possível | Descobrir origem, assuntos e países e abrir feed específico sem URL/RSS | **UX12** + B01/B02/B05 |
| [F13](F13_CONTENT_CONTROL_EXCLUSIONS_UX_PRD.md) | F02, F04, F07, F09; [decisões](PRODUCT_DECISIONS_2026-10-09.md) | V2 possui elegibilidade por palavra-chave, mas editor de exclusões V1 não foi transferido | Regras duráveis e preferências leves não se confundem; editar/reverter produz efeito em história futura | **UX13** + B02/B04/B05 |
| [F14](F14_READER_LINK_NAVIGATION_UX_PRD.md) | F03, F06, F08, F09; [F03](F03_ACQUISITION_FRESHNESS_STORY_INTEGRITY_PRD.md) | Card com link tecnicamente válido não prova leitura utilizável nem retorno ao mesmo card | Abrir/consumir/fechar artigo real, inclusive erro, sem perda de posição | **UX14** + B04/B05 |
| [F15](F15_PODCAST_PLAYBACK_CONTINUITY_UX_PRD.md) | F03, F06, F08, F09, F10; [F06](F06_SACRED_FEED_CARD_READINESS_PRD.md) | Mini-player parcial ≠ progresso restaurado/áudio utilizável ao mudar tela ou relançar | Episódio, estado e ponto de reprodução coerentes; vídeo não é prometido por semelhança | **UX15** + B04/B05/B06 |
| [F16](F16_PERSONAL_LIBRARY_SMART_FEEDS_UX_PRD.md) | F07, F08, F09; [contextos](../superpowers/specs/2026-10-09-reader-contexts.md) | Persistir boxes/collections/presets ≠ ler, localizar e editar esses agrupamentos | Salvos, coleções e smart feeds como destinos de leitura e retorno, sem perder ownership | **UX16** + B05 |
| [F17](F17_LOCALIZATION_APPEARANCE_ACCESSIBILITY_UX_PRD.md) | F02, F06, F07, F10; [UI quality](../v1-study/05-ui-app-quality.md) | V1 listava 39 idiomas; V2 não tem seletor equivalente e não comprovou cobertura de traduções/RTL | Idioma da UI vs. idiomas lidos, legibilidade, RTL, VoiceOver e aparência sem salto | **UX17** + B04/B06 |
| [F18](F18_ADD_FEED_CLIPBOARD_OPML_PORTABILITY_PRD.md) | F01, F07, F08, F09, F10; [PD-10](PRODUCT_DECISIONS_2026-10-09.md) | Import/export de **Sources** não garante portabilidade de bookmarks/coleções/estados; JSON rotulado «Backup JSON» contém Sources | Contrato honesto de **interoperabilidade de fontes** e **backup/restauração dos dados pessoais** com escopo explícito | **UX18** + B05 |
| [F19](F19_SHARING_DISCOVERY_UX_PRD.md) | F03, F06, F08, F17; [V1 UI inventory](../v1-study/UI_TRANSFER_MATRIX.md) | Compartilhar link está presente; imagem/stats foram deliberadamente deixados fora da transferência | Compartilhar informação correta de forma útil; imagem/stats só se decisão de produto os incluir | **UX19** + B04 |
| [F20](F20_RETURN_FRESHNESS_LIFECYCLE_PRD.md) | F02, F05, F07, F09; [F05](F05_CONTINUOUS_RUNWAY_PRODUCT_PRD.md) | «Novidade» da V1 tinha carousel/booster próprios; refresh/foreground V2 não devem mexer na leitura | Retorno conserva leitura e apresenta oportunidade real de novas histórias sem inserção silenciosa | **UX20** + B03/B04/B05 |

### Gargalos que atravessam mais de uma frente

**G1 — Busca, filtros, navegação e biblioteca são a mesma jornada, mas não o mesmo escopo.** F11 encontra uma Source; F12 abre seu feed; F13 restringe conteúdo futuro; F16 guarda; F07 preserva as identidades A→B→A. A aceitação exige percorrer a cadeia sem misturar estados.

**G2 — «Existe action» não significa «o usuário consumiu».** F14/F15/F19 precisam distinguir affordance disponível, destino certo, mídia utilizável e retorno correto. Não usar teste de método como substituto de abertura de artigo ou áudio real.

**G3 — Conteúdo publicado vs. preferências futuras.** F02/F13/F17/F20 não podem silenciosamente recriar o que está visível ao mudar peso editorial, aparência, localidade da UI ou receber novidades. Mudanças deliberadas de contexto continuam possíveis com transição explícita.

**G4 — Portabilidade tem dois níveis distintos.** **Interoperabilidade de Sources** permite mudar/importar listas de subscriptions. **Portabilidade dos dados pessoais** permite sair, reinstalar ou mudar de aparelho com estado de leitura e organização recuperável. Um OPML não substitui um backup da biblioteca; um JSON contendo só `sources` tampouco.

**G5 — Lacuna de prova da interface.** A [matriz V1→V2](../v1-study/UI_TRANSFER_MATRIX.md) registra `validado`, `em transferência` e `inventariado`; a primeira categoria frequentemente prova componentes/um gesto, não a jornada inteira. F11–F20 exigem traces de interação na UI real, dados conhecidos e imagens quando relevantes.

**G6 — Autonomia do feed principal.** Todas as experiências de administração são opcionais e **não** podem virar requisito para descobrir conteúdo no primeiro uso (F02/B01). «Um app completo» não significa «copiar todos os menus da V1».

## 3. O que «portabilidade» quer dizer na V2

| Capacidade | Dado que a pessoa tem direito a recuperar | Contrato verificável de experiência | O que não significa |
| --- | --- | --- | --- |
| **Interoperabilidade de fontes** | lista de Sources importadas/selecionadas e seus endereços estáveis exportáveis; hierarquia de organização quando representável | OPML exportado é lido por outro leitor compatível; OPML de terceiro permite prévia/seleção/import com resultados e erros honestos | não garante que qualquer site continue online ou que o app de destino entenda preferências do FeedMine |
| **Backup dos dados pessoais** | coleções e membership, caixas e referências exatas dos itens salvos, presets/feeds curados e suas escolhas, filtros/exclusões duráveis, idiomas/lugares/preferências explícitas, progresso/estado de leitura e imports pessoais que o FeedMine mantém | arquivo portável e documentado, com versão e inventário, pode ser reimportado em instalação limpa **sem conta FeedMine**; itens e relações cobertos voltam de forma verificável, sem substituição destrutiva silenciosa | **não** é exportação irrestrita de textos/imagens de terceiros nem garantia de reproduzir páginas externas offline |
| **Portabilidade legível** | artigo salvo identificável por título, origem, link/identidade durável e metadados que o FeedMine pode preservar | exportação compreensível permite reencontrar/reabrir conteúdo onde o destino continuar disponível; limites de conteúdo offline são declarados | URL ou nome de host sozinho **não** preserva uma caixa de bookmarks |
| **Escopo e consentimento** | escolher fontes apenas, coleção, caixa ou backup pessoal completo quando oferecido | nome/preview do arquivo informa exatamente o que contém; cancelar não altera estado; falhas parciais são reportadas e export anterior segue válido | botão chamado «Backup» produzindo somente lista de Sources |

**Evidência direta V2:** [`ReaderExport.swift`](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineRuntime/ReaderExport.swift) oferece formatos incluindo `json` rotulado «Backup JSON»; [`ReaderImportExportCoordinator.swift`](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineComposition/ReaderImportExportCoordinator.swift) implementa `json(entries:)` com array `sources`, e exportar `bookmarkBox` deriva **Sources dos links** dos cards salvos, não salva identidades dos cards como itens recuperáveis. Este é um **descompasso confirmado de semântica de produto**, não prova de que todo o backup pessoal já exista.

**Decisão de escopo ainda a formalizar:** se a V2 vai oferecer *backup completo* já no release, deve aceitar a prova UX18-B. Se não vai, deve chamar a função atual **«Exportar fontes»**, não «Backup»; a promessa completa continua fora de escopo e **não pode receber PASS**. A especificação não exige um formato técnico específico nem copiar conteúdo protegido de terceiros.

## 4. Como funcionam os benchmarks complementares UX11–UX20

Os benchmarks abaixo são **oráculos black-box**, determinísticos no cenário, sem adaptar o critério ao resultado. B01–B06 continuam os únicos gates P0 da baseline vigente; UX11–UX20 **não alteram seus limiares, suas durações nem seu corpus**.

- **UX11:** busca por termo conhecido retorna Source/artigo/salvo no escopo certo; abrir cada um chega ao objeto correto; cancelar restaura contexto/âncora. **Zero resultado de query/escopo antigo**.
- **UX12:** card→Source→nó de taxonomia/região→Source e retorno; seleção de Source altera **futuro**, não publicação prévia. **Zero navegação para entidade errada**.
- **UX13:** criar exclusão durável e preferência negativa leve; avançar e comparar histórias futuras; desfazer/excluir restaura elegibilidade; restart conserva só o estado que prometeu persistir. **Zero alteração silenciosa do card visível**.
- **UX14:** abrir matéria real, seguir link, fechar, voltar ao **mesmo card/posição**; repetir com destino indisponível. **Zero dead tap ou erro mascarado como artigo aberto**.
- **UX15:** ouvir episódio real, navegar no feed, pausar/retomar/seek, interromper e relançar. Mesmo episódio e posição conforme regra declarada; **zero mudança de âncora por ação do player**.
- **UX16:** guardar mesmo card em duas caixas, criar coleção e Smart Feed, relançar, acessar cada leitura; remover uma entidade não destrói outra; **zero perda de relação pessoal**.
- **UX17:** navegar idioma suportado, RTL, Dynamic Type, contraste/night e VoiceOver nas superfícies principais; mudança visual não desloca o conteúdo. **Zero controle anunciado e inoperante**.
- **UX18:** export/import de fontes via OPML e arquivo legível; **além disso, se o produto anunciar «backup»**, restauração em instalação limpa recupera as entidades pessoais declaradas, sem conta; **zero campo prometido perdido silenciosamente**. Registrar matriz item-por-item.
- **UX19:** copiar/compartilhar card com título, origem e link corretos; se opção de imagem/stats for oferecida, verificar o payload visual e a privacidade. **Zero ação visível que não funcione**.
- **UX20:** abrir, consumir até card X, sair, admitir novidades, voltar offline/online e escolher quando vê-las; **mesmo card/âncora antes da escolha** e nenhum card histórico adulterado.

**Setup mínimo comum:** versão/commit de app, corpus rotulado e congelado, dispositivo/iOS/locale, sequência de gestos reais e estado local prévio, expectativa escrita antes da execução, vídeo/prints e lista de identidades das ações/objetos. Para cada caso reportar `PASS / FAIL / NOT_RUN / BLOCKED` (evidência exata e motivo). Se não houver interface comprometida no release, registrar decisão explícita `DEFERRED/NOT_OFFERED` no **escopo de produto**, mas **não** como quinta classificação de benchmark executado. Recursos presentes que não funcionam não podem ser rotulados «adiados».

A seleção de casos UX não substitui cenários obrigatórios B01–B06; executar cruzamentos quando relevantes. Evidência de código e testes unitários é útil para diagnóstico, mas **não pontua sozinha** como aprovação da experiência.

## 5. Ligações e separação de autoridade

- [Mapa das primeiras dez frentes](PRODUCT_AUDIT_10_FRONTS.md) segue como dono da análise macro.
- [Catálogo e descoberta inicial F02](F02_DISCOVERY_FEED_ONBOARDING_PRD.md) permanece autoridade da primeira experiência e dos votos explícitos no feed.
- [Integridade e consumibilidade F03](F03_ACQUISITION_FRESHNESS_STORY_INTEGRITY_PRD.md) é autoridade para destinos reais/paywall e distinção entre duplicatas e perspectivas.
- [Runway F05](F05_CONTINUOUS_RUNWAY_PRODUCT_PRD.md) e [cards estáveis F06](F06_SACRED_FEED_CARD_READINESS_PRD.md) são inegociáveis durante navegação por busca, leitor, áudio, compartilhamento e retorno.
- [B01–B06](DISCOVERY_ACCEPTANCE_BENCHMARK.md) permanecem congelados; o relatório de release deve mostrar **separadamente** gates P0 e provas UX condicionadas às funcionalidades prometidas.
- [F11–F20](PRODUCT_AUDIT_FRONTS_11_20.md) é o **índice de oportunidades**, os dez PRDs individuais são os **contratos específicos**.
- [Matriz V1→V2](../v1-study/UI_TRANSFER_MATRIX.md) é comparação/registro e não deve ganhar poder sobre as decisões de produto.

**Se houver conflito:** registrar conflito pelo nome, autoridade que o resolve e efeito na aceitação. Não corrigir silenciosamente especificações anteriores nem transformar uma preferência de UX num novo requisito arquitetural.
