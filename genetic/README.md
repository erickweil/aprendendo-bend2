# Solver genético em Bend 2

Um motor de algoritmo genético **genérico e paralelo**, portado do motor em
Rust de [erickweil/my-website](https://github.com/erickweil/my-website)
(`rust-wasm/src/genetic`). Como no Rust, o motor trata o gene como um tipo
qualquer `G`; só os operadores sabem que ele é um vetor de genes — aqui,
`List<&2, G>`, genérico sobre o tipo de cada gene e **sem limite de tamanho**.

```
genetic/
├── ga.bend              # o motor: GAConfig, torneio, elitismo, estagnação,
│                        # diversity_check, ilhas com migração em anel
├── operators.bend       # cruzamentos: 1 ponto, 2 pontos, uniforme, OX1
├── mutations.bend       # mutações: substituição, troca, vizinhos, combine
├── stats.bend           # estatísticas agregadas da população em O(log N)
├── LAWS.bend            # 14 leis formais
├── PROOF.bend           # as 14 provas construtivas
├── *_test.bend          # testes dos cruzamentos e das mutações
├── utils/
│   ├── poptree.bend     # a árvore binária da população
│   └── genes.bend       # núcleo do vetor de genes + ponte com Array
└── exemplos/
    ├── onemax.bend      # genes Bool, qualquer N (100, 1K, 1M)
    ├── sorting.bend     # genoma-permutação: ordenar uma lista
    ├── tsp.bend         # genoma-permutação: caixeiro viajante
    └── sudoku.bend      # modelo do sudoku.ts; 3 puzzles + quadro vazio
```

## Como rodar

Sempre compilado para nativo — o interpretador tem comportamento e
desempenho fundamentalmente diferentes, e há erros que só o backend nativo
acusa.

```bash
bend genetic/exemplos/onemax.bend -o bin/onemax
./bin/onemax                          # 100 genes, 300 gerações, 8 ilhas x 8
./bin/onemax 1000000 10 3 1 42        # N GERAÇÕES ILHAS POP SEMENTE
./bin/onemax 100000 20 --threads 8    # opções do runtime depois dos argumentos

bend genetic/exemplos/sorting.bend -o bin/sorting && ./bin/sorting 42
bend genetic/exemplos/tsp.bend -o bin/tsp && ./bin/tsp 42       # SEMENTE [N cidades]
bend genetic/exemplos/sudoku.bend -o bin/sudoku && ./bin/sudoku 42 1   # SEMENTE PUZZLE ...

bend genetic/PROOF.bend               # verifica as 14 leis
for t in genetic/utils/genes_test genetic/operators_test genetic/mutations_test genetic/ga_test; do
  bend $t.bend -o bin/t && ./bin/t
done
```

> `bend genetic/LAWS.bend` sozinho reporta TODOs: é só o enunciado, as provas
> moram em `PROOF.bend`. Pelo mesmo motivo, `--checkup` falha nesse par.

## O motor

Como o `GAProblem` do Rust, o problema fornece quatro templates, e todos
recebem o **contexto** `P` — o `&self` do Rust (as cidades, as dicas do sudoku,
o tamanho N). Sem ele, um template não teria como ler dado de runtime.

```
~init   : P -> U32 -> G               random_genes
~fit    : P -> G -> U32               fitness (maior é melhor)
~hash   : P -> G -> U32               hash (para o diversity_check)
~cross  : P -> G -> G -> U32 -> G & G crossover: dois pais, dois filhos
~mutate : P -> G -> U32 -> U32 -> G   mutate(ctx, genes, taxa por gene, semente)
```

O motor faz o resto, com uma `Config` que espelha o `GAConfig`:
`cross_rate`, `mut_rate`, `gene_rate`, `tsize`, `max_stag`, `max_fit`,
`pop_d` (2^pop_d indivíduos por ilha) e `diversity`.

- **Dois pais, dois filhos**, como no Rust: a reprodução desce a árvore até
  pares de folhas, e cada par é um cruzamento (ou, sem o sorteio, uma cópia dos
  dois pais) com a mutação sorteada para cada filho. O par mais à esquerda é o
  campeão intacto mais um filho de um pai só — o `offspring[0]` e o resto
  ímpar do Rust.
- **Seleção por torneio** e **elitismo estrito** (o `offspring[0]` do Rust).
  O segundo pai exclui o índice do primeiro e, com `diversity`, também todo
  candidato com o mesmo hash (o `exclude_hash` do Rust). Os torneios rodam
  numa passada sequencial por ilha, ANTES da reprodução, sobre um retrato da
  população num `Array` local (aptidão e hash de cada índice): descer a árvore
  compartilhada custava ~170 ns por sorteio, ler o `Array` custa ~3 ns. A
  reprodução paralela só desce a árvore para buscar os dois genomas de cada
  par. Medido no sudoku: −11% com torneio de 10, −30% com torneio de 40.
- **Hash guardado no indivíduo** (`Ind{gene, fit, hash}`, 0 = desconhecido,
  como o `Option` do Rust): com `diversity`, calculado quando o filho nasce,
  como no Rust — dentro da reprodução, que é paralela, e não na passada de
  diversidade, que é sequencial por ilha. O elite leva o seu adiante, e o
  torneio exclui por hash lendo o retrato.
- **Controle de estagnação adaptativo**, como no Rust: após `max_stag/2`
  gerações sem melhora a taxa de mutação cresce e o torneio encolhe; em
  exatamente `max_stag/2` o melhor já encontrado é reintroduzido; acima de
  `max_stag` a população é reiniciada (o melhor continua guardado).
- **Parada** ao atingir `max_fit`.
- **`diversity_check`**: no Rust há um `HashSet` escrito durante a reprodução,
  o que tarefas paralelas não podem ter. Aqui é uma passada depois da
  reprodução, sequencial dentro da ilha: os hashes são marcados num conjunto de
  bits num `Array` local, e quem repetir é mutado de novo (com 4x a taxa, para
  compensar a falta das novas tentativas com outros pais), re-hasheado, e o
  hash novo é marcado. O elite nunca é tocado. Os hashes já chegam prontos da
  reprodução; o que sobra de sequencial é marcar o conjunto e remutar os
  repetidos. Medido no sudoku (1 thread): a checagem custa ~30% da geração,
  metade hash e conjunto, metade remutação. Foi o que fez o sudoku funcionar:
  com torneio de 10 e sem ele, 0 de 6 sementes resolviam o puzzle fácil; com
  ele, 6 de 6.
- **Arquipélago com migração em anel**: cada ilha recebe o melhor da vizinha,
  injetado num indivíduo comum (não no elite). Uma primeira versão copiava o
  campeão global para o elite de todas as ilhas a cada época, e as ilhas
  convergiam todas para o mesmo mínimo local.

`run_island` evolui uma população; `run_archipelago`, várias em paralelo.

## O vetor de genes

**O genoma precisa ser `Data`**: o motor duplica o campeão para a população
inteira a cada geração, e um parente escolhido por vários torneios é lido por
vários filhos. Isso elimina `Array<T>`, que em Bend 2 é um `Type` — um único
dono, sem `+`. Sobra a lista encadeada, que espelha o `&[G]` do Rust: todo
cruzamento e mutação de lá já é uma varredura sequencial dos pais.

A lista ainda tem uma vantagem que o vetor não tem: **caudas compartilhadas**.
Depois do corte, um filho do cruzamento de 1 ponto É a cauda do outro pai; depois
da última mutação, o genoma mutado É o original. Os operadores devolvem essas
caudas sem copiar.

E onde acesso aleatório importa, o `Array` entra como **rascunho local**, de
dono único, dentro do operador — no nativo ele é um buffer plano (40 milhões de
acessos aleatórios em 0,09 s):

- o **OX1** marca os genes já copiados num `Array<U32>`;
- a **troca aleatória** converte a lista em `Array`, troca in-place em O(1) e
  converte de volta: O(n) para qualquer taxa, em vez de O(taxa · n²).

### Operadores

Todos genéricos sobre `G`, todos para qualquer tamanho, todos testados com
100 mil genes. Mutação: um genoma produz um genoma. Cruzamento: dois pais
produzem dois filhos. Em todos os operadores do Rust o filho B é o filho A com
os papéis dos pais trocados e os mesmos sorteios; aqui cada operador tem as
duas formas, `child_*` (o filho A, para compor cruzamentos próprios, como o do
sudoku por linha) e `cross_*` (o par `(child(a, b, s), child(b, a, s))`).

Montar os dois filhos numa varredura só, devolvendo o par a cada gene, foi
medido e descartado: num microbenchmark parecia 2× mais rápido, mas dentro do
GA deixou o motor 1,6× a 3,4× mais lento (veja o AGENTS.md, Armadilha 8).

| Rust | Bend 2 | observação |
|---|---|---|
| `crossover_1_point` | `Op.cross_1point` | corte em [0, n); copia os prefixos, compartilha as caudas |
| `crossover_2_point` | `Op.cross_2point` | cortes distintos; dois *splices* por filho, caudas compartilhadas |
| `crossover_uniform` | `Op.cross_uniform` | uma moeda por posição para os dois filhos |
| `CrossoverOX1` | `Op.cross_ox1(~G, ~key, a, b, n, keys, seed)` | `~key` e `keys` são o `get_index` e o `possible_gene_values` do Rust; mesmos cortes nos dois filhos; marcas num `Array` |
| `mutation_replace` | `M.mut_replace(~G, ~gen, …)` | |
| `mutation_random_swap` | `M.mut_swap(~G, …)` | via `Array`, O(n) |
| `mutation_neighbor_swap` | `M.mut_neighbor` | vizinha da esquerda ou direita, com volta, via `Array` |
| `mutation_combine` | `M.combine(~G, ~ma, ~mb, fa, fb, …)` | cada operador com sua fração da taxa; aninhável |
| `for_each_poisson` | `R.gap` | salto geométrico entre mutações |
| `poisson_knuth_sample` | `R.poisson` | quantidade de mutações (usado no sudoku) |
| `tournament_selection` | `GA.tournament` | por índice, O(log N) por sorteio; o 2º pai exclui o 1º |

Todas as mutações têm a mesma assinatura final `(lista, n, taxa, semente)`,
para que `combine` possa compô-las — `M.combine(~U32, ~M.mut_swap(~U32),
~M.mut_neighbor(~U32), 0,5, 0,5, …)` é o `mutation_combine` do TSP do Rust
(templates aninhados funcionam desde o bend 2.0.16). A substituição usa o salto
geométrico do `for_each_poisson` e devolve a cauda compartilhada depois da
última mutação.

### Aleatoriedade

`utils/random.bend` concentra o gerador e tudo sobre Poisson. O passo é
xorshift32 com uma guarda no zero: a versão anterior tinha um **estado
absorvente** (`step(0) = 0`), e para a semente 3783986154 o `split.snd` caía
nele — dali em diante todo número daquele ramo era 0. Os `split.*` são fluxos
com constantes distintas (antes `split.fst` era literalmente `step`). Para
transformar semente em probabilidade ou índice, `mix` aplica meio `lowbias32`.
Um hash completo por passo, no estilo SplitMix, foi medido: custa o dobro, e o
gerador é chamado em quase toda operação. `R.hit`, `R.range`,
`R.range_except`, `R.bool`, `R.unit`, `R.gap` e `R.poisson` são validados
estatisticamente em `utils/random_test.bend`.

**Taxas** são limiares sobre 2^32 (`R.per(num, den)`, `R.hit(seed, limiar)`),
porque o `R.chance` de 1% não expressa uma taxa por gene de 1/N com N = 1 milhão.

## Paralelismo

No Bend 2 o paralelismo só existe onde se escreve a chamada paralela
`a b = f(x) g(y)`, e o escalonador é fork-join binário sem roubo de trabalho.
Medido no nativo:

| seleção | 1 → 12 threads |
|---|---|
| torneio sobre a população inteira (versão antiga) | **1,4×** |
| torneio dentro de cada ilha | **2,8×** |

O torneio global fazia toda tarefa segurar uma cópia `+pop` da geração
anterior, liberada só no fim e por uma thread. Por isso o motor paraleliza no
nível das ilhas.

**Qual é o teto desta máquina?** O i5-1245U (15 W, 2 núcleos P com HT + 8 E)
limita muito o trabalho contínuo de CPU: 8 tarefas **idênticas e totalmente
independentes**, só contas, escalam no máximo **1,7×**; 64 tarefas, **2,6×**,
e nada melhora além de 4 threads (limite de potência derruba o clock com todos
os núcleos ocupados). O `pow2` do GUIDE, com tarefas minúsculas, chega a 3,2× e
é uma referência otimista. Nessa régua, o sudoku (1,65–1,9×) e o OneMax
(2,5–2,8×) estão perto do teto. A exceção é uma ilha só: a seleção e a
passada de deduplicação são sequenciais por ilha (Amdahl), e uma ilha de 512
ganha pouco com threads (sudoku: 0,72 s com 1 thread, 0,63 s com 4) — use
várias ilhas.

### Escala (OneMax, nativo)

| N genes | população | gerações | 1 thread | 12 threads | memória |
|---|---|---|---|---|---|
| 100 | 8 × 8 | 300 | 0,13 s | 0,19 s | 2 MB |
| 1 000 | 8 × 8 | 300 | 1,36 s | 0,60 s | 4 MB |
| 100 000 | 8 × 8 | 20 | 6,59 s | 2,61 s | 160 MB |
| 1 000 000 | 4 × 4 | 10 | 7,33 s | 4,94 s | 420 MB |

Com 8 ilhas o ganho satura em 8 threads (nunca há mais de 8 tarefas pesadas).
E com a mesma forma e o mesmo trabalho total, o ganho cai conforme os genomas
crescem — 3,16× com 10 mil genes, 2,62× com 100 mil, 1,45× com 1 milhão: acima
de alguns MB por genoma o limite passa a ser a banda de memória, não o motor.

## O que não foi portado

- **`CrossoverIPX`** (multiconjuntos, usado nos horários) — ainda não.
- **`mutationShiftSwapOperator`** (TS) — ainda não.
- **Varredura quando o torneio exclui todos** — se todo candidato sorteado tem
  o hash do primeiro pai, o Rust varre a população atrás de um hash diferente;
  aqui o pai sai de um sorteio que exclui só o índice (com diversity_check a
  população quase não tem repetidos).
- **`f64` como aptidão** — aqui é `U32`, comparada milhões de vezes na redução
  em árvore; métricas contínuas entram invertidas e escaladas (veja `tsp.bend`).

## Exemplos

**`onemax.bend`** — porte direto do `problem_onemax.rs`: genes `Bool`,
cruzamento de 1 ponto com 90%, mutação com 90% e taxa por gene 1/N, torneio de
5. Com 100 genes chega a 100/100 por volta da geração 60.

**`sorting.bend`** — genoma-permutação que ordena 12 números. Aptidão = pares
`(i, j)` com `i < j` em ordem (máximo 66). Converge em 8/8 sementes testadas.

**`tsp.bend`** — 12 cidades **sobre uma circunferência**, fora de ordem. A
rota ótima de pontos num círculo é o polígono convexo, de comprimento conhecido
(≈ 3106): o exemplo é verificável, e o GA a encontra em 8/8 sementes testadas.

**`sudoku.bend`** — porte do `sudoku.ts`, no mesmo modelo: o genoma é o
quadro inteiro (9 linhas de 9), cada linha começa como permutação de 1–9 com as
dicas no lugar, e a aptidão conta os dígitos que aparecem exatamente uma vez em
cada linha, coluna e caixa (243) mais +8 por dica mantida. O cruzamento faz, por
linha, OX1 (50%) nos dois sentidos, ou dá a cada filho a linha de um dos pais,
como o TS — **e o OX1 pode mover as
dicas**, que ficam presas só pelo bônus: é o caminho por estados inválidos que
tira a busca do mínimo local. A mutação troca duas células livres da mesma
linha; a quantidade de trocas é `R.poisson(81 × taxa)`, uma por quadro em média
com a taxa 1/81. O puzzle 3 é o quadro vazio.

Uma versão anterior travava as dicas por construção (o genoma guardava só as
células livres). Era mais barata por geração, mas empacava em 158–160/162 no
puzzle difícil.

A aptidão percorre o quadro uma vez só, com as 27 unidades num `Array` local
(7 µs por avaliação; a primeira versão, acumulando colunas e caixas em listas,
custava 30 µs).

## Leis formais

`LAWS.bend` enuncia e `PROOF.bend` prova 14 invariantes:

1. **Leis 1–7** — a redução de estatísticas conserva contagem, soma e extremos.
2. **Leis 8–11** — os combinadores (`pipe`, `chain_mutations`, `branch_mut`)
   são **definicionalmente iguais** ao código escrito à mão, provadas por
   reflexividade: a abstração de ordem superior custa zero por construção.
3. **Leis 12–13** — a migração em anel não cria nem destrói ilhas, e a fusão
   de duas meias-gerações soma exatamente as duas populações.
4. **Lei 14** — `take(l, k) ++ drop(l, k) == l`, que sustenta o `rotate` e,
   por consequência, as permutações que o OX1 monta.

Pendente: "a reprodução preserva o tamanho da população" — a indução não fechou
com as reescritas `%` disponíveis; a Lei 13 cobre a metade difícil.
