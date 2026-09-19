# Solver genético em Bend 2

Um motor de algoritmo genético **genérico e paralelo**, portado do motor em
Rust de [erickweil/my-website](https://github.com/erickweil/my-website)
(`rust-wasm/src/genetic`). O motor não sabe nada sobre o genoma: ele é
polimórfico sobre um tipo `G: Data` qualquer. Quem conhece a representação são
as bibliotecas de operadores e o problema.

```
genetic/
├── ga.bend              # o motor: população, elitismo, torneio, arquipélago
├── operators.bend       # operadores para genoma U32 (32 bits empacotados)
├── stats.bend           # estatísticas agregadas da população em O(log N)
├── LAWS.bend            # 14 leis formais do motor
├── PROOF.bend           # as 14 provas construtivas
├── utils/
│   ├── poptree.bend     # a árvore binária da população
│   ├── bits.bend        # popcount, máscaras, crossover bit a bit
│   └── genes.bend       # operadores para genoma "vetor de genes"
└── exemplos/
    ├── onemax.bend      # genoma U32: maximizar bits ligados
    ├── sorting.bend     # genoma-permutação: ordenar uma lista
    └── tsp.bend         # genoma-permutação: caixeiro viajante
```

## Como rodar

```bash
timeout 60s bend genetic/exemplos/onemax.bend
timeout 60s bend genetic/exemplos/sorting.bend        # aceita uma semente: ... 42
timeout 60s bend genetic/exemplos/tsp.bend            # aceita uma semente: ... 42

timeout 60s bend genetic/PROOF.bend                   # verifica as 14 leis
timeout 60s bend genetic/operators_test.bend          # operadores de bits
timeout 60s bend genetic/utils/genes_test.bend        # operadores de vetor
```

> `bend genetic/LAWS.bend` sozinho reporta TODOs: é só o enunciado, as provas
> moram em `PROOF.bend`. É `PROOF.bend` que deve ser verificado. Pelo mesmo
> motivo, `--checkup` falha nesse par — ele checa cada import isoladamente.

## A forma do genoma

O motor em Rust trata o gene como um `G` qualquer e só os operadores exigem
que seja um `&[G]`. Aqui é igual, com uma restrição que o Bend 2 impõe:

**o genoma precisa ser `Data`.** O motor duplica o campeão para a população
inteira a cada geração (`+champ_g: G`), e só valores `Data` podem ser
duplicados. Isso elimina `Array<T>`, que em Bend 2 é um `Type`: tem
exatamente um dono, não pode receber `+` nem morar dentro de `Ind<G>`.

Sobram duas representações, e o repositório traz as duas:

| | `operators.bend` | `utils/genes.bend` |
|---|---|---|
| genoma | `U32` (32 bits) | `List<&2, A>` |
| tamanho | fixo em 32 | qualquer |
| acesso | bitwise O(1) | varredura O(n) |
| bom para | genomas binários | permutações, vetores, qualquer gene |

A lista encadeada foi escolhida (em vez de uma árvore binária de genes) porque
**todo operador do motor em Rust já é uma varredura sequencial dos pais** —
`crossover_uniform`, `crossover_1_point`, `crossover_2_point` e o OX1 percorrem
os dois pais do começo ao fim. Uma árvore daria acesso aleatório em O(log n),
mas tornaria o OX1 — que precisa manter a ordem relativa dos genes — bem mais
difícil, sem ganho nenhum nos tamanhos de genoma que os exemplos usam.

O AGENTS.md avisava que uma `List` como genoma causaria explosão de nós `dup`
e OOM. **Medido, não acontece**: 1024 indivíduos × 400 gerações com genoma de
64 genes custa 1,3 s e 4,2 MB de residente no binário nativo. O que realmente
custa é acesso indexado via `U32.to_nat` em laço quente — por isso `genes.bend`
indexa tudo com `U32` e nunca aloca um `Nat` dentro da evolução.

## Seleção

O motor oferece duas estratégias, e os exemplos usam as duas:

- **`run_gen_loop`** — todo indivíduo cruza com o campeão global. Pressão
  seletiva máxima, diversidade mínima, uma travessia só. Converge muito rápido
  em paisagens unimodais (é o que o `onemax.bend` usa), e estagna em
  paisagens multimodais.
- **`run_gen_loop_tourney`** — os dois pais saem de **torneios** na geração
  anterior, como no motor em Rust. Como a população é uma árvore binária
  perfeita, sortear um indivíduo é descer `d` níveis escolhendo o lado por um
  bit aleatório: O(log N), sem índice nenhum. É o que `sorting.bend` e
  `tsp.bend` usam — sem torneio, os dois estagnam.

Ambas preservam o **elitismo estrito**: a folha mais à esquerda recebe o
campeão intacto, e a descoberta do campeão da nova geração acontece na mesma
travessia que gera os filhos (o tipo `Gen<G>`).

## O que veio do motor em Rust

| Rust | Bend 2 | onde |
|---|---|---|
| `tournament_selection` | `tournament` | `ga.bend` |
| elitismo explícito em `offspring[0]` | folha de elite em `breed_tree` | `ga.bend` |
| `crossover_uniform` | `cross_uniform` | `genes.bend` |
| `crossover_1_point` | `cross_1point` | `genes.bend` |
| `crossover_2_point` | `cross_2point` | `genes.bend` |
| `CrossoverOX1` | `cross_ox1` | `genes.bend` |
| `mutation_random_swap` | `mut_swap` | `genes.bend` |
| `mutation_neighbor_swap` | `mut_neighbor` | `genes.bend` |
| `mutation_replace` | `mut_replace` | `genes.bend` |
| `mutation_combine` | `chain_mutations` | `operators.bend` |
| `problem_tsp.rs` | `exemplos/tsp.bend` | — |

O `CrossoverOX1` do Rust guarda as marcas num vetor com *epoch* para testar
pertencimento em O(1). Aqui, como o gene de uma permutação é um índice < 32, o
conjunto inteiro de marcas cabe num único `U32` usado como conjunto de bits —
mesma complexidade, sem alocar nada. É por isso que `cross_ox1` está limitado a
32 genes.

**O que não foi portado**, e por quê:

- **Controle de estagnação adaptativo** (`max_stagnation`, multiplicadores de
  mutação, reinício da população). Depende de estado mutável entre gerações; o
  laço aqui é uma recursão pura sobre `Gen<G>`. Cabe, mas exigiria carregar o
  estado no tipo.
- **`diversity_check` por hash.** Precisa de um conjunto compartilhado sendo
  escrito durante a reprodução — é justamente o que a travessia fork-join não
  tem (e não deveria ter, para continuar paralela).
- **Dois filhos por cruzamento.** O motor em Rust cruza em pares e escreve
  `child_a`/`child_b`; aqui cada folha produz um filho, o que mantém a
  travessia da população como um simples `map` paralelo.
- **`f64` como aptidão.** A aptidão aqui é `U32`, porque é comparada milhões de
  vezes dentro da redução em árvore. Problemas contínuos entram com a métrica
  invertida e escalada (veja `tsp.bend`: `BASE - distância*10`).

## Exemplos

**`onemax.bend`** — genoma `U32`, aptidão = número de bits ligados. Converge
para 32/32 em 25 gerações com 32 indivíduos.

**`sorting.bend`** — genoma-permutação. Procura a ordem de leitura que ordena
uma lista de 12 números. Aptidão = pares `(i, j)` com `i < j` já em ordem
(máximo 66), que dá um gradiente muito melhor do que contar vizinhos em ordem.
Converge para o ótimo em 8/8 sementes testadas.

**`tsp.bend`** — genoma-permutação. 12 cidades **sobre uma circunferência**,
listadas fora de ordem. Isso torna o exemplo verificável: a rota ótima de
pontos sobre um círculo é sempre o polígono convexo, de comprimento conhecido
(≈ 3106). O GA encontra exatamente essa rota em 8/8 sementes testadas.

## Leis formais

`LAWS.bend` enuncia e `PROOF.bend` prova 14 invariantes:

1. **Leis 1–7** — a redução de estatísticas em árvore conserva contagem, soma e
   extremos.
2. **Leis 8–11** — os combinadores de `operators.bend` são **definicionalmente
   iguais** ao código escrito à mão (provadas por reflexividade pura): a
   abstração de ordem superior custa zero por construção, não por otimização.
3. **Leis 12–13** — a migração entre ilhas não cria nem destrói ilhas, e a fusão
   de duas meias-gerações soma exatamente as duas populações.
4. **Lei 14** — `take(l, k) ++ drop(l, k) == l`, o invariante que sustenta
   `rotate` e, por consequência, a validade das permutações que o OX1 monta.

Fica **pendente** a invariante central do elitismo — "a reprodução preserva o
tamanho da população". A indução é trivial no papel, mas no caso `Node` as duas
hipóteses precisam ser aplicadas dentro de um `Nat.add` cujos dois lados mudam,
e o motivo de reescrita `%` aceito nessa posição não foi encontrado. A Lei 13 já
cobre a metade difícil.
