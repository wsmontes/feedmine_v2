# Para o PO — leitura local: os oito critérios, cada um com a prova

Mensagem pronta para entrega no thread do PO ("Assumir papel de PO"). Evidência completa em
`docs/reviews/2026-10-11-reading-implementation-evidence.md`.

---

PO — leitura local implementada; resultados medidos para o seu aceite.

Os oito critérios que você fixou, cada um com a prova executada no iPhone físico:

1. **Artigos com texto substancial lidos localmente, sem rede — ATENDE.** Quatro formatos de conteúdo pelos
   fixtures, e no aparelho com o proxy HTTPS fechado do próprio app.
2. **Conteúdo parcial nunca apresentado como completo — ATENDE.** A superfície rotula a origem ("Texto publicado
   pela fonte" / "Resumo fornecido pela fonte") e declara "Conteúdo parcial: o artigo completo está no site" sempre
   que não há garantia de origem — e nunca há.
3. **Artigos sem texto suficiente com acesso simples e rápido ao site — ATENDE.** O toque vai direto ao navegador
   interno, sem tela intermediária.
4. **Fonte, título e data corretos — ATENDE.** Os três na superfície, conferidos na árvore de acessibilidade do
   aparelho.
5. **Abrir e fechar preserva o mesmo card e a posição exata — ATENDE.** Delta 0,0 pt no cartão ancorado, medição
   repetida na superfície nova, como o arquiteto exigiu.
6. **Dynamic Type, inclusive fonte Grande — ATENDE.** No tamanho de acessibilidade máximo a superfície inteira
   escala (captura anexa).
7. **Falha de conexão não impede a leitura local — ATENDE.** Com a rede do app realmente indisponível, o texto
   continua legível.
8. **Nenhuma aquisição iniciada pela renderização do leitor — ATENDE.** Medido em processo: zero requisições de
   rede e nada publicado ao abrir a leitura.

Escopo: a extração integral do texto permanece FORA, como combinado. "Abrir no site" aparece no cabeçalho e ao
final, sem duplicar o texto.

**O que isso significa no catálogo real** (medido no aparelho): dos 173 cartões publicados, 22 já têm 3.000+
caracteres guardados — quase todos do A List Apart, que publica o artigo inteiro no RSS (21 a 31 KB por item).
Esses artigos passam a ser legíveis dentro do FeedMine, sem rede. Fontes que só publicam uma chamada continuam
abrindo o site direto, sem tela vazia no caminho.

**Um limite honesto que eu não quero esconder:** o texto guardado é o que a fonte publicou. Quando ela publica o
artigo inteiro, a leitura é completa — mas o app não tem como *saber* disso, então ele nunca afirma "completo": diz
de onde o texto veio e oferece o site. É a mesma regra que você fixou, aplicada ao pé da letra.

Capturas do aparelho: `reading-body`, `reading-back-in-the-feed`, `reading-large-text`, `reading-offline`,
`reading-explicit-site`, `reading-back-to-the-text` (anexos do resultado de `ReadingSurfaceUITests`).
