# Motor genético em Bend 2 — modelagem 0-copy / 0-alloc

> Verificado contra o **bend 2.0.21**. Todo número aqui foi medido no nativo
> (i5-1245U, 15 W). As armadilhas citadas estão no `AGENTS.md`.

## 1. O objetivo e o que ele custa

Um motor escrito uma vez, focado em desempenho:

- **0 alocação por geração.** Tudo que o motor usa é criado na largada: a
  população, os genomas, o buraco, os rascunhos. A geração só faz
  `Array.get`/`Array.set`/`Array.swap` sobre o que já existe.
- **0 cópia onde a semântica permite.** Nunca se copia um genoma para
  "guardar" um indivíduo: o elite é um índice, a migração é troca de slot.
  Copiar genes acontece só onde o algoritmo exige (um pai escolhido duas
  vezes gera dois filhos distintos) — e mesmo aí a cópia vai para um buffer
  que já existe, sem alocar.

> Ganho esperado sobre o motor v2 (genoma em `List`): o v2 fazia ~71 ns por gene
> por geração; a arena faz 0,4–2,6 ns por operação de gene. E o v2 **degradava
> com o tempo** (44 ms por geração no início, 105 ms na geração 300, com memória
> constante: o alocador reusa nós numa pilha LIFO e as listas novas nascem
> espalhadas). Uma arena que não aloca não tem esse efeito — é a primeira coisa
> a confirmar quando o motor rodar.

## 2. Os números que mandam no desenho

| operação | custo medido | consequência de projeto |
|---|---|---|
| `fold_rot` / `reduce` por índice | **0,4 ns/elem** | forma canônica de percorrer |
| `for_each_rot` (1 swap) | 0,58 ns/elem | passada in-place mais rápida |
| `for_each` (get+set) | 0,78 ns/elem | use quando a ordem importa (genes) |
| `for_each_hole` (2 swaps) | 1,30 ns/elem | só se a ordem importar e o elemento for `Type` |
| ler campo de `Individual` no array (swap+match+rebuild) | **3 ns** | torneio lê direto, **sem espelho de fitness** |
| `swap_at_hole` (3 swaps) | ~10 ns | migração e Fisher–Yates |
| troca de faixa entre 2 arrays por índice | 1,4 ns/posição | crossover de 1 e 2 pontos |
| `R.step` / `R.range` | 2,0 / 3,6 ns | ~1 sorteio por gene é aceitável |
| `IO.random_u32` | **11 µs** | só a semente inicial, no `main` |
| `match ALeaf/ANode` (percurso estrutural) | 18,8 ns/elem | **proibido** no caminho quente |
| `with`/closure por elemento | 38 ns/elem | **proibido** em laço |
| `match ANode` num `Array<Individual>` (divide demes) | copia só handles | paralelismo por deme é barato |
| `Array.size` | não é tão rápido assim (O(log n)) | carregar `size` na mão em loops quentes |

## 3. Estado

```python
# O indivíduo é um registro LINEAR: guarda o genoma (que é `Type`) ao lado dos
# metadados. Verificado no nativo, inclusive polimórfico sobre G.
type Individual<-G: Type> is Type:
  Individual{
    gene: G,
    fit: U32,      # 0 = não avaliado
    hash: U32,     # 0 = desconhecido (diversity check)
  }

# A arena. `pop` tem 2^pop_d slots; `hole` é o buraco que circula.
type Deme<-G: Type, -P: Data> is Type:
  Deme{
    pop: Array<Individual<G>>,
    hole: Individual<G>,       # um só, para todo o programa
    plan: Array<U32>,          # rascunho: índices de pais/vítimas
    seen: Array<U32>,          # rascunho: bitset de hashes (2^16 bits)
    ctx: P,                    # contexto do problema (Data, read-only)
    best_idx: U32,             # elitismo: um ÍNDICE, não uma cópia
    best_fit: U32,
    stag: U32,                 # gerações sem melhora
    seed: U32,
  }
```

Decisões que vêm da medição:

- **Sem espelho de fitness.** Ler o `fit` de um slot custa 3 ns (empresta com
  `Array.swap`, desestrutura o registro, reconstrói, devolve) — o mesmo que ler
  de um `Array<U32>` paralelo, sem a passada extra para montá-lo e sem risco de
  dessincronizar.
- **`best_idx` em vez de `best_gene`.** O v2 duplicava o campeão para a
  população inteira a cada geração; aqui o elite é excluído do plano de
  reprodução e custa zero. O melhor de todos os tempos vive num slot reservado
  e só é reescrito (`copy_range`) quando melhora.
- **`plan` e `seen` são do deme e vivem uma época**, não uma geração.

## 4. Interface do problema

Templates (`~`), todos recebendo o contexto `P` como **parâmetro comum** —
template não captura valor de runtime (`a def parameter is not comptime`).

```python
~alloc     : (ctx: P) -> G                    # ÚNICO ponto de alocação: cria um genoma vazio
~init      : (ctx: P, gene: G, seed: U32) -> G           # (re)inicializa IN-PLACE
~fitness   : (ctx: P, gene: G) -> G & U32                # devolve o genoma e a aptidão
~hash      : (ctx: P, gene: G) -> G & U32                # idem, para o diversity check
~crossover : (ctx: P, pa: G, pb: G, ca: G, cb: G, seed: U32) -> ((G & G) & (G & G))
~mutate    : (ctx: P, gene: G, rate: U32, seed: U32) -> G  # IN-PLACE
~copy_into : (ctx: P, src: G, dst: G) -> G & G              # substitui o clone: escreve em buffer existente
```

- **`~crossover` recebe os 4 e devolve os 4** (pais e filhos). É a forma certa:
  com só dois argumentos os pais *seriam* os filhos, o que proíbe um pai bom de
  ser escolhido duas vezes e muda o algoritmo. Escrevendo nos buffers dos
  filhos, que já existem na arena, continua 0-alocação. Pares aninhados como
  retorno foram verificados.
- **`~fitness` devolve `G & U32`** porque o `fit` mora no registro: o par é
  aberto no mesmo lugar onde o `Individual` é remontado, sem custo extra.
- **Nada de `clone`.** Toda "cópia" é `copy_into` num buffer existente.

### Como fica o fitness de um problema (o teste de simplicidade)

OneMax, genoma `Array<U32>` de bits:

```python
def bit(x: U32, acc: U32, i: U32) -> U32:
  (acc + U32.and(x, 1) : U32)

def fitness(ctx: U32, gene: Array<U32>) -> Array<U32> & U32:
  Arr.reduce(~U32, ~U32, ~bit, gene, 0)      # devolve (gene, soma)
```

Três linhas, custo 0,4 ns por gene. Um fitness que precisa de acesso aleatório
(sudoku: linhas, colunas, caixas) usa `Arr.reduce` com o acumulador carregando
um `Array<U32>` de contagens — o padrão que já está no `exemplos/arrays.bend`.

## 5. A geração, passo a passo

Sequencial dentro do deme; demes em paralelo.

1. **Avaliar** — uma passada `fold_rot` (0,4 ns/elem): empresta o indivíduo,
   `~fitness`, grava o `fit` no registro, devolve; o acumulador carrega
   `(best_idx, best_fit)`. Pula quem já tem `fit != 0`.
   *A passada rotaciona o array uma posição* — some 1 nos índices guardados, ou
   alterne o sentido das passadas para cancelar.
2. **Selecionar** — torneios lendo o `fit` por empréstimo (3 ns por sorteio).
   Os índices dos pais e das vítimas vão para `plan`. Sequencial, mas só
   leituras de array: o `snapshot` do v2 (e a máquina de estados de 19
   parâmetros do `select.go`) deixa de existir.
3. **Reproduzir** — para cada trio `(vitima_a, vitima_b, pai_a, pai_b)` do
   plano: empresta os 4 slots, `~crossover` escreve nos dois filhos (ou
   `copy_into` quando o sorteio não cruza), `~mutate` em cada filho,
   `~fitness`, devolve os 4. Zero alocação; as únicas cópias de gene são as que
   o algoritmo exige.
4. **Elitismo** — `best_idx` é excluído do plano. Custo zero.
5. **Diversidade** — os hashes saem dos registros para o bitset `seen`
   (pré-alocado), e quem repetir é mutado de novo com 4× a taxa e re-hasheado.
6. **Estagnação** — `~init` in-place sobre os slots; o melhor de todos os
   tempos volta por `copy_into`.

## 6. Contabilidade de alocação

| momento | o que aloca |
|---|---|
| largada | esqueleto da população (recursão comum devolvendo `ALeaf`/`ANode` — `Array.new` exige `Data`), um genoma por slot (`~alloc`), o buraco, o slot do melhor de todos os tempos |
| início de época (por deme) | `plan`, `seen` |
| **por geração** | **nada** |

Tuplas `A & B` são nós, mas são baratas a ponto de não aparecer na medição
(`Array.get` devolve uma por chamada e o laço custa 0,4 ns/elem) e o alocador
as recicla numa pilha LIFO por thread. A afirmação honesta é: **o conjunto de
dados vivos é constante** — medido 10–13 MB para 8,4 MB de dados ao longo de
100 gerações.

## 8. Idiomas obrigatórios (como escrever)

1. **A tupla é o estado do laço.** Só dá para desestruturar um parâmetro;
   `(a, v) = f(x)` não compila. O laço recebe a tupla, abre, e passa a próxima
   tupla adiante.
2. **Auxiliares não recursivos consertam o estado** (`X.go` é o laço,
   `X.put`/`X.next` os auxiliares). Não existe recursão mútua em Bend 2.
3. **Nada de `with`/closure dentro de laço** (38 ns/elem contra 1,5 ns).
   `with` só na borda — `utils/tuples.bend` tem `with`, `with3`, `with4`.
4. **Nunca `match` na estrutura do `Array`** no caminho quente (18,8 ns/elem).
   A exceção é dividir a população em demes, onde só handles são copiados.
5. **Nunca `Array.size` na arena com um slot emprestado** (o buraco tem outra
   profundidade e o tamanho sai errado). Tamanhos andam como parâmetro.
6. **Potência de 2** em tamanho de população e de genoma, ou carregue o `n`
   lógico em todo laço.
7. **Normalize índices antes de comparar** (`U32.and(i, n-1)`): eles dão a
   volta, e `swap_at_hole` com `i == j` mascarado corromperia o array.
8. **Aleatoriedade:** `IO.random_u32` uma vez no `main` para a semente; daí em
   diante `R.step`/`R.split.*`. Avance o laço externo com um `split.*` que o
   corpo não usa (Armadilha 9).

## 9. Riscos e pontos abertos

1. **Não foi medida a geração completa** nesta forma — só as peças (arena,
   empréstimo, torneio, crossover in-place, demes paralelos, `fold_rot`).
2. **A rotação do `fold_rot`** é segura para a população (saco de indivíduos) e
   **proibida dentro de um genoma** (genes são posicionais). Quem escrever um
   operador precisa saber a diferença.
3. **Convergência**: a forma como o plano escolhe vítimas (substituir os piores)
   muda a pressão seletiva em relação ao v2. Comparar com semente fixa, mesmo
   número de gerações, no OneMax e no sudoku.
4. **`f64` como aptidão** não existe aqui: `U32`, como no v2.
5. ~~Falta em `utils/arrays.bend`~~ **feito**: `copy_range` (0,6 ns/posição),
   `swap_range` (1,1 ns), `fill` (0,3 ns) e `swap_range_hole`, com testes em
   `utils/arrays_test.bend`.
6. **Falta na Base**: `Array.swap2(a, i, j)` (o `slice::swap` do Rust). Sem ele,
   toda troca precisa de buraco e paga 3 swaps em vez de 1. Vale abrir issue.

## 10. Estado da implementação

Cada etapa terminou em binário nativo medido, com commit próprio.

1. ✅ `utils/arrays.bend`: `copy_range` (0,6 ns/posição), `swap_range` (1,1 ns),
   `fill` (0,3 ns), `swap_range_hole`, `fold_rot`, com testes (14 casos).
2. ✅ `genetic/arena.bend` + `operators.bend`: `Individual`/`Pop`, empréstimo
   com dois buracos, `at1`/`read1`/`at2`/`fit_at`/`hash_at`/`evaluate`,
   cruzamentos (1 ponto, 2 pontos, uniforme) e mutações in-place. 7 testes.
3. ✅ OneMax na arena: **0,5 ns por gene**, memória constante, **sem
   degradação** (0,30 / 0,20 / 0,22 ms por geração em 100 / 200 / 400
   gerações, contra 44 → 105 ms do v2 em `List`).
4. ✅ `genetic/ga.bend`: torneio do pior para vítimas e do melhor para pais,
   elitismo de graça (o elite é excluído do sorteio), reprodução steady-state.
   Ótimo do OneMax por volta da geração 60 em 8 de 8 sementes; 1024 genes,
   pop 64, 300 gerações em **0,03 s contra 1,36 s do v2 (~45×)**.
5. ✅ Arquipélago: demes em paralelo por `match ANode`, migração por troca de
   slot (zero gene copiado). 1,6× com 2 threads (teto da máquina), resultado
   idêntico em 1–12 threads. **No OneMax mais demes PIORA** (é unimodal);
   migrar a cada 5 gerações dá 4053/4096 contra 3742 sem migração.
6. ✅ Diversidade (hash no nascimento + bitset por deme, **configurável**:
   dobra o tempo para +2% no OneMax) e estagnação (mutação adaptativa +
   reinício in-place: população de 8 em 512 genes empaca em 507/512 sem ela e
   chega a 512/512 com `max_stag = 25`).
7. ✅ `exemplos/trap.bend`, o caso difícil: com diversidade + 8 demes +
   estagnação, 108–111/128 contra 101–105 do baseline em 3 sementes.

### O que falta

- **Sudoku.** A aptidão precisa de 243 contadores de rascunho, e alocá-los por
  indivíduo por geração quebraria o 0-alloc. A saída provável: o genoma carrega
  o próprio rascunho na cauda (81 células do quadro + contadores, num `Array`
  de 512), porque contexto do problema é `Data` e não pode guardar `Array`.
- **LAWS.bend / PROOF.bend** (combinado para o final).
- **Medir o desvio do §4**: a interface tem `~crossover` de 2 genomas (o motor
  copia os pais nos filhos antes) em vez de 4. Custa uma passada extra de
  cópia por filho; a alternativa de 4 genomas exigiria 4 buracos.
- **Operadores que faltam** do v2: OX1 (genoma-permutação), mutação por troca
  de vizinhos, `mutation_combine`.

### Contabilidade de alocação, como ficou

| momento | o que aloca |
|---|---|
| largada | população (2^d genomas), 2 buracos, 1 bitset de 8 KB |
| início de época, por deme | 2 buracos + 1 bitset (só com demes: 2^d > 1) |
| **por geração** | **nada** |

