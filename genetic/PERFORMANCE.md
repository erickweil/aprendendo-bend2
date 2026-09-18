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

## 7. Abrir um Registro Compartilhado Custa uma Cópia

Com os operadores já otimizados, uma ablação mostrou que **o motor era 56% do
tempo** do `bench_perm` (261 ms de 467 ms) — mais caro que os operadores
genéticos. Decompondo o laço geracional, sempre sobre os mesmos 2,56 milhões de
indivíduos:

| O que o laço faz | Custo |
| :--- | ---: |
| só reproduzir (percorre, aloca e reconstrói a árvore) | **28 ms** |
| reproduzir + `tree_size` (percorre todos os nós, sem abrir indivíduos) | 29 ms |
| reproduzir + compartilhar a árvore com um consumidor barato | 22 ms |
| reproduzir + `best_ind` (busca do campeão) | **252 ms** |

A busca do campeão custava **9x mais que a reprodução inteira**, apesar de não
alocar nada. E não era por percorrer a árvore (`tree_size` percorre os mesmos
nós e custa zero), nem por compartilhá-la.

A causa é **abrir um registro compartilhado**. `pick_better` fazia
`Ind.fit(a)` e `Ind.fit(b)` em valores `+`; destruir um nó com contagem de
referências obriga o runtime a copiá-lo antes. São 2 cópias por comparação,
126 por geração.

> **Regra:** em Bend, percorrer uma estrutura compartilhada é de graça, mas
> **abrir** um nó dela custa uma cópia. Se um valor precisa ser lido fora do
> dono, carregue o campo escalar solto em vez do registro.

### 7.1 A geração fundida

A correção foi eliminar a segunda leitura. `breed_tree` faz numa travessia só:

1. o cruzamento de cada indivíduo com o campeão,
2. a injeção do elitismo (a folha de elite recebe o campeão em vez de ser
   criada e depois sobrescrita por `inject_elite`),
3. a descoberta do campeão da nova geração.

A aptidão sobe a recursão como um `U32` solto dentro de `Gen{pop, bfit, bgene}`,
então comparar é aritmética escalar e nenhum registro é aberto. O campeão
atravessa as gerações dentro do `Gen`, e `best_ind` passa a ser chamado uma vez
por ilha em vez de uma vez por geração.

A semântica é exatamente a mesma: como o campeão ocupa a folha de elite, o
máximo calculado durante a construção É o máximo da população resultante — o
mesmo que `best_ind(inject_elite(...))` devolvia.

Medido com os binários antigo e novo intercalados:

| Benchmark | 1T | 4T |
| :--- | ---: | ---: |
| `bench_perm` | 441 ms → **251 ms** (1,76x) | 242 ms → 135 ms |
| `bench_bits` | 285 ms → **102 ms** (2,79x) | 168 ms → 63 ms |
| `bench_islands` | 582 ms → **348 ms** (1,67x) | 195 ms → 116 ms |

`bench_bits` ganha mais porque seu genoma é um `U32` puro: quase todo o custo
dele era o motor. Os 18 programas produzem saída byte a byte idêntica.

Nessa reescrita o parâmetro `fork_d` foi removido — ele media pior em toda
configuração testada (§6.1) e complicava o caminho quente fundido. A medição
que o motivou continua registrada aqui.

---

## 8. Onde o Tempo Vai Agora, e Três Tentativas que Falharam

Reperfilando o `bench_perm` depois da geração fundida (273 ms em 1 thread):

| Parte | Custo | Fatia |
| :--- | ---: | ---: |
| motor (travessia, alocação, elitismo, campeão) | 66 ms | 24% |
| `cross_perm_ox1` | ~104 ms | 38% |
| mutações (`random_swap` / `reverse_segment`) | ~42 ms | 15% |
| aptidão (`tour_distance`) | ~9 ms | 3% |

O motor saiu de 56% para 24%: os operadores passaram a dominar. Três tentativas
de atacá-los **não deram ganho nenhum** e foram revertidas — ficam registradas
porque cada uma refuta uma teoria plausível.

**Tentativa 1 — reescrever os operadores sobre a palavra crua.** O OX1 lê cada
pai oito vezes; pela regra do §7, seriam 16 aberturas de registro compartilhado
por crossover. Expor `word_get`/`word_set`/`word_swap` e desempacotar uma vez só
mediu **1,01x**. Conclusão: abrir um registro de **1 campo escalar** é quase de
graça. O custo do §7 vinha de o `Ind` ter um campo **ponteiro**, cujo refcount
precisa ser incrementado na cópia. A regra do §7 vale para registros com
ponteiros, não para qualquer registro.

**Tentativa 2 — parar de recalcular o PRNG.** `cut_lo` e `cut_hi` refaziam cada
um `R.step(seed)` e `R.step(R.step(seed))`, somando 6 chamadas de Xorshift por
sorteio onde 2 bastavam. Empacotar o par num escalar mediu **1,01x**: o Xorshift
é barato demais para aparecer.

**Tentativa 3 — subdividir a geração** (`fork_d`, §6.1): 2x a 3x **mais lento**.

O que sobra do OX1 são 16 iterações de laço por crossover, trabalho inerente ao
algoritmo. A partir daqui o caminho seria desenrolar os laços, o que troca
legibilidade por alguns por cento.

---

## 9. Por Que o GP Não Escala

`bench_gp` é o único benchmark com escala negativa. Ele melhora com mais ilhas,
mas nem de perto o suficiente:

| Ilhas | 1 thread | 4 threads | escala |
| ---: | ---: | ---: | ---: |
| 4 | 367 ms | 537 ms | 0,68x |
| 16 | 1421 ms | 1623 ms | 0,88x |
| 64 | 4485 ms | 3931 ms | 1,14x |

**Não é alocação.** Testado de propósito, com a contagem de tarefas fixa em 4096
e variando só quanta memória cada tarefa aloca:

| Trabalho por tarefa | 1T | 4T | escala |
| :--- | ---: | ---: | ---: |
| computação pura, zero alocação | 35 ms | 11 ms | 3,18x |
| 511 nós alocados e consumidos | 11 ms | 5 ms | 2,20x |
| 4.095 nós alocados e consumidos | 69 ms | 22 ms | **3,14x** |

Alocar 16,8 milhões de nós escala **igual** a não alocar nada. O alocador do
Bend não é o gargalo.

O que resta é o genoma: o GP é o único cujo indivíduo é uma **árvore de tamanho
variável**, com dezenas de nós e ponteiros a perseguir. Isso traz duas coisas
que os demais não têm — uma pegada de memória por ilha grande o bastante para
disputar cache compartilhada entre os cores, e **desbalanceamento**, porque o
bloat faz ilhas diferentes convergirem para árvores de tamanhos diferentes. Num
escalonador sem work stealing o tempo em 4 threads é o da ilha mais lenta.

> **Corolário de projeto:** o que faz o motor escalar é o **genoma compacto**.
> Cada passo nessa direção (empacotar `Perm8` numa palavra, carregar a aptidão
> como escalar solto) melhorou os dois eixos ao mesmo tempo, single e multicore.

---

## 10. Resumo dos Ganhos

Todos medidos com os binários antigo e novo intercalados, em 1 thread:

| Benchmark | Início | Antes desta sessão | Agora | Ganho Total |
| :--- | ---: | ---: | ---: | ---: |
| `bench_perm` | 1605 ms | 251 ms | **206 ms** | **7,8x** |
| `bench_bits` | 299 ms | 102 ms | **85 ms** | **3,5x** |
| `bench_gp` | 561 ms | 359 ms | **222 ms** | **2,5x** |
| `bench_parallel` (8 ilhas) | 248 ms | 248 ms | **45 ms** | **5,5x** |

E em 4 threads, com o arquipélago bem dimensionado, `bench_islands` faz mais de 3,17x a 4,20x
sobre sua própria execução em 1 thread.

As otimizações vieram de cinco descobertas fundamentais sobre o Bend 2:

1. **Não passe alternativas computadas para quem escolhe** (§2) — `Bool.pick`
   avalia os dois ramos.
2. **Agregados pequenos cabem numa palavra atrás de um construtor de 1 campo**,
   sem custo e sem perder o tipo (§5).
3. **Ler uma estrutura duas vezes custa uma cópia por nó aberto** (§7) — leia
   uma vez, ou carregue o escalar solto.
4. **Trocas bitwise em palavras empacotadas são O(1) via máscara XOR** (§12) —
   elimina o registro intermediário e inversões de máscara redundantes.
5. **Reprodução avaliada elimina a 3ª avaliação em cenários meméticos** (§13) —
   cenários como GP e Sudoku já calculam a aptidão na seleção gulosa; carregar
   `Ind<G>` via `breed_tree_eval` poupa a reavaliação completa de AST e grades.

---

## 11. Otimizações Recentes Consolidadas

### 11.1 Rastreamento do Campeão de Arquipélago em O(1) e Eliminação de Travessias de Época
Anteriormente, `run_generations` executava as gerações da ilha e descartava o campeão
descoberto na geração fundida com `Gen.pop`. Em seguida, a cada época, `best_archipelago`
re-percorria as árvores de todas as 64 ilhas (4.096 nós) chamando `best_ind` e abrindo
indivíduos compartilhados. Além disso, `migrate_champion` usava `inject_elite` para reescrever
a folha de cada árvore.

**Solução:** `ArchTree` agora armazena `SingleIsland{gen: Gen<G>}`. Como `run_gen_loop`
já devolve o campeão no `Gen`, a redução entre ilhas lê `(bfit, bgene)` em $O(1)$ por ilha.
E a migração apenas atualiza o campeão no `Gen`, que é injetado no slot de elite e recombinado
automaticamente na primeira geração da época seguinte pelo próprio `breed_tree`.

### 11.2 `Perm8.swap` via Máscara XOR em Expressão Única
O `swap` de `Perm8` fazia `get(i)`, `get(j)`, `set(i, vj)` e `set(j, vi)`, alocando um `P8`
intermediário. Agora, calcula a diferença escalar `diff = vi ^ vj` e aplica a máscara
`(diff << shi) | (diff << shj)` com um único `U32.xor(b, mask)`. `bench_perm` caiu de 258ms
para 206ms.

### 11.3 Eliminação de Avaliação Especulativa no Cenário 12 (Co-Evolução)
Em `scenario12_coevolution.bend`, `apply_pair` usava `Bool.pick(Arr4, ...)` aninhado 5 vezes
para escolher o comparador, avaliando todas as 6 chamadas de `cas(a, ...)` a cada passo.
Com seletores encadeados em `match` sobre `Bool`, a execução em C caiu de ~26ms para 2ms.

### 11.4 Reprodução Avaliada (`breed_tree_eval`) no GP e Sudoku
Resolve o item que estava em aberto: em operadores que já avaliam a aptidão para selecionar
o melhor entre mutado e original, o motor descartava a aptidão e chamava `fit` uma 3ª vez.
Com `breed_tree_eval` e o helper `leaf_from_ind`, `bench_gp` caiu de 366ms para 222ms em 1T
e o Sudoku caiu de 26ms para 15ms.

---

## 12. Em Aberto

- **Desenrolar os laços do OX1**: 16 iterações por crossover, hoje a maior fatia do `bench_perm`.
- **Empacotar `Arr4` (Cenário 12) e `String16` (Cenário 8)** em palavras únicas como `Perm8`.
- Re-dimensionar `bench_bits` e `bench_perm` para 64 ilhas para exibir a escala 3.5x-4.2x do `bench_islands`.
