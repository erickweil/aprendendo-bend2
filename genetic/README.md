# Solver genético em Bend 2

Um motor de algoritmo genético **genérico e paralelo**, portado do motor em Rust de [erickweil/my-website](https://github.com/erickweil/my-website)(`rust-wasm/src/genetic`). 

## O desenho do motor genético.

- Inicializa a população (gera indivíduos aleatórios para preencher a população até o tamanho definido)
- Para cada geração, até que atinja o limite ou consiga fitness ótimo:
  1. Avalia o fitness de cada indivíduo (se ainda não avaliado).
  2. Realiza seleção por torneio + mutação + reprodução crossover criando a próxima geração
  3. Elitismo: O melhor indivíduo da geração é preservado.

Detalhes:
- A reprodução é **dois pais, dois filhos**: a população não muda de tamanho entre gerações.
- Diversity check: calcula-se o hash dos genes de cada indivíduo, para evitar que indivíduos repetidos sejam escolhidos para reprodução
- Controle de estagnação adaptativo: se a população não melhorar por um número definido de gerações, a taxa de mutação aumenta e o tamanho do torneio diminui. Se a população não melhorar por um número maior de gerações, a população é reiniciada.

## Modelagem do 'Problema'

Um problema é 
- um genoma `G`
- um contexto `P`
- função que cria um indivíduo aleatorio `random_genes(P, seed) -> G`
- função que calcula o fitness `fitness(P, G) -> U32`
- função que aplica mutação `mutate(P, G, rate, seed) -> G`
- função que aplica crossover `crossover(P, G, G, seed) -> (G, G)`
- função que calcula o hash `hash(P, G) -> U32`

Assim qualquer problema pode ser resolvido pelo motor genético, desde que se forneça essas funções. O motor genético é **genérico sobre o genoma `G` e o contexto `P`**.

## Paralelismo: Island Model

Os maiores ganhos com paralelismo se observam ao utilizar modelo de ilhas, e a cada N gerações, as ilhas trocam indivíduos entre si. Isso também permite cada
ilha explorar diferentes regiões do espaço de busca, e evita que a população inteira fique presa em um ótimo local.
