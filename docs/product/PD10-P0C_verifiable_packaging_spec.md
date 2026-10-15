# PD10-P0C — Empacotamento Verificável (spec do arquiteto)

> Transcrita para o repositório pelo orquestrador omp em 2026-10-15, a partir da spec que o arquiteto
> (ChatGPT, thread de coordenação) escreveu para execução. O texto abaixo é **dele**, na íntegra, sem
> edição. Base de referência citada na spec: `f01d92f034c44f18a81b3beb6c9645f96ac05aee`.

---

PD10-P0C — Empacotamento Verificável

Spec de implementação autorizada pelo arquiteto — P0 de release

1. Repositório, base e entrega

Repositório: github.com/wsmontes/feedmine_v2

Base de referência: f01d92f034c44f18a81b3beb6c9645f96ac05aee (main verificado na elaboração desta spec).

Branch: chatgpt/pd10-p0c-verifiable-release-packaging

Se main avançar antes de iniciar a execução, registrar o novo HEAD e verificar a diferença antes de escolher a base efetiva. Não misturar alterações do P0B nem incorporar automaticamente commits ainda não aceitos.

Entrega: branch isolada, commits identificados, diff, testes e procedimento de validação no Mac. Sem merge, sem upload para TestFlight e sem publicação no repositório público.

O implementador tem autoridade para corrigir os arquivos permitidos, mas não para ampliar o escopo.

2. Objetivo

Garantir que nenhuma nova build de distribuição do FeedMine seja arquivada e enviada sem comprovar qual revisão pública do catálogo contém, de onde ela veio e que os bytes efetivamente empacotados correspondem à revisão validada.

A cadeia verificável é:

Manifesto público → OPMLs declarados → compilador identificado → SQLite compilado → descritor do bundle → archive Release → build identificada por commit.

A cadeia deve falhar de maneira explícita quando qualquer elo não puder ser comprovado.

O catálogo embarcado continua sendo o bootstrap local e offline. O repositório público continua sendo a única autoridade editorial. Nenhuma verificação de release passa a bloquear o primeiro paint em runtime.

3. Defeitos confirmados na base
C-DEF1 — Downloader legado ainda executável

scripts/fetch-catalog.sh:7–13 contém catalog-v1, checksum e tamanho antigos. O script ainda oferece um caminho operacional capaz de instalar bytes que não correspondem ao descritor público atual.

C-DEF2 — Bootstrap dependente da máquina do desenvolvedor

scripts/bootstrap_catalog.py fixa DEFAULT_REVISION = 5 e aponta o compilador para um caminho absoluto sob /Users/.../Documents/GitHub/feedmine/....

O bootstrap já verifica manifesto, inventário, hashes e relatório, mas sua execução não é portável.

C-DEF3 — Release não exige catálogo verificável

scripts/release-testflight.sh verifica somente a existência de catalog.sqlite, sem chamar o bootstrap nem a verificação de integridade/proveniência do par.

C-DEF4 — Archive não é verificado como artefato final

O script comprova SHA Git, bundle ID e build number, mas não obriga a conferência do SQLite e descritor realmente presentes no .xcarchive antes do upload.

C-DEF5 — Ferramenta de publicação prometida e ausente

O README público de wawasoft/feed-repository instrui executar scripts/publish_catalog_update.py, mas esse arquivo não existe no repositório V2.

O manifesto público está atualmente na revisão 5. O contrato de publicação e o de empacotamento precisam ser consistentes, mas são operações distintas.

4. Allowlist
Produção — scripts existentes

scripts/fetch-catalog.sh

scripts/bootstrap_catalog.py

scripts/release-testflight.sh

scripts/verify_product_catalogue.sh

scripts/generate_build_info.sh — somente se necessário para registrar ou verificar a identidade do artefato.

Ferramentas permitidas

scripts/publish_catalog_update.py — novo, para preparar revisões públicas sem push.

No máximo um pequeno helper adicional sob scripts/, se for demonstrado que a validação não pode ser reutilizada sem duplicar o mecanismo existente.

Testes

Tests/ReleaseScripts/test_catalog_packaging.py — novo.

Tests/ReleaseScripts/test_catalog_publishing.py — novo, se o publisher for implementado.

Tests/ReleaseScripts/test_release_preflight.py — novo, se necessário.

Preferir consolidar cenários nos testes existentes ou em um único arquivo quando isso simplificar a suíte.

Documentação

README.md

FeedMineApp/FeedMineApp/Resources/CATALOG.md

docs/IOS_RUN.md

docs/reviews/FEEDMINE_V2_RELEASE_EVIDENCE.md — somente para registrar evidências novas, distinguindo-as de resultados históricos.

FeedMineApp/FeedMineApp/Resources/catalog.manifest.json poderá mudar somente se houver uma revisão pública realmente validada que justifique o novo par. Não modificar apenas para obter testes verdes.

Proibições

Nenhuma alteração em:

bench/, incluindo driver, avaliador, corpus, manifesto e hashes;

Swift de aquisição, runtime, UI, composição ou persistência;

Package.swift, migrações e schema do runtime;

project.pbxproj, exceto se um bloqueio concreto demonstrar necessidade de autorização adicional;

repositório público wawasoft/feed-repository, sem autorização específica.

Não adicionar dependências, serviço permanente, scheduler ou infraestrutura de CI hospedada.

5. Critérios de aceite
C1 — Revisão pública correta em cada build

O processo deve verificar a revisão mais recente validada/disponível do manifesto público no momento da preparação do release.

Não usar 5, 77.443 ou 118 como constantes permanentes para decidir qual revisão empacotar.

Regras:

A revisão pública observada deve ser registrada.

O SHA-256 dos bytes originais de manifest.json deve ser registrado.

O descritor embarcado precisa corresponder ao inventário público completo, não apenas ao primeiro OPML ou à contagem.

Revisão menor, mesmo número de revisão com declaração diferente, ou mudança inesperada do manifesto devem produzir recusa explícita.

Não substituir uma cópia íntegra por dados inferiores ou não verificados.

Indisponibilidade da autoridade durante a preparação não pode ser silenciosamente interpretada como prova de que um catálogo antigo continua sendo o mais recente.

A execução do aplicativo offline continua permitida. A indisponibilidade de rede na preparação de uma nova release é uma situação diferente e deve ser tratada como ausência de verificação, não como sucesso.

C2 — Bootstrap portável e rastreável

Remover a dependência obrigatória de um caminho absoluto específico do Mac.

O bootstrap deve conseguir obter ou receber um compilador explicitamente identificado, incluindo suas dependências auxiliares, e registrar:

Origem do compilador;

commit ou versão identificável, quando aplicável;

SHA-256 dos arquivos relevantes;

comando utilizado;

identidade dos insumos;

versão Python utilizada, quando relevante.

O compilador V1 atualmente depende também de catalog_identity.py. Não basta copiar build_catalog.py isoladamente e afirmar portabilidade.

Pode ser utilizado um checkout de versão fixada do compilador legado ou um caminho explícito fornecido pelo operador, desde que sua identidade seja verificada.

Não autorizar um novo compilador paralelo.

A compilação existente deve continuar exigindo concordância entre file_count, source_count, inventário e bytes produzidos.

Reexecutar o bootstrap com os mesmos insumos verificados deve reaproveitar o resultado legítimo, sem recompilar ou gerar novo checksum apenas por ter sido executado novamente.

C3 — Eliminar o caminho legado incompatível

scripts/fetch-catalog.sh não pode continuar instalando catalog-v1 como catálogo válido para a release atual.

Preferência arquitetural: transformá-lo em uma recusa explícita com instrução para o bootstrap canônico, ou delegar integralmente ao bootstrap existente, caso isso não crie uma segunda interpretação de revisão/proveniência.

Não introduzir downloader alternativo.

C4 — Preflight obrigatório antes do archive

scripts/release-testflight.sh deve validar, antes do xcodebuild archive:

Working tree e commit identificáveis, conforme o contrato atual.

Existência do SQLite e do descritor do recurso.

Correspondência integral entre ambos: tamanho, SHA-256 e schema.

Revisão, inventário público e procedência comprovados.

Compatibilidade do banco com o leitor do app.

Ausência de catálogo do corpus de benchmark.

Falha em qualquer ponto significa abortar antes de arquivar.

Reutilizar o verificador existente, sem criar uma implementação concorrente de cálculo de identidade.

A preparação que modifica os recursos deve ocorrer antes do commit da build. O release não deve baixar ou trocar silenciosamente arquivos depois de fixar o SHA Git que identifica o binário.

C5 — Verificação obrigatória do archive real

Depois de xcodebuild archive e antes de xcodebuild -exportArchive, verificar o artefato:

<archive>/Products/Applications/FeedMine.app

Exigir:

catalog.sqlite presente;

catalog.manifest.json presente;

bytes e SHA-256 do SQLite concordando com o descritor;

descritor do archive correspondente ao descritor previamente verificado;

schema e contagem concordando com o SQLite real;

ausência da marca de corpus Bench;

bundle ID e versão corretos;

SHA Git embutido correspondendo ao commit do release.

Um archive que contenha um catálogo diferente do recurso previamente validado deve falhar antes do upload.

Não basta verificar o diretório do repositório e presumir que o Xcode copiou os mesmos bytes.

C6 — Evidência de proveniência por build

Cada execução aprovada deve produzir um registro legível por máquina, fora de bench/, contendo no mínimo:

Campo	Origem
Versão e build	Info.plist do archive
Git SHA	HEAD e archive
Revisão pública	Manifesto validado
URL da autoridade	Canal efetivamente consultado
SHA-256 do manifesto público	Bytes recebidos
Número de OPMLs	Inventário validado
Número de fontes	Manifesto e relatório de compilação
Identidade do compilador	Fonte/versão/hash verificados
SHA-256 do SQLite	Arquivo efetivo
SHA-256 do descritor	Recurso/archive
Resultado do preflight	Verificações executadas
Resultado do archive	Verificação do artefato final

A evidência pode ficar em .build/ ou diretório de evidências definido pelo operador.

Não salvar API keys, tokens, certificados privados ou credenciais.

Não declarar reconstrução bit a bit garantida quando o compilador introduz um timestamp no banco. O requisito é rastrear e verificar os bytes exatos distribuídos, além da origem e do processo de derivação.

C7 — --dry-run representa a barreira real

O --dry-run precisa executar as validações pertinentes e demonstrar que o archive está correto.

Não pode fazer upload, criar tag ou modificar o repositório remoto.

Se não houver upload, não deve exigir desnecessariamente credenciais de App Store Connect apenas para testar o empacotamento.

O caminho de release real e o dry-run devem reutilizar as mesmas verificações, e não dois conjuntos de regras diferentes.

C8 — Falhar fechado, com regressões negativas

Os testes devem introduzir deliberadamente:

SQLite ausente;

descritor ausente;

checksum alterado;

tamanho alterado;

manifesto público com inventário divergente;

alteração de um OPML sem atualização do manifesto;

mesma revisão com declaração diferente;

revisão mais recente que a efetivamente empacotada;

compilador ausente ou diferente do esperado;

relatório de compilação incompatível;

catálogo de benchmark injetado;

bundle válido no repositório, mas archive com catálogo diferente;

falha na validação pré-archive.

Para cada cenário, exigir exit não zero e mensagem que identifique a causa.

Nos testes de release, usar executáveis simulados/instrumentados para verificar que uma falha anterior impede chamar upload e criação de tag. Não executar uploads reais.

Os testes unitários de script devem usar fixtures locais e não depender da disponibilidade momentânea do GitHub.

C9 — Publicador do catálogo público

Implementar scripts/publish_catalog_update.py como ferramenta de preparação de publicação, sem push automático.

A ferramenta deve:

Receber explicitamente a árvore editorial de origem e o destino público, sem depender de caminhos pessoais.

Detectar adições, remoções e alterações de OPML.

Preparar um inventário completo e consistente.

Calcular tamanho e SHA-256 de cada arquivo.

Produzir schemaVersion, fileCount e sourceCount a partir de entradas verificadas, sem estimar a contagem.

Exigir incremento monotônico de revisão quando o conteúdo mudar.

Recusar alterações de bytes mantendo a mesma revisão.

Permitir inspeção/dry-run antes de aplicar mudanças ao checkout público.

Não fazer commit, push, force-push ou alteração remota sem uma operação explícita e separada.

Permitir que o bootstrap do aplicativo consuma o resultado publicado sem adaptação especial.

A ferramenta não deve copiar automaticamente um catálogo para Resources/ como efeito colateral de preparar uma revisão pública. A próxima build continua passando pelo bootstrap e pelos gates C1–C6.

O README público atualmente apresenta um comando que pressupõe a existência desse publicador. Se o CLI implementado exigir argumentos adicionais, registrar exatamente a correção documental necessária.

Não editar o README nem o manifesto de wawasoft/feed-repository neste gate. Uma alteração naquele repositório exige branch e autorização próprias. Se a compatibilidade documental não puder ser fechada sem essa alteração, reportar P0C-PUBLISH-DOC — EXTERNAL BLOCKER, sem esconder o problema.

6. O que main deve garantir após integrar P0C

Após o merge, toda nova build de distribuição feita pelo caminho oficial deve satisfazer:

G1. O operador não consegue usar catalog-v1 silenciosamente como substituto da revisão pública verificada.

G2. A revisão do catálogo não é escolhida implicitamente por uma constante histórica ou por um caminho da máquina.

G3. O par catalog.sqlite + catalog.manifest.json é validado antes de iniciar o archive.

G4. O par copiado para o .xcarchive é novamente validado antes de permitir upload.

G5. Uma falha de integridade impede envio e criação de tag que sugira sucesso.

G6. Cada build possui identidade Git e identidade de catálogo verificáveis, vinculadas aos bytes efetivamente distribuídos.

G7. A alteração de uma revisão pública é um processo explícito, verificável e distinto do empacotamento de uma build.

G8. Ausência de rede durante a leitura do app não impede o uso do catálogo local; nenhuma validação nova é introduzida no caminho de primeira apresentação.

A Build 45 já distribuída mantém seu pareamento histórico. P0C protege as próximas builds, não reescreve retrospectivamente as anteriores.

7. Execução e provas no Mac

O implementador deve entregar comandos e resultados disponíveis no ambiente dele, sem declarar PASS para testes que não executou.

Validação requerida:

bash -n nos shell scripts modificados.

python3 -m unittest nos testes novos de scripts.

Testes positivos e negativos de manifesto, compilador, integridade e empacotamento.

swift build e swift test completos para verificar ausência de regressões.

git diff --check.

No Mac: um --dry-run do release, usando o par real derivado do catálogo público, e verificação independente do archive gerado.

Provar que trocar um byte do SQLite ou do descritor provoca recusa antes do upload.

Conferir que o diff não contém bench/, runtime, credenciais nem modificações não autorizadas.

A limitação atual de disco (B03) não autoriza reduzir a exigência de integridade. Se o archive não couber, registrar BLOCKED — DISK nessa medição, mantendo as provas de scripts separadas.

8. Restrições arquiteturais

Não criar outro pipeline de catálogo.

Não criar outro compilador.

Não adicionar dependências ou serviços.

Não tocar nos bancos pessoais do usuário.

Não modificar regras de aquisição, feed, runway ou publicação.

Não fazer download ou validação remota como dependência da primeira apresentação.

Não interpretar sourceCount igual como prova de catálogo igual.

Não substituir verificação criptográfica dos bytes por nome de arquivo, timestamp ou etiqueta de versão.

Não aceitar sucesso parcial como sucesso de release.

Não fazer upload nem merge.

Se uma correção exigir owner fora da allowlist, parar a parte afetada e reportar arquivo:linha, causa e menor extensão necessária, antes de qualquer alteração.

9. Entrega obrigatória

Apresentar:

Branch, base, commits e SHA final.

Inventário exato dos arquivos modificados.

Explicação do caminho canônico de preparação e verificação.

Resultado individual C1–C9: PASS, FAIL, PARTIAL, NOT_RUN ou BLOCKED, sempre com evidência.

Resultados dos testes positivos e negativos.

Exemplo real de registro de proveniência, sem credenciais.

Procedimento de validação nativa no Mac.

Limitações restantes, especialmente qualquer dependência documental externa do repositório público.

Critério de aceite: uma release só alcança o ponto de upload se o catálogo que ela efetivamente contém puder ser relacionado, por evidência verificável, aos insumos públicos validados e ao commit identificado da build.

Não confundir P0C aprovado com release público certificado. B03, B06, P0B/P0D e os demais gates de produto continuam independentes.

Ordem sugerida de implementação: primeiro fazer release-testflight.sh exigir o verificador existente e validar o archive; em seguida tornar o bootstrap portável e eliminar fetch-catalog.sh; depois fechar proveniência, testes negativos e o publisher. Evitar começar pelo publisher enquanto o caminho atual ainda permite upload sem validar o catálogo.
