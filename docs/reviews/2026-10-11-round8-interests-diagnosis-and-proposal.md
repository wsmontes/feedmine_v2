# Rodada 8 — interesses compreensíveis (diagnóstico e proposta)

Data: 2026-10-11. Autor: sessão OMP. **Nenhuma linha de código alterada** (pedido do Codex). Evidências
colhidas com catálogo real, leitura do código e consultas ao `catalog.sqlite` empacotado.

## 1. Os rótulos repetidos: não é duplicação nem agrupamento — é região colapsada

O catálogo declara o idioma da fonte com código variável — **257 códigos distintos** no snapshot real:

|Código|Fontes|Código|Fontes|
|---|---|---|---|
|`und` (não declarado)|27.741|`pt`|1.125|
|`en`|17.971|`pt-BR`|936|
|`en-US`|7.028|`fr`|1.171|
|`es`|3.982|`fr-FR`|411|
|`en-GB`|1.013|`es-ES`|394|

`LegacyCatalogReader.languages()` (`Sources/FeedMinePersistence/LegacyCatalogReader.swift:456`) agrupa por
**código bruto** — uma linha por código, com `enabled`/`total`. A interface, porém, rotula pelo **subtag
primário**:

```swift
// Sources/FeedMineComposition/SourceManagementCoordinator.swift:159-164
static func displayName(_ code: String) -> String {
    let primary = String(trimmed.prefix(while: { $0 != "-" && $0 != "_" })).lowercased()
    if primary == "und" { return String(localized: "Idioma não declarado") }
    return Locale.current.localizedString(forLanguageCode: primary)?.capitalized ?? code
}
```

Consequência: `en`, `en-US` e `en-GB` produzem **a mesma etiqueta "English"** com contagens diferentes;
idem `pt`/`pt-BR` ("Portuguese"), `fr`/`fr-FR`, `es`/`es-ES`. São **variantes regionais legítimas**
apresentadas sem a região — o usuário não tem como distinguir, e a contagem ao lado só aumenta a confusão.

## 2. As superfícies não têm o mesmo significado (nomes, contagens, seleção, persistência)

|Superfície|Identidade da linha|Rótulo|Contagem|O que **persiste**|
|---|---|---|---|---|
|Catálogo (`languages()`)|código bruto (257)|nome do subtag primário|`enabled` + `total`|—|
|Onboarding (`ReaderDiscoveryControls`)|`OnboardingLanguage(code:name:)`; num ramo, `name = $0` — **o próprio código**|nome do subtag primário|**nenhuma**|`FeedRecipeDefinition.languages` normalizado para **subtag primário** (`FeedRecipeDefinition.swift:114`)|
|Filtros (`FilterSheetView.languageRows`)|código bruto|`summary.displayName`|`enabledSources`|`ReaderFilter.languages` = **o código da linha** (`language.code`)|
|Perfil de descoberta (persistido)|—|—|—|**subtag primário** (medido: `["en","pt"]`)|

Três significados diferentes convivendo: o *mesmo* rótulo visível ("English"), duas bases de contagem
(nenhuma × `enabledSources`), e **duas identidades persistidas** (subtag primário no onboarding/perfil,
código completo nos filtros). O pipeline já compara por subtag primário
(`ReaderDiscoveryPool.swift:192`, `CatalogValues.primarySubtag`), então a escolha "en" e a escolha "en-US"
têm efeitos equivalentes — mas são gravadas como coisas distintas.

## 3. Comportamento em pt-BR

Medido/verificado no código e nas capturas desta sessão:

- **A cópia da interface é portuguesa e fixa**, inclusive um título **em inglês**:
  `ReaderOnboardingView.swift:140/147` — `Text("The open web,\narranged by you.")`. Dentro da mesma tela
  convivem "Escolha idiomas e lugares" e "The open web, arranged by you.".
- **A pré-seleção segue o aparelho**, não a cópia: `FeedMineApp.swift:731` →
  `Locale.current.language.languageCode?.identifier ?? "en"`. No simulador (locale `en_US`) isso marca
  "English" num app cujos textos são portugueses — a mistura que o Codex observou. Num aparelho pt-BR a
  pré-seleção seria "Portuguese".
- **Nomes de idioma seguem o locale do aparelho** ("English" no simulador; seria "inglês" em pt-BR), mas
  **nomes de país vêm do catálogo** (`catalog_node.name`, `kind = countryKind`) e **nunca são localizados**:
  `Locale.localizedString(forRegionCode:)` não aparece em nenhum lugar do código.
- **Datas relativas** apareceram em inglês ("2 days ago") numa interface em português (captura
  `R1/R2-real-*`), sinal de formatação presa ao locale do aparelho e não à interface.

Ou seja: **idioma da interface**, **idioma do conteúdo** e **país da fonte** estão misturados numa só
superfície, cada um obedecendo a uma fonte diferente (literal no código, `Locale.current`, texto do catálogo).

## 4. Proposta (antes → depois)

Separar explicitamente os três conceitos, e dar a cada um uma fonte de verdade única.

### 4.1 Linha de idioma (onboarding e filtros)

- **Antes:** `English 757`, `English 278`, `English 34` — três linhas, um rótulo só.
- **Depois (recomendado):** uma linha por **idioma** com a contagem agregada, e as variantes regionais
  visíveis só quando existirem:
  - `Inglês · 26.012 fontes` (agrega `en` + `en-US` + `en-GB` + …)
  - `Inglês (Estados Unidos) · 7.028` e `Inglês (Reino Unido) · 1.013` como detalhamento da mesma linha
    (expansão), ou como linhas próprias **com a região no rótulo**
  - `Português · 2.061` com `Português (Brasil) · 936`
  - `Idioma não declarado · 27.741`
- Regra: **duas linhas nunca compartilham o mesmo rótulo visível**; se o código tem região, o rótulo diz qual.

### 4.2 Uma identidade por escolha, persistida em todo lugar

- Escolher no onboarding, no filtro e no perfil deve gravar **o mesmo valor**. Duas opções:
  1. gravar o **código do catálogo** (`pt-BR`) e o pipeline seguir comparando por subtag primário (já faz);
  2. gravar o **subtag primário** (`pt`) e a região virar um refino opcional dentro do idioma.
- Recomendo a (1): é o dado que o catálogo declara, evita "perda de região" e mantém o filtro capaz de
  aceitar `pt` **e** `pt-BR` quando o leitor escolher "Português" no agregado.
- Aceite: a mesma escolha, feita em qualquer superfície, aparece com o mesmo rótulo e o mesmo valor
  persistido nas outras duas.

### 4.3 Idioma da interface × idioma do conteúdo × país da fonte

- **Interface**: uma decisão explícita do PO. Hoje é pt-BR fixo no código; deve ser *declarado* (e o literal
  inglês do onboarding sai ou vira pt-BR).
- **Conteúdo**: o idioma declarado pela fonte (o que o filtro usa) — e as etiquetas de idioma devem ser
  grafadas no idioma da interface.
- **País**: o país **da fonte** vem do catálogo; o rótulo deve ser localizado por `forRegionCode` quando o
  nó trouxer código de região, mantendo o nome do catálogo como fallback honesto.
- Datas: formatar no idioma da interface (hoje seguem o aparelho).

### 4.4 Contagens com significado único

- Dizer **o que** a contagem mede ("fontes disponíveis") e usar a **mesma base** no onboarding e no filtro
  (hoje: nenhuma × `enabledSources`).

## 5. Critérios de aceite propostos

1. Nenhuma tela mostra duas linhas de idioma com o mesmo rótulo visível.
2. Toda linha cujo código declara região nomeia a região (ou está agrupada sob o idioma, com a região visível
   ao expandir).
3. A escolha de idioma feita no onboarding aparece **selecionada e igual** nos filtros e é o que o perfil
   persistido contém (mesmo valor, mesmo significado).
4. Com o aparelho em pt-BR, nenhuma string fixa em inglês permanece na interface (incluindo o título do
   onboarding), e datas/seções aparecem no idioma da interface.
5. `und`/vazio continua se chamando "Idioma não declarado" e continua por último na lista.
6. As contagens das duas superfícies batem entre si e declaram a mesma unidade.

## 6. O que **não** proponho

- Não mexer na taxonomia de filtros além do idioma (mood/taxonomy/regiões ficam como estão).
- Não introduzir uma segunda lista de idiomas: uma fonte de verdade (o catálogo) e uma derivação.
- Não "consertar" o catálogo: 257 códigos com região são dados legítimos; o defeito está em como a interface
  os apresenta e no que ela grava.

## 7. Parecer do PO (recebido em 2026-10-11)

**DECISÃO: DIREÇÃO APROVADA**, com ajuste de semântica nos filtros.

- **(a) Aprovado** — "problema de apresentação, não de duplicação de dados". Aprovados: rótulos únicos,
  preservação dos códigos regionais do catálogo, consistência onboarding/filtros/preferências, separação
  idioma-conteúdo × país-da-fonte × idioma-interface, contagens em "fontes disponíveis", localização de
  países/datas/mensagens. **Ressalva nova e obrigatória:**
  - escolher **"Português"** = aceitar **todas** as variantes de português;
  - escolher **"Português (Brasil)"** = **restringir** a `pt-BR`;
  - se a seleção regional exata não entrar nesta rodada, as variantes devem ser **apenas informativas, sem
    controles que aparentem filtrá-las**. (Hoje o motor compara só o subtag primário: escolher `pt-BR` traz
    `pt-PT` — inconsistência de produto que o PO nomeou.)
- **(b) Idioma da interface: SEGUIR O APARELHO.** pt-BR fixo **não** aprovado. Seguir o idioma do iOS
  (respeitando as preferências por app), pt-BR e inglês suficientes nesta rodada, **inglês como fallback**.
  O idioma da interface **nunca** altera os idiomas de conteúdo escolhidos; datas, países, títulos e
  mensagens usam a mesma localização da interface.
- **(c) Apresentação: AGRUPAR COM EXPANSÃO.** Variantes sob o idioma principal, expansão opcional, com
  contagem por região — no formato: `Inglês · 26.012 fontes disponíveis` → expandir → `Região não especificada
  17.971`, `Estados Unidos 7.028`, `Reino Unido 1.013`.

## 8. Correção ao escopo depois do parecer

O critério de aceite 3 do §5 ("a mesma escolha, mesmo valor") fica **insuficiente**: passa a exigir também
que a escolha **regional** restrinja de fato o que é apresentado, ou que a variante seja informativa sem
controle. Sem isso, a tela promete um filtro que o motor não aplica.

## 9. Prontidão do código para a decisão (b) — interface segue o aparelho

Estado medido no repositório (2026-10-11), porque a decisão do PO exige infraestrutura que hoje não existe:

|Fato|Evidência|
|---|---|
|**Nenhum catálogo de tradução no app**|não há `*.xcstrings`, `*.lproj` nem `*.strings` fora dos checkouts do GRDB em `bench/run/…/SourcePackages`|
|**Sem `CFBundleLocalizations`**|`plutil -p FeedMineApp/FeedMineApp/Info.plist` não traz chave de localização|
|**Projeto declara inglês como região de desenvolvimento**|`project.pbxproj`: `developmentRegion = en`, `knownRegions = (en, Base)`|
|**As chaves de localização são os próprios textos em português**|346 `String(localized:)` em `Sources/FeedMineUI`, p.ex. `String(localized: "Montar meu feed")`, sem tabela que os traduza|
|**11 textos não são localizáveis de forma alguma**|`Text("Indo atrás do que vale a pena ler")` (`FeedPreparationView.swift:39`), 6 em `FeedLoadingView.swift`, `Text("Salve um artigo…")` (`FeedSavedListView.swift:37`), e o título em inglês `Text("The open web,\narranged by ")` (`ReaderOnboardingView.swift:140`)|

Consequência: "seguir o aparelho" não é trocar um literal — exige criar o catálogo (en + pt-BR), decidir qual
literal é a chave (hoje português, com região de desenvolvimento `en`) e converter os 11 pontos que nunca
localizam. E os rótulos *de dados* (nome de idioma, país, data relativa) têm de ser derivados do **mesmo**
locale da interface — hoje derivam de `Locale.current` (idioma) ou de texto do catálogo (país), que é o
mecanismo da mistura observada.
