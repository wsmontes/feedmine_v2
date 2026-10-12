# Rodada 9 — uma escolha por idioma, e a interface na língua do aparelho (2026-10-11)

Implementação da frente aberta pelo parecer do PO na rodada 8 (direção aprovada) e pelas condições do
Codex na rodada 9. Toda a evidência abaixo foi executada nesta árvore; nenhum número é estimado.

## 1. O defeito, em uma frase

O catálogo declara **257 códigos** (`en`, `en-US`, `en-GB`, `pt`, `pt-BR`…), o leitor escolhe **um idioma**, e
três lugares guardavam ou comparavam isso de formas diferentes: o filtro gravava o código bruto, o chip do
onboarding escrevia o código cru direto no array da receita, e o perfil de descoberta exigia pertencimento
exato a um conjunto documentado como "subtags primários". Resultado medido: o mesmo idioma aparecia como
várias linhas de rótulo idêntico com contagens diferentes, e uma seleção regional **não admitia nada** no
caminho da descoberta.

## 2. Uma regra, um lugar

`Sources/FeedMineDomain/ReaderLanguageCode.swift` (novo) é a única definição: a escolha é o **subtag
primário, em minúsculas** (`pt-BR` → `pt`), `und`/vazio é o balde não declarado, e um conjunto de escolhas
colapsa duplicatas (`{pt, pt-BR}` → `{pt}`).

Aplicada em **todas** as entradas e comparações:

|Onde|Antes|Agora|
|---|---|---|
|`ReaderFilter.init` / decode|`trim` apenas|`ReaderLanguageCode.choices`|
|`FeedRecipeDefinition.init` (+ observador da propriedade)|colapsava no init, mas o chip mutava o array direto|colapsa no init **e** em qualquer escrita direta|
|`ReaderFilterDraft.toggleLanguage`|gravava o valor cru|`ReaderLanguageCode.choice`|
|`ReaderDiscoveryProfile.init`|só `lowercase`|`ReaderLanguageCode.choices`|
|`ReaderDiscoveryPool.admits`|comparava com `primarySubtag` local e exigia pertencimento exato|`ReaderLanguageCode.answered`|
|`ReaderFilterEligibility.admitsLanguage`|comparava primário **ou** código exato|`ReaderLanguageCode.answered`|
|`LegacyCatalogLanguageRecord.primarySubtag` / `CatalogLanguageSummary.primarySubtag`|cada um com sua cópia|delegam à regra|

## 3. Mudança de comportamento sobre dados existentes (registro obrigatório)

Filtros gravados antes desta rodada podem conter código regional (`pt-BR`). O que muda, medido pelos dois
caminhos que leem um filtro:

|Valor persistido|Antes|Depois|
|---|---|---|
|`pt-BR` na elegibilidade editorial (`ReaderFilterEligibility`)|admitia **só** fontes declaradas `pt-BR`|admite `pt`, `pt-BR`, `pt-PT` — o idioma inteiro|
|`pt-BR` no pool de descoberta (`ReaderDiscoveryPool`)|**não admitia nada** (`pt-br` ≠ `pt`)|admite as mesmas fontes que `pt`|

É **reparo, não estreitamento**: nenhuma seleção perde fontes, e a seleção regional passa a significar o que
a interface sempre mostrou ("Português"). A normalização acontece na **leitura** (decode do filtro, init do
perfil) e na escrita; nenhuma migração de banco é necessária, e nenhum outro critério do filtro é tocado.

## 4. Apresentação

- `CatalogLanguageGroup` (`FeedMineRuntime/CatalogValues.swift`) agrupa as linhas do catálogo **por idioma**,
  preservando a ordem do catálogo (maiores primeiro, `und` por último) e somando as contagens dos variantes.
- **Uma contagem, um significado**: a linha mostra `fontes disponíveis` = `totalSources` somado sobre todas as
  variantes do idioma — a forma exata do parecer do PO (`Inglês · 26.775 fontes disponíveis` no catálogo
  empacotado, somando `en` 17.971 + `en-US` 7.028 + `en-GB` 1.013 + os demais `en-*`). `enabledSources` continua
  existindo para ordenação e nunca é exibido com o mesmo rótulo.
- **Expansão informativa**: as variantes regionais aparecem nomeadas (idioma + região) e contadas, **sem
  nenhum controle de seleção**. Identificadores: `language-<primário>` / `language-regions-<primário>` /
  `language-variant-<código>` no filtro, e `composer-language-<primário>` /
  `composer-language-regions-<primário>` / `composer-language-variant-<código>` no onboarding (nada de buscar
  por texto "Portuguese").
- Um filtro legado com código regional mostra a linha **do idioma** como selecionada: nenhuma tela fica com
  tudo desmarcado enquanto filtra.

## 5. Localização

- `FeedMineApp/FeedMineApp/Resources/Localizable.xcstrings` (String Catalog, `sourceLanguage = pt-BR`) entrou no
  alvo do app; as chaves foram extraídas com `SWIFT_EMIT_LOC_STRINGS=YES` + `xcstringstool sync` (344 chaves,
  com `%@`/`%lld` tipados — a extração por *lightweight parsing* produziria `%arg`, que não casa em tempo de
  execução).
- `Info.plist`: `CFBundleDevelopmentRegion = en` (inglês é o *fallback*) e `CFBundleLocalizations = [en, pt-BR]`.
- **A interface segue o aparelho**: `CatalogLanguageNaming.interfaceLocale` resolve a língua a partir da
  resolução do próprio bundle (preferência por app incluída) e é o único lugar que decide isso. O app a instala
  como `\.locale` na raiz, então cópia, datas e números leem a mesma língua.
- Nomes de **país** vinham do catálogo em inglês e nunca eram localizados: `CatalogRegionNaming` reverte o
  nome para o código de região pela lista do Foundation e nomeia na língua da interface (África do Sul, Brasil,
  Estados Unidos), mantendo o nome do catálogo quando não consegue colocar.
- **Datas** (`FeedItemCardView`) passaram a usar a língua da interface em vez do padrão do processo.
- Textos que nunca poderiam localizar foram convertidos: o título do onboarding (em inglês, agora três chaves),
  o resumo de status da preparação, o rótulo do contexto ativo.

## 6. Verificação executada

|Prova|Comando|Resultado|
|---|---|---|
|Pacote|`swift build`|exit 0|
|Suíte completa|`swift test`|**1205 testes, 0 falhas** (1 skip pré-existente)|
|App (simulador)|`xcodebuild … -scheme FeedMine build`|BUILD SUCCEEDED|
|Catálogo|`xcstringstool compile` / build|compila; 344 chaves|

Testes novos: `ReaderLanguageChoiceTests` (regra e migração sobre JSON legado),
`CatalogLanguageGroupingTests` (agrupamento, contagens somadas, rótulos únicos, nomes de idioma/país, formato de
número), `LanguageSurfaceTests` (linhas do filtro, seleção legada, ausência de controle por variante, valores do
onboarding) e um caso de pool em `ReaderDiscoveryPoolTests` (perfil `pt` admite a fonte que declara `pt-BR`;
`pt-BR`, `pt` e `PT` admitem o mesmo conjunto). Dois testes existentes foram atualizados porque o contrato
mudou de propósito (linhas do filtro por idioma; chips do lens resolvidos por idioma) e um terceiro teve sua
asserção incidental de formato de data substituída pela invariante que ele realmente protege.

## 7. Parecer do PO (recebido em 2026-10-11): **APROVADO — frente encerrada**

- **(a) Apresentação aprovada.** "Um idioma, uma escolha, sem duplicações visuais", semântica consistente entre
  onboarding, filtros, descoberta e persistência, interface localizada pelo aparelho e independente do idioma
  do conteúdo, compatibilidade com preferências anteriores preservada. O PO destacou a correção da divergência
  entre elegibilidade e descoberta: "o usuário finalmente recebe aquilo que sua seleção promete".
- **(b) Expansão: manter TODAS as variantes**, inclusive regiões com uma única fonte — "não quero um limite
  arbitrário de relevância; a expansão é uma área informativa, acessada intencionalmente". A implementação atual
  já é isso.
- **(c) Seleção regional exata: ADIADA e não obrigatória.** "Não considero essa funcionalidade obrigatória para o
  produto… não criar backlog obrigatório apenas porque o catálogo permite essa granularidade."
- **Diretriz registrada:** "o FeedMine deve esconder a complexidade do catálogo sem esconder informações úteis.
  A seleção precisa ser simples; os detalhes podem ser profundos, desde que opcionais."
- Nenhuma alteração adicional exigida; as evidências relatadas bastaram para o aceite funcional.

## 8. Achado pré-existente (não desta rodada): o título do onboarding não é desenhado

Ao localizar o título, verifiquei o resultado na tela do simulador e ele **não aparece** — nem antes nem depois
da mudança. Duas capturas do mesmo aparelho, uma de rodada anterior e uma de agora, são idênticas nesse ponto:
[antes](evidence/2026-10-11-r9/welcome-headline-not-rendered-before.png) e
[depois](evidence/2026-10-11-r9/welcome-headline-not-rendered-after.png).

Mecanismo: `ReaderOnboardingView.headline` (`Sources/FeedMineUI/Onboarding/ReaderOnboardingView.swift:132-147`)
é um `Text(verbatim: "")` — sem tamanho — com o título real em `.overlay`. O texto existe para a acessibilidade
(`welcome-headline`, que os testes usam) mas não pinta nada visível. Não é regressão da rodada 9: o título
nunca foi visível nesse layout, e a localização dele segue correta para quando o desenho for corrigido.

Classificação do PO: **P1, não bloqueante**, encaminhado ao Codex para a próxima revisão da tela de boas-vindas,
com a instrução explícita de **não** reabrir a implementação de idiomas para corrigi-lo.

## 9. O que ficou de fora (e por quê)

- **Seleção regional exata** (filtrar só `pt-BR`): decidida como frente própria e **não obrigatória** pelo PO.
  Hoje a região é informação; o motor compara o idioma.
- Verificação em **aparelho físico** e a prova de fluidez de 30 minutos seguem com o responsável pela medição.
