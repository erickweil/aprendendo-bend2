# Performance Single-Core do Motor Genético em Bend 2

Documento irmão de [`PARALLELISM.md`](PARALLELISM.md), que trata de escala multicore.
Aqui o assunto é o **custo por indivíduo** — quanto trabalho cada reprodução gasta
num único core.

---

## 1. Harness de Medição

[`bench/run_bench.sh`](bench/run_bench.sh) compila três cargas para binário C nativo
e mede 1, 2 e 4 threads:

| Benchmark | Carga | O que exercita |
| :--- | :--- | :--- |
| [`bench/bench_perm.bend`](bench/bench_perm.bend) | 8 ilhas x 64 ind. x 5.000 gerações = 2,56M reproduções | Seção C de `operators.bend` (OX1, 2-opt, swaps) |
| [`bench/bench_bits.bend`](bench/bench_bits.bend) | idem, genoma `U32` Royal Road | Seção B (crossover 2-point, mutações de bloco) |
| [`bench/bench_gp.bend`](bench/bench_gp.bend) | 4 ilhas x 64 ind. x 1.500 gerações | ADTs em árvore: pattern-matching e alocação de nós |

O harness reporta o **mínimo de 7 execuções**, não a mediana: nesta VM de 4 vCPUs
compartilhadas o ruído é sempre aditivo, então o mínimo é o estimador estável do
custo real. Medir com mediana de 5 produziu variação de até 30% entre execuções do
mesmo binário.

---

## 2. A Descoberta: Avaliação Especulativa em `Bool.pick`

`Bool.pick(T, cond, a, b)` é uma função comum, e o Bend avalia argumentos de
chamada. Portanto **os dois ramos são construídos antes da escolha** e um é jogado
fora. Quando um ramo aloca (um registro, um nó de AST) ou recursa, o desperdício é
proporcional ao ramo descartado — não a uma constante.

O idioma correto está documentado no próprio benchmark `queens` do repositório
oficial do Bend:

> *"a match scrutinizes only a parameter, so every decision bool is computed by the
> CALLER and passed as an argument"*

Ou seja: **não passe alternativas já computadas para quem escolhe; passe os
ingredientes crus e decida com `match` sobre um parâmetro `Bool` dentro do callee.**

Medição isolada ([`bench/micro_pick.bend`](bench/micro_pick.bend)), 4M iterações de
`swap` condicional sobre `Perm8`:

| Forma | Tempo |
| :--- | ---: |
| `Bool.pick(Perm8, c, Perm8.swap(p, i, j), p)` | **180 ms** |
| `Perm8.swap_if(c, p, i, j)` (match sobre parâmetro) | **39 ms** |

**4,6x.** E `Bool.pick` continua ótimo quando os dois ramos já são valores prontos
ou escalares — o problema é só a alternativa *computada e descartada*.

### 2.1 O caso patológico: recursão especulativa

Dois operadores tinham a **chamada recursiva inteira** como argumento de
`Bool.pick`:

```bend
# ANTES: a recursão é sempre executada, e só depois descartada
+rec = perm_reverse_range(q, Perm8.swap(p, lo, hi), lo + 1, hi - 1)
Bool.pick(Perm8, cont, rec, p)
```

O `cont` nunca cortava nada: todo 2-opt pagava os 4 níveis de troca e todo PMX
pagava os 8 níveis de resolução de conflito, independentemente dos dados. A
correção é tornar a condição um **parâmetro** da própria função recursiva, para o
`match` de fato interromper:

```bend
# DEPOIS: o match corta a recursão
def perm_reverse_range(n: Nat, cont: Bool, +p: Perm8, +lo: U32, +hi: U32) -> Perm8:
  match n cont:
    case 0n _:        p
    case 1n+q False{}: p
    case 1n+q True{}:
      ...
      perm_reverse_range(q, U32.is_lt(lo2, hi2), Perm8.swap(p, lo, hi), lo2, hi2)
```

### 2.2 Recursão condicional sem recursão mútua

O Bend proíbe recursão mútua, então não dá para extrair o `match` para um helper
que volta a chamar a função recursiva. A saída é dar à própria função uma flag que
a torna O(1):

```bend
# do_mut = False devolve a expressão intacta em O(1)
def mutate_expr(e: Expr, do_mut: Bool, +rnd: U32) -> Expr:
  match e do_mut:
    case _ False{}:
      e
    case Add{+l, +r} True{}:
      ...
      +ml = mutate_expr(l, U32.is_eq(mode, 1), s1)   # só um dos dois desce
      +mr = mutate_expr(r, U32.is_eq(mode, 2), s1)
      rebuild_add(U32.is_eq(mode, 0), U32.is_eq(mode, 3), ml, mr)
```

`case _ False{}: e` devolve o escrutinado intacto — o padrão que torna a técnica
viável. Os dois filhos são chamados sempre, mas o não sorteado custa um retorno em
vez de uma subárvore inteira.

---

## 3. Onde Foi Aplicado

| Local | Ramo desperdiçado |
| :--- | :--- |
| `operators.bend` `perm_reverse_range` | recursão 2-opt completa |
| `operators.bend` `pmx_resolve` | 8 níveis de resolução de conflito |
| `operators.bend` `ox1_fill` | registro `Perm8` por posição não aproveitada |
| `operators.bend` `pmx_fill` / `pmx_place` | resolução de conflito dentro da fatia |
| `operators.bend` `mut_perm_scramble` | 3 registros `Perm8` por mutação |
| `scenario10_gp` `gen_expr` | 2 subárvores por nível |
| `scenario10_gp` `mutate_expr` | 1 subárvore mutada por nó |
| `scenario10_gp` `crossover_expr` / `reproduce` | nó de AST e mutação completa |
| `scenario4_sudoku` `mutate_sudoku9` | 2 grades 9x9 por mutação |
| `scenario13` `apply_adaptive_mutation` | 2 dos 3 operadores auto-adaptados |
| `scenario5_horario` `reproduce` | um `crossover_tt` |

Os primitivos `Perm8.swap_if` e `Perm8.set_if` ficam em `utils/perm.bend` para
que o padrão seja reutilizável em vez de repetido.

---

## 4. Resultado do Ciclo 1

Mínimo de 7 execuções, binário C nativo:

| Benchmark | Antes (1T) | Depois (1T) | Ganho | Antes (4T) | Depois (4T) |
| :--- | ---: | ---: | ---: | ---: | ---: |
| `bench_perm` | 1605 ms | **596 ms** | **2,69x** | 905 ms | 358 ms |
| `bench_gp` | 561 ms | **400 ms** | **1,40x** | 857 ms | 541 ms |
| `bench_bits` | 299 ms | 303 ms | — | 185 ms | 196 ms |

`bench_bits` não muda, como esperado: o caminho binário é aritmética escalar, onde
`Bool.pick` não desperdiça nada. Isso é confirmação de que o ganho vem exatamente
da fonte identificada, e não de ruído.

Todos os 17 cenários continuam convergindo, as 22 leis continuam válidas e os
cenários refatorados produzem **saída byte a byte idêntica** — é otimização pura,
sem mudança de semântica.

---

## 5. O Genoma Empacotado

`Perm8` era um registro de 8 campos, então cada `swap` alocava dois nós de heap —
e o motor aloca um genoma por indivíduo por geração. Empacotando os 8 elementos
(valores 0..7) em 3 bits cada dentro de uma palavra de 24 bits:

| Representação | 4M swaps |
| :--- | ---: |
| registro de 8 campos | 28 ms |
| `P8{bits: U32}` (1 campo) | **15 ms** |
| `U32` cru, sem tipo | 15 ms |

O construtor de 1 campo custa **exatamente o mesmo que o `U32` cru**. Ou seja, não
é preciso escolher entre segurança de tipo e performance: `Perm8` continua um tipo
distinto, nenhuma aritmética solta pode ser confundida com uma permutação, e ainda
assim o genoma inteiro cabe numa palavra.

Efeito medido no motor (binários antigo e novo intercalados): `bench_perm`
605 ms → 370 ms em 1 thread, **1,64x**.

O corolário de projeto é mais amplo que este tipo: **em Bend, um agregado pequeno
de campos pequenos vale a pena empacotar numa palavra atrás de um construtor de 1
campo.** O mesmo vale para `String16`, `Row9` e `Arr4`.

---

## 6. Por Que o Multicore Não Escalava

Em 4 cores, `pow2` (aritmética pura, zero heap) faz 4,03x. O motor genético fazia
1,6x. As duas primeiras hipóteses estavam erradas, e vale registrar as duas:

**Hipótese 1 — "o gargalo é alocação".** Errada. Um fork-join que aloca e consome
um registro por folha escala 2,9x; e `bench_gp`, o mais alocador de todos, é
justamente o único com escala *negativa*.

**Hipótese 2 — "os problemas são simples demais, falta trabalho por tarefa".**
Errada, e esta foi testada de propósito: `bench_tsp_heavy` usa distância
euclidiana real em F32 com raiz quadrada (~20x mais computação por indivíduo, com
alocação idêntica) e escala 1,69x — nada melhor. `bench_neuro`, que roda 200
passos de simulação física por avaliação, escala 1,85x.

**A causa real é a contagem de tarefas.** O escalonador do Bend é uma máquina
fork-join binária *sem work stealing*: cada tarefa vai para um core uma única vez
e nunca é movida. Medindo com trabalho puro, perfeitamente balanceado, variando só
a profundidade de bifurcação:

| Tarefas | 2 threads | 4 threads |
| ---: | ---: | ---: |
| 4 | 1,81x | 1,90x |
| 16 | 1,81x | 1,81x |
| 64 | 1,81x | **2,92x** |
| 1.024 | 1,81x | **3,17x** |
| 2.097.152 | 1,81x | 3,00x |

Abaixo de ~64 tarefas, os cores 3 e 4 simplesmente não recebem trabalho. E o platô
é largo: mesmo 2 milhões de tarefas de 8 passos cada continuam em 3,0x, então
granularidade fina **não** é intrinsecamente cara.

### 6.1 Mas subdividir a geração é pior ainda

A conclusão acima parece sugerir bifurcar a árvore populacional dentro da ilha. É
o contrário — medido com `fork_d = 3` (8 tarefas por ilha):

| Benchmark | 4T sequencial | 4T com `fork_d = 3` |
| :--- | ---: | ---: |
| `bench_perm` | 268 ms | 855 ms |
| `bench_bits` | 199 ms | 1008 ms |

A diferença em relação ao teste sintético é que lá as tarefas eram criadas **uma
vez** e viviam o programa inteiro. Uma geração é um fork-join completo: com
`fork_d = 3`, 5.000 gerações x 8 ilhas viram 320.000 episódios de bifurcação,
cada um distribuindo microssegundos de trabalho e sincronizando no fim.

O que conta, então, não é "muitas tarefas" e sim **muitas tarefas longevas**. O
parâmetro continua exposto em `GA.run_generations_at` (padrão `0n`) para
populações gigantes com aptidão cara, onde a subdivisão pode compensar.

### 6.2 A regra correta de dimensionamento

Uma ilha é exatamente isso: uma tarefa longeva que roda milhares de gerações sem
sincronizar. Mantendo 64 indivíduos por ilha e variando só a contagem:

| Ilhas | 4 threads |
| ---: | ---: |
| 4 | 1,54x |
| 8 | 1,66x |
| 16 | 1,63x |
| 32 | **2,55x** |
| 64 | **2,8x – 4,2x** |

`bench/bench_islands.bend` (64 ilhas x 64 indivíduos) mede **739 ms → 176 ms em
4 threads, 4,20x**.

> **Regra:** dimensione o arquipélago em ~16x o número de threads, não em 1x.
> Isto corrige a Regra 2 de `PARALLELISM.md`, que dizia `N_ilhas >= N_threads`.

`best_archipelago` e `migrate_champion` passaram a reduzir em paralelo no nível do
arquipélago (uma tarefa por sub-arquipélago, criada uma vez por época). Era a
fração serial de cada época; em 4 cores o ganho fica dentro do ruído, mas a
seção serial deixa de crescer com o tamanho do arquipélago.

---

## 7. Em Aberto

- **`bench_gp` fica mais lento com threads** (0,77x em 4T). É o único benchmark com
  escala negativa e o único cujo genoma é uma árvore de tamanho variável — logo,
  ilhas com trabalho desbalanceado, que num escalonador sem work stealing custam
  caro. Ainda não investigado.
- `bench_bits` e `bench_perm` ainda escalam ~1,6-1,7x com 8 ilhas; re-dimensionar
  os benchmarks para 64 ilhas deve levá-los ao mesmo patamar do `bench_islands`.
- Empacotar `String16` (Cenário 8), `Row9`/`Sudoku9` (Cenário 4) e `Arr4`
  (Cenário 12) da mesma forma que `Perm8`.
