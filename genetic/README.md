# Solver genético em Bend 2

Um motor de algoritmo genético **genérico e paralelo**, portado do motor em
Rust de [erickweil/my-website](https://github.com/erickweil/my-website)
(`rust-wasm/src/genetic`). Como no Rust, o motor trata o gene como um tipo
qualquer `G`; só os operadores sabem que ele é um vetor de genes — aqui,
`List<&2, G>`, genérico sobre o tipo de cada gene e **sem limite de tamanho**.

```
genetic/
├── ga.bend              # o motor: população, elitismo, torneio, arquipélago
├── operators.bend       # cruzamentos: 1 ponto, 2 pontos, uniforme, OX1
├── mutations.bend       # mutações: substituição, troca, troca de vizinhos
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
    └── tsp.bend         # genoma-permutação: caixeiro viajante
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
bend genetic/exemplos/tsp.bend -o bin/tsp && ./bin/tsp 42

bend genetic/PROOF.bend               # verifica as 14 leis
for t in genetic/utils/genes_test genetic/operators_test genetic/mutations_test; do
  bend $t.bend -o bin/t && ./bin/t
done
```

> `bend genetic/LAWS.bend` sozinho reporta TODOs: é só o enunciado, as provas
> moram em `PROOF.bend`. Pelo mesmo motivo, `--checkup` falha nesse par.

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
100 mil genes.

| Rust | Bend 2 | observação |
|---|---|---|
| `crossover_1_point` | `Op.cross_1point` | copia o prefixo, compartilha a cauda |
| `crossover_2_point` | `Op.cross_2point` | dois *splices*, cauda compartilhada |
| `crossover_uniform` | `Op.cross_uniform` | |
| `CrossoverOX1` | `Op.cross_ox1(~G, ~key, …)` | `~key: G -> U32` como o `get_index` do Rust; marcas num `Array` |
| `mutation_replace` | `M.mut_replace(~G, ~gen, …)` | |
| `mutation_random_swap` | `M.mut_swap(~G, …)` | via `Array`, O(n) |
| `mutation_neighbor_swap` | `M.mut_neighbor` | |
| `mutation_combine` | `M.chain_mutations` | |
| `for_each_poisson` | `M.gap` | salto geométrico entre mutações |
| `tournament_selection` | `GA.tournament` | sorteio descendo a árvore, O(log N) |

As mutações portam o `for_each_poisson`: sorteiam a **distância até a próxima
mutação** em vez de um número aleatório por gene, e quando a próxima mutação
cairia depois do fim, devolvem o resto da lista compartilhado.

**Taxas** são limiares sobre 2^32 (`R.per(num, den)`, `R.hit(seed, limiar)`),
porque o `R.chance` de 1% não expressa uma taxa por gene de 1/N com N = 1 milhão.

## Seleção e paralelismo

No Bend 2 o paralelismo só existe onde se escreve a chamada paralela
`a b = f(x) g(y)`, e o escalonador é fork-join binário sem roubo de trabalho.
Isso decide o desenho da seleção. Medido no nativo (12 threads num i5-1245U,
2 núcleos P + 8 E; o `pow2` do GUIDE escala 3,2× nesta máquina):

| seleção | 1 → 12 threads |
|---|---|
| todos cruzam com o campeão (`run_gen_loop`) | 1,9× |
| torneio sobre a população inteira (`run_gen_loop_tourney`) | **1,4×** |
| torneio dentro de cada ilha (`run_archipelago_tourney`) | **2,8×** |

O torneio global faz toda tarefa segurar uma cópia `+pop` da geração anterior;
ela só é liberada quando a última tarefa termina, e por uma thread só. No
arquipélago as ilhas não compartilham nada durante uma época — o campeão global
migra para o slot de elite de todas as ilhas entre épocas. É o que o
`onemax.bend` usa.

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

- **Controle de estagnação adaptativo** (`max_stagnation`, multiplicadores,
  reinício da população) — estado mutável entre gerações; cabe carregado no tipo.
- **`diversity_check` por hash** — exigiria um conjunto compartilhado escrito
  durante a reprodução, justamente o que as tarefas paralelas não podem ter.
- **Dois filhos por cruzamento** — cada folha da população produz um filho.
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

## Leis formais

`LAWS.bend` enuncia e `PROOF.bend` prova 14 invariantes:

1. **Leis 1–7** — a redução de estatísticas conserva contagem, soma e extremos.
2. **Leis 8–11** — os combinadores (`pipe`, `chain_mutations`, `branch_mut`)
   são **definicionalmente iguais** ao código escrito à mão, provadas por
   reflexividade: a abstração de ordem superior custa zero por construção.
3. **Leis 12–13** — a migração não cria nem destrói ilhas, e a fusão de duas
   meias-gerações soma exatamente as duas populações.
4. **Lei 14** — `take(l, k) ++ drop(l, k) == l`, que sustenta o `rotate` e,
   por consequência, as permutações que o OX1 monta.

Pendente: "a reprodução preserva o tamanho da população" — a indução não fechou
com as reescritas `%` disponíveis; a Lei 13 cobre a metade difícil.
