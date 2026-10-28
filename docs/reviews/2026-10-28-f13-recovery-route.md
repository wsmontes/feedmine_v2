# F13 — recuperação real e geometria da cauda — 2026-10-28

Incremento sobre `5e375d2a`. A regressão de posição foi corrigida; F13 integral permanece aberta.

## RED e correção

A jornada real abriu a recuperação, removeu Revista no editor e retornou com a mesma janela de
12 IDs. A última carta admitida mudou de minY 647,4167 para 764,4167: **117 pt**, iguais nas cinco
observações. Resultado oficial `Failed`, uma falha, em `t6-recovery-admitted-stability-tests`.
Capturas e coordenadas foram preservadas; `corrections=0`, `activeWrites=0`.

O resultado é consistente com clamp nativo quando o footer desaparece e encurta o conteúdo rolável.
O corretor de janela só arma com IDs diferentes. O console exportável não estava disponível; não
se declara medida independente de contentSize. A correção remove a causa geométrica sem escrever
posição: com histórico, a recuperação fica no menu **Mais**, sinalizada por eye.slash e valor AX
localizado. O botão existente mantém suas dimensões e abre o mesmo editor. Sem cartas, permanecem
explicação e atalho direto. Não há spacer invisível, nova intenção de navegação ou mudança de PD-4.
O custo assumido pelo implementador é um toque extra; a spec registra a decisão sob autonomia.

## GREEN no estado final

| Verificação | Resultado |
| --- | --- |
| Pacote completo | 1777 testes, um skip, zero falhas; 106,192 s; exit 0 |
| Jornada pt-BR | Passed, 1/0; mesma janela, carta e viewport |
| Jornada en, AX XXXL | Passed, 1/0; altura do nome >30 pt confirma ampliação real |
| ContentFilterTests no mesmo build iOS | Passed, 9/0; exit 0 |

Português: minY **784,4167** antes e nas cinco amostras depois; viewport `(0,122,440,834)` igual.
Inglês: minY **715,0833** antes e nas cinco amostras depois; viewport `(0,126,440,830)` igual.
Ambos: **delta zero**, `corrections=0`, `activeWrites=0`. A pré-condição exige a carta final admitida
visível e seu bottom dentro do viewport após gesto real. Indicador AX presente antes e ausente depois;
lista vazia confirma remoção, além do mero fechamento do menu. Capturas antes/depois inspecionadas.

Build identificado: `t6-chrome-single-batch-capacity-build`, patch SHA-256
`8aa4d4b256b6d0ea35d2369325fd67a5efb28163bf0fbff9133e1db8e6a901fa`.
O diff atual de Sources/FeedMineApp foi comparado com esse hash. Manifestos guardam hashes dos
executáveis, runner, bundle unitário e xctestrun; resultados oficiais `*-summary.json` e geometria
`t6-chrome-recovery-geometry-summary.json` acompanham o relatório. Não é benchmark ou release.

Revisão independente não encontrou P1/P2 no patch. Foram incorporadas as sugestões de delimitar
janela admitida, exigir cauda alcançada e comparar cinco amostras e o mesmo viewport.

## Diagnósticos preservados e limites

A primeira prova parou por TRACE_CAPTURE ausente: falha de configuração, não RED do produto.
A primeira suíte com chrome teve uma falha OCR em 1777 testes: no canvas de 1500 pt, Vision leu
parcialmente Amber apesar da imagem íntegra. A captura diagnóstica comprova as duas cartas; 900/1200 pt
leram ambas. O teste usa o viewport padrão de 900 pt, conservando títulos exatos e IDs. A suíte final
completa passou; logs de todas as tentativas permanecem em gzip verificado.

Revista está fora da supply da fixture; a rede dessa fonte está bloqueada. As capturas anteriores à
remoção mostram seu toast de conexão. O caso prova navegação/editor/remover e geometria, não uma
ausência causada pelas regras ou recuperação causal de supply. Não certifica histórico integral,
publicação inédita A/B, canonical compartilhado, contexto A→B→A ou R4 de palavras. B02/B04/B05 seguem
pendentes; B03/B06 inalterados. O fim de conteúdo definitivo conserva seu componente anterior.

## Capacidade e preservação

Dois builds foram interrompidos pela reserva de 700 MiB; não contam como PASS. O log revelou `-j8`
no Swift mesmo com Xcode `-jobs 1`. O build aprovado usa `-driver-batch-count 1`, mantendo Debug,
sem símbolos/índices e um job. A guarda padrão de benchmark de 3 GiB não foi alterada.

Só intermediários inativos e caches regeneráveis foram removidos. ZIP de atualização Ollama sem
handles e cache Homebrew sem processo/handles foram liberados; instalações/modelos intactos.
Um resultado próprio incompleto foi arquivado em tar.gz, com verificação de todos os hashes antes
de liberar a pasta. Logs fechados de três resultados históricos já incompletos foram comprimidos
em gzip, com SHA-256 descomprimido, modos, mtimes e instruções de restauração nos manifestos.
Resultados completos foram sondados e mantidos originais porque não havia economia útil.

Os manifestos `t6-interrupted-result-archive.json`, `t6-historical-incomplete-log-compression.json`
e `t6-chrome-capacity-preservation.json` identificam os caminhos restauráveis. Bancos, simuladores,
produtos e dados dos resultados foram preservados. O cache do updater ativo Codex foi mantido.
