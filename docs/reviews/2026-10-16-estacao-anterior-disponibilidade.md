# Disponibilidade das evidências físicas da estação anterior (2026-10-16)

A rodada de 2026-10-16 (build 48 no TestFlight, a reabertura medida, o ensaio curto do B06) foi executada
na **estação anterior**. Depois do corte da migração, esta máquina tem o repositório, as refs e os logs
versionados — mas **não** tem os brutos pesados. Este documento registra o que ficou para trás, o que
ainda dá para alcançar pela rede e o que só o dono pode destravar.

## 1. Ausentes nesta máquina, preservados na estação anterior

| Evidência | Onde vivia na estação anterior | Estado aqui |
|---|---|---|
| Pacote do ensaio curto do B06 | `bench/run/20261016T184556Z/b06` (29 MB de artefatos por instrumento) | **AUSENTE** |
| Traços da corrida F48-HITCH | `/tmp/hx-run-control`, `/tmp/hx-run-branch`, `/tmp/hx-run-control-v1-b-falhou` (citados em `docs/reviews/2026-10-16-rodada-entrega-48.md` §6) | **AUSENTE** |
| Traços F48-HITCH-X | família das corridas de hitches da mesma rodada, em `/tmp/hx-run-*`; o nome exato do diretório **não está versionado** neste repositório | **AUSENTE** |
| Os 13 `.xcresult` da rodada da build 48 | derived data / `Logs/Test` da estação anterior | **AUSENTE** |
| Archive da build 48 | pareado com `03d05f5f4bfff9ec0ce6c3be3f4a78ef5073c38f` | **AUSENTE** |

São exatamente os itens que `docs/reviews/2026-10-16-rodada-entrega-48.md` §4 declara **preservados**
("os 13 `.xcresult`, o archive da 48 e todos os brutos") e que a tabela do corte da migração classificou
como **não copiados de propósito** por serem "recriável". Ver §5: o arquiteto corrigiu essa classificação
para estes itens.

O que **está** aqui: os dois logs crus da rodada 48 versionados em
`docs/reviews/evidence/2026-10-16-rodada-48/` (com o registro de redação em
`docs/reviews/evidence/REDACTION.md`), o registro de ambiente do B06
(`docs/reviews/2026-10-16-b06-registro-de-ambiente.md`) e os vereditos e relatórios das rodadas
anteriores em `docs/reviews/evidence/**`.

## 2. A estação anterior está viva

Medido nesta retomada, daqui:

| Medida | Resultado |
|---|---|
| Alcance pela rede | `192.168.1.76` responde ping, **~55 ms** |
| Corpus congelado na porta 8757 | **servido, byte a byte igual ao congelado** |
| Paridade do corpus | conferida contra a própria saída de `bench/serve.py` — índice e totais de `/`, totais de `/_totals` e `{"status":"ok",...}` de `/health` |

Os valores que a resposta tem de reproduzir são os congelados, registrados em `bench/README.md` §Measured
e nos vereditos: **fontes 2305**, **itens 15917**, elegíveis por perfil **A=942 / B=1123** e
**A=6885 / B=8112 itens**, `empty_documents 75`, `slow_media_sources 231`, `canonical_shared 270`,
protocolos `{atom 587, rss 1285, jsonfeed 433}`.

A conferência pode ser refeita com o verificador que já vive no repositório — ele fala com o `serve.py`
remoto e compara o corpus inteiro, não uma amostra:

```sh
python3 bench/transport_variant.py --host 192.168.1.76:8757 --verify-only
# esperado: fontes: 2305 | itens: 15917 ; reversibilidade: 4616 comparações, 0 divergências ; exit 0
```

E, direto nos três endpoints que o `bench/serve.py` expõe:

```sh
curl -s http://192.168.1.76:8757/        # índice em texto + totais do corpus
curl -s http://192.168.1.76:8757/_totals # os mesmos totais em JSON
curl -s http://192.168.1.76:8757/health  # {"items":15917,"sources":2305,"status":"ok"}
```

Ou seja: a estação anterior **serve o corpus**, e serve o corpus certo. Ela não serve mais nada.

## 3. Nenhum acesso a arquivo

As portas por onde os brutos poderiam sair estão **recusadas**, todas medidas nesta retomada:

| Porta | Serviço | Estado |
|---|---|---|
| 22 | Remote Login (SSH/SCP/SFTP) | **recusada** |
| 445 | SMB (Compartilhamento de Arquivos) | **recusada** |
| 139 | NetBIOS/SMB legado | **recusada** |
| 5900 | Compartilhamento de Tela (VNC) | **recusada** |
| 3283 | Apple Remote Desktop | **recusada** |

O único serviço que responde é o transporte do corpus na 8757, que entrega o corpus congelado — e só ele.
Não há caminho de rede para `bench/run/20261016T184556Z/b06`, para os traços F48-HITCH / F48-HITCH-X,
para os 13 `.xcresult` nem para o archive.

## 4. O que destrava a recuperação

A recuperação é uma ação do **dono**, na estação anterior, e é pequena: ligar **Compartilhamento de
Arquivos** (porta 445) ou **Login Remoto** (porta 22) em Ajustes do Sistema → Geral → Compartilhamento.
Sem uma das duas, nenhuma cópia é possível daqui, e nada deve ser tentado por outro caminho.

Depois de ligada, a cópia é o passo trivial — o que exige cuidado é a **conferência**:

```sh
# na estação anterior, no diretório que contém os brutos (após a recuperação):
find bench/run/20261016T184556Z /tmp/hx-run-* -type f -print0 \
  | sort -z | xargs -0 shasum -a 256 > /tmp/fm-station-20261016.SHA256SUMS

# na máquina que recebeu:
shasum -c /tmp/fm-station-20261016.SHA256SUMS   # toda linha tem de sair "OK"
```

Os insumos congelados se conferem pelos manifestos que já estão versionados, com a mesma ferramenta
(`shasum -c`):

```sh
shasum -a 256 -c bench/EVALUATOR.sha256   # 6/6 OK — caminhos relativos à raiz do repositório
(cd bench && shasum -a 256 -c MANIFEST.sha256)   # 2314 entradas — caminhos relativos a bench/
```

Se os brutos recuperados tiverem de ser citados num relatório, o hash deles entra pelo mesmo caminho dos
demais: o sha256 dos bytes **publicados** acompanha o arquivo, e a redação de identificadores
(`docs/reviews/evidence/REDACTION.md`) é aplicada antes de qualquer publicação na ponta.

## 5. Parecer do arquiteto: evidência histórica, não cache

A tabela do corte da migração tratou `.xcresult`, `bench/run/**` e derived data como **recriável**. Para
os itens da §1 isso está **errado**, e o arquiteto deu o parecer em 2026-10-16:

- uma corrida **refeita** não é a mesma evidência: ela mede outro aparelho, outro disco, outro momento, e
  não substitui o testemunho do que foi medido na rodada da build 48;
- portanto esses brutos **não são cache**: são evidência histórica da rodada, e a perda deles é perda de
  evidência, não economia de espaço;
- a ausência fica **registrada** (este documento) em vez de silenciada, e a recuperação é do dono, pelo
  caminho da §4 — sem inventar acesso.

Enquanto isso, o que a ausência **não** muda: os vereditos e relatórios das rodadas anteriores continuam
versionados, os dois logs crus da rodada 48 continuam versionados e a reabertura medida continua provada
por eles. O que fica pendente é a leitura dos brutos por instrumento — não a conclusão da rodada.
