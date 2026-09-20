import Base
import ./../utils/arrays.bend as Arr
import ./../utils/tuples.bend as T
import ./../utils/random.bend as R

# ================================================================
# ARENA (arena.bend)
# ================================================================
# A população vive num `Array<Individual<G>>` alocado na largada e nunca
# realocado. Uma geração só faz `Array.swap` sobre o que já existe.
#
# `Individual` é um registro LINEAR: guarda o genoma (que é `Type`, logo tem um
# dono só) ao lado dos metadados. Ler um campo é O(1): desestrutura e
# reconstrói (medido: 3 ns por leitura, contando o empréstimo no array).
#
# `Pop` carrega, junto com o array:
#   - DOIS buracos (`h1`, `h2`): para tirar um indivíduo do array é preciso pôr
#     algo no lugar (`Array.swap` é o `mem::replace` do Rust). Dois buracos
#     permitem ter dois slots fora ao mesmo tempo, que é o que o cruzamento
#     precisa. Eles circulam: saem e voltam em cada operação, sem alocar.
#   - `size`: o número de slots. Guardado na mão porque `Array.size` é O(log n)
#     e a arena não pode ser medida com um slot emprestado (o buraco tem outra
#     profundidade).
#
# PRIMITIVAS (todas com 2 ou 4 swaps, sem alocação):
#   at1    aplica f ao indivíduo do slot i
#   read1  aplica f ao slot i e devolve também um valor
#   at2    aplica f aos slots i e j (i != j)
#   evaluate  uma passada avaliando quem ainda não tem fitness
# ================================================================

type Individual<-G: Type> is Type:
  Individual{gene: G, fit: U32, hash: U32}

type Pop<-G: Type> is Type:
  Pop{arr: Array<Individual<G>>, h1: Individual<G>, h2: Individual<G>, size: U32}

# ----------------------------------------------------------------
# CONSTRUIR
# ----------------------------------------------------------------

# fit = 0 significa "não avaliado"; hash = 0, "desconhecido"
def fresh(~G: Type, gene: G) -> Individual<G>:
  Individual{gene, 0, 0}

# Esqueleto da população: 2^d slots, cada um com um genoma criado por `alloc` e
# preenchido por `init` com uma semente própria. Recursão comum (não `from_fn`:
# o `~f` de um template não pode capturar `ctx`, que vem de argumento), com
# chamada paralela nos dois lados.
def pop_build(~G: Type, ~P: Data, ~alloc: @+c: P -> G, ~init: @+c: P -> G -> @+s: U32 -> G,
              d: Nat, +ctx: P, +seed: U32) -> Array<Individual<G>>:
  match d:
    case 0n:
      ALeaf{fresh(~G, init(ctx, alloc(ctx), seed))}
    case 1n+ +p:
      l r = pop_build(~G, ~P, ~alloc, ~init, p, ctx, R.split.fst(seed)) pop_build(~G, ~P, ~alloc, ~init, p, ctx, R.split.snd(seed))
      ANode{l, r}

# A população pronta: 2^d indivíduos mais os dois buracos.
def pop_new(~G: Type, ~P: Data, ~alloc: @+c: P -> G, ~init: @+c: P -> G -> @+s: U32 -> G,
            +d: Nat, +ctx: P, +seed: U32) -> Pop<G>:
  Pop{pop_build(~G, ~P, ~alloc, ~init, d, ctx, R.split.trd(seed)),
      fresh(~G, alloc(ctx)),
      fresh(~G, alloc(ctx)),
      U32.shln(1, d)}

# ----------------------------------------------------------------
# at1: aplicar f ao indivíduo do slot i (2 swaps)
# ----------------------------------------------------------------

def at1.put(~G: Type, r: Array<Individual<G>> & Individual<G>, h2: Individual<G>, +size: U32) -> Pop<G>:
  (arr, h1) = r
  Pop{arr, h1, h2, size}

def at1.call(~G: Type, ~C: Data, ~f: Individual<G> -> @+c: C -> @+at: U32 -> Individual<G>,
             r: Array<Individual<G>> & Individual<G>, h2: Individual<G>, +i: U32, +ctx: C, +size: U32) -> Pop<G>:
  (arr, ind) = r
  at1.put(~G, Array.swap(Individual<G>, arr, i, f(ind, ctx, i)), h2, size)

def at1(~G: Type, ~C: Data, ~f: Individual<G> -> @+c: C -> @+at: U32 -> Individual<G>, p: Pop<G>, +i: U32, +ctx: C) -> Pop<G>:
  match p:
    case Pop{arr, h1, h2, +size}:
      at1.call(~G, ~C, ~f, Array.swap(Individual<G>, arr, i, h1), h2, i, ctx, size)

# ----------------------------------------------------------------
# read1: aplicar f ao slot i e trazer um valor de volta (2 swaps)
# ----------------------------------------------------------------

def read1.put(~G: Type, ~S: Type, r: Array<Individual<G>> & Individual<G>, h2: Individual<G>, value: S, +size: U32) -> Pop<G> & S:
  (arr, h1) = r
  (Pop{arr, h1, h2, size}, value)

def read1.split(~G: Type, ~S: Type, arr: Array<Individual<G>>, h2: Individual<G>, r: Individual<G> & S, +i: U32, +size: U32) -> Pop<G> & S:
  (ind, value) = r
  read1.put(~G, ~S, Array.swap(Individual<G>, arr, i, ind), h2, value, size)

def read1.call(~G: Type, ~C: Data, ~S: Type, ~f: Individual<G> -> @+c: C -> @+at: U32 -> (Individual<G> & S),
               r: Array<Individual<G>> & Individual<G>, h2: Individual<G>, +i: U32, +ctx: C, +size: U32) -> Pop<G> & S:
  (arr, ind) = r
  read1.split(~G, ~S, arr, h2, f(ind, ctx, i), i, size)

def read1(~G: Type, ~C: Data, ~S: Type, ~f: Individual<G> -> @+c: C -> @+at: U32 -> (Individual<G> & S),
          p: Pop<G>, +i: U32, +ctx: C) -> Pop<G> & S:
  match p:
    case Pop{arr, h1, h2, +size}:
      read1.call(~G, ~C, ~S, ~f, Array.swap(Individual<G>, arr, i, h1), h2, i, ctx, size)

# ----------------------------------------------------------------
# at2: aplicar f aos indivíduos dos slots i e j (4 swaps)
# ----------------------------------------------------------------
# Com i == j a arena seria corrompida (o segundo empréstimo tiraria o BURACO do
# slot como se fosse um indivíduo), então isso é checado: com i == j a
# população volta intacta e f não é chamada. Índices precisam estar
# normalizados para [0, size): eles dão a volta, e i=0 com j=size seriam o
# mesmo slot sem a checagem pegar.

def at2.put_j(~G: Type, r: Array<Individual<G>> & Individual<G>, h1: Individual<G>, +size: U32) -> Pop<G>:
  (arr, h2) = r
  Pop{arr, h1, h2, size}

def at2.put_i(~G: Type, r: Array<Individual<G>> & Individual<G>, nj: Individual<G>, +i: U32, +j: U32, +size: U32) -> Pop<G>:
  (arr, h1) = r
  at2.put_j(~G, Array.swap(Individual<G>, arr, j, nj), h1, size)

def at2.split(~G: Type, arr: Array<Individual<G>>, r: Individual<G> & Individual<G>, +i: U32, +j: U32, +size: U32) -> Pop<G>:
  (ni, nj) = r
  at2.put_i(~G, Array.swap(Individual<G>, arr, i, ni), nj, i, j, size)

def at2.call(~G: Type, ~C: Data, ~f: Individual<G> -> Individual<G> -> @+c: C -> (Individual<G> & Individual<G>),
             r: Array<Individual<G>> & Individual<G>, ind_i: Individual<G>, +i: U32, +j: U32, +ctx: C, +size: U32) -> Pop<G>:
  (arr, ind_j) = r
  at2.split(~G, arr, f(ind_i, ind_j, ctx), i, j, size)

def at2.take_j(~G: Type, ~C: Data, ~f: Individual<G> -> Individual<G> -> @+c: C -> (Individual<G> & Individual<G>),
               r: Array<Individual<G>> & Individual<G>, h2: Individual<G>, +i: U32, +j: U32, +ctx: C, +size: U32) -> Pop<G>:
  (arr, ind_i) = r
  at2.call(~G, ~C, ~f, Array.swap(Individual<G>, arr, j, h2), ind_i, i, j, ctx, size)

def at2.open(~G: Type, ~C: Data, ~f: Individual<G> -> Individual<G> -> @+c: C -> (Individual<G> & Individual<G>),
             p: Pop<G>, +i: U32, +j: U32, +ctx: C) -> Pop<G>:
  match p:
    case Pop{arr, h1, h2, +size}:
      at2.take_j(~G, ~C, ~f, Array.swap(Individual<G>, arr, i, h1), h2, i, j, ctx, size)

def at2.if(~G: Type, ~C: Data, ~f: Individual<G> -> Individual<G> -> @+c: C -> (Individual<G> & Individual<G>),
           same: Bool, p: Pop<G>, +i: U32, +j: U32, +ctx: C) -> Pop<G>:
  match same:
    case True{}:
      p
    case False{}:
      at2.open(~G, ~C, ~f, p, i, j, ctx)

def at2(~G: Type, ~C: Data, ~f: Individual<G> -> Individual<G> -> @+c: C -> (Individual<G> & Individual<G>),
        p: Pop<G>, +i: U32, +j: U32, +ctx: C) -> Pop<G>:
  at2.if(~G, ~C, ~f, U32.is_eq(i, j), p, i, j, ctx)

# ----------------------------------------------------------------
# LER O FITNESS (a primitiva do torneio)
# ----------------------------------------------------------------

def peek_fit(~G: Type, ind: Individual<G>, +ctx: U32, +at: U32) -> Individual<G> & U32:
  match ind:
    case Individual{gene, +fit, hash}:
      (Individual{gene, fit, hash}, fit)

def fit_at(~G: Type, p: Pop<G>, +i: U32) -> Pop<G> & U32:
  read1(~G, ~U32, ~U32, ~peek_fit(~G), p, i, 0)

def peek_hash(~G: Type, ind: Individual<G>, +ctx: U32, +at: U32) -> Individual<G> & U32:
  match ind:
    case Individual{gene, fit, +hash}:
      (Individual{gene, fit, hash}, hash)

def hash_at(~G: Type, p: Pop<G>, +i: U32) -> Pop<G> & U32:
  read1(~G, ~U32, ~U32, ~peek_hash(~G), p, i, 0)

# ----------------------------------------------------------------
# ACESSO AO TAMANHO
# ----------------------------------------------------------------

def size_of(~G: Type, p: Pop<G>) -> Pop<G> & U32:
  match p:
    case Pop{arr, h1, h2, +size}:
      (Pop{arr, h1, h2, size}, size)

# ----------------------------------------------------------------
# AVALIAÇÃO
# ----------------------------------------------------------------
# Uma passada pelos slots: quem tem fit = 0 é avaliado. Preserva a ordem (2
# swaps por slot). O custo da passada é dominado pelo fitness do problema, que
# é O(genoma) — a travessia em si é ~1 ns por indivíduo.

def eval_one.put(~G: Type, r: G & U32, +hash: U32) -> Individual<G> & U32:
  (gene, +f) = r
  (Individual{gene, f, hash}, f)

def eval_one.if(~G: Type, ~P: Data, ~fitness: @+c: P -> G -> (G & U32),
                unevaluated: Bool, gene: G, +fit: U32, +hash: U32, +ctx: P) -> Individual<G> & U32:
  match unevaluated:
    case True{}:
      eval_one.put(~G, fitness(ctx, gene), hash)
    case False{}:
      (Individual{gene, fit, hash}, fit)

# Avalia se ainda não foi avaliado, e devolve o indivíduo com a aptidão
def eval_one(~G: Type, ~P: Data, ~fitness: @+c: P -> G -> (G & U32),
             ind: Individual<G>, +ctx: P, +at: U32) -> Individual<G> & U32:
  match ind:
    case Individual{gene, +fit, hash}:
      eval_one.if(~G, ~P, ~fitness, U32.is_zero(fit), gene, fit, hash, ctx)

# melhor entre o acumulado e o slot i. Uma tupla é `Type`, então não aceita `+`:
# os escalares são escolhidos separadamente, sem montar tupla descartada.
def eval.best(best: U32 & U32, +i: U32, +fit: U32) -> U32 & U32:
  (+bi, +bf) = best
  +better = U32.is_gt(fit, bf)
  (Bool.pick(U32, better, i, bi), Bool.pick(U32, better, fit, bf))

def eval.step(~G: Type, st: Pop<G> & U32, best: U32 & U32, +i: U32) -> Pop<G> & (U32 & U32):
  (p, +fit) = st
  (p, eval.best(best, i, fit))

def eval.go(~G: Type, ~P: Data, ~fitness: @+c: P -> G -> (G & U32),
            k: Nat, st: Pop<G> & (U32 & U32), +ctx: P, +i: U32) -> Pop<G> & (U32 & U32):
  match k:
    case 0n:
      st
    case 1n+p:
      (pop, best) = st
      eval.go(~G, ~P, ~fitness, p,
        eval.step(~G, read1(~G, ~P, ~U32, ~eval_one(~G, ~P, ~fitness), pop, i, ctx), best, i),
        ctx, (i + 1 : U32))

def evaluate.start(~G: Type, ~P: Data, ~fitness: @+c: P -> G -> (G & U32),
                   r: Pop<G> & U32, +ctx: P) -> Pop<G> & (U32 & U32):
  (p, +n) = r
  eval.go(~G, ~P, ~fitness, U32.to_nat(n), (p, T.pair(U32, U32, 0, 0)), ctx, 0)

# Avalia a população inteira e devolve (população, (índice do melhor, aptidão do
# melhor)). O tamanho sai do próprio `Pop`.
#
# ⚠️ O fitness do problema NUNCA pode devolver 0: 0 é a marca de "não
# avaliado". Some 1 se o mínimo real for zero.
def evaluate(~G: Type, ~P: Data, ~fitness: @+c: P -> G -> (G & U32),
             p: Pop<G>, +ctx: P) -> Pop<G> & (U32 & U32):
  evaluate.start(~G, ~P, ~fitness, size_of(~G, p), ctx)

