# Parecer do PO sobre a leitura local — visual e final (2026-10-11)

Recebido no thread do PO ("Assumir papel de PO"), sobre a mensagem de aceite
(`2026-10-11-reading-acceptance-for-po.md`) e a evidência (`2026-10-11-reading-implementation-evidence.md`),
ambas publicadas. O PO avaliou os oito critérios um a um.

## Parecer, critério a critério (verbatim)

|Critério|Parecer do PO|
|---|---|
|1. Leitura local sem rede|**Aceito funcionalmente.** O leitor usa dados locais e não inicia requisições. **O teste não comprova desconexão global do iPhone.**|
|2. Conteúdo parcial identificado|**Aprovado.** Nenhum texto é apresentado como artigo integral sem garantia de completude.|
|3. Acesso direto ao site quando falta texto|**Aprovado.** A decisão de navegação foi testada.|
|4. Fonte, título e data|**Aprovado.** Metadados verificados nos testes de interface.|
|5. Preservação da posição|**Aprovado.** Mesmo card, deslocamento de 0,0 pt.|
|6. Dynamic Type|**Funcionalmente aprovado, com ressalva visual.** Texto adapta-se ao tamanho máximo, mas **a ação do cabeçalho trunca**.|
|7. Leitura local durante falha de conexão|**Aprovado no cenário testado.** Transporte do aplicativo bloqueado; **Safari e conectividade global não foram testados offline**.|
|8. Nenhuma aquisição pelo leitor|**Aprovado.** Zero requisições no transporte controlado.|

E a distinção que ele fez questão de registrar, e que é exatamente o limite que eu havia declarado:

> "A distinção importante é que **o teste de transporte bloqueado prova a independência do leitor em relação à
> aquisição do aplicativo**, mas não uma experiência totalmente offline do sistema, incluindo o Safari."

## Estado das duas ressalvas

1. **Ação do cabeçalho truncando no tamanho de acessibilidade máximo** (critério 6) — observação real, medida na
   captura `3-fonte-grande.png` e já registrada como refinamento em `2026-10-11-reading-implementation-evidence.md`
   (§Limites, item 5): o rótulo vira "Abrir…", a ação continua disponível, o rodapé fica inteiro e a
   acessibilidade anuncia "Abrir no site". **Correção proposta, ainda não executada** (é mudança de produto; o
   desenho é do arquiteto): no cabeçalho, usar um controle com rótulo visual curto e rótulo de acessibilidade
   completo — o que existe hoje é um `Text` de uma linha que trunca.
2. **Escopo do teste de rede** (critérios 1 e 7) — não é defeito e não há o que corrigir no produto: o leitor
   local não faz requisição nenhuma (zero, medido em processo), então a conectividade do Safari é irrelevante para
   ele. O que os testes **não** provam, e o PO corretamente apontou, é uma experiência offline de sistema inteiro.
   Num aparelho físico não há como desligar a rede pelo XCUITest; a alternativa honesta é medir o que importa
   (zero requisições do leitor) em vez de simular o que não dá para controlar.

## O que isto encerra

O aceite funcional e o parecer visual estão dados, com as ressalvas acima **nomeadas** em vez de varridas. Nenhuma
delas contradiz o que foi entregue; a primeira é um refinamento visual de produto e a segunda é um limite de
instrumento, declarado desde o diagnóstico.
