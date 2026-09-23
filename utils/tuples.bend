import Base

# ================================================================
# TUPLAS `A & B` (tuples.bend)
# ================================================================
# Uma tupla `A & B` (um Sigma) é o que toda operação sobre `Array` devolve,
# porque o array tem um dono só e precisa voltar junto com a resposta:
#
#   a[5]                  -> Array<U32> & U32
#   Array.size(U32, a)    -> Array<U32> & U32
#   Array.swap(T, a, i, v)-> Array<T> & T
#
# A regra que manda no jeito de escrever: **só dá para desestruturar um
# PARÂMETRO**. Isto não compila:
#
#   (a, n) = Array.size(U32, a)   # a match cannot scrutinize a computed value
#
# Daí as duas formas de lidar com um resultado `A & B`:
#
#  1. Um auxiliar que recebe a tupla como PARÂMETRO e a abre. É o jeito dos
#     laços quentes: custo zero.
#
#       def mostra(r: Array<U32> & U32) -> String:
#         (a, n) = r
#         U32.show(n)
#
#  2. `with`, que abre a tupla e entrega as duas metades a uma lambda. Custa
#     uma closure por chamada.
#
# ⚠️ CUSTO: `with` é ótimo UMA vez por chamada e péssimo por elemento. Medido
# no nativo, uma travessia de 2^20 elementos: 1,5 ns por elemento com auxiliar
# nomeado, 38 ns com um `with` por elemento (25× mais). Em laço, sempre
# auxiliar; `with` só na borda (abrir o `Array.size` no começo, montar o IO no
# fim). Todo o resto deste arquivo é açúcar de custo zero.
#
# Nomes seguem o Rust onde ele tem equivalente (`.0`/`.1` -> `fst`/`snd`,
# `map`, `swap`); o resto é o que a linguagem obriga a ter.

# ----------------------------------------------------------------
# CONSTRUIR
# ----------------------------------------------------------------

# A tupla `(a, b)`. Existe porque uma tupla literal precisa de contexto de tipo
# para ser inferida (Armadilha 6), e em posição de argumento nem sempre tem.
def pair(-A: Type, -B: Type, a: A, b: B) -> A & B:
  (a, b)

# Tripla, aninhada à esquerda: `(A & B) & C`. É o estado de um laço que carrega
# três coisas lineares (por exemplo população, buraco e acumulador).
def pair3(-A: Type, -B: Type, -C: Type, a: A, b: B, c: C) -> (A & B) & C:
  ((a, b), c)

def pair4(-A: Type, -B: Type, -C: Type, -D: Type, a: A, b: B, c: C, d: D) -> ((A & B) & C) & D:
  (((a, b), c), d)

# ----------------------------------------------------------------
# ABRIR
# ----------------------------------------------------------------

# `let (a, b) = p` escrito como continuação. Uma closure por chamada: não use
# dentro de laço (veja o aviso no topo).
def with(-A: Type, -B: Type, -C: Type, p: A & B, k: A -> B -> C) -> C:
  (a, b) = p
  k(a, b)

def with3(-A: Type, -B: Type, -C: Type, -D: Type, p: (A & B) & C, k: A -> B -> C -> D) -> D:
  (ab, c) = p
  (a, b) = ab
  k(a, b, c)

def with4(-A: Type, -B: Type, -C: Type, -D: Type, -E: Type, p: ((A & B) & C) & D, k: A -> B -> C -> D -> E) -> E:
  (abc, d) = p
  (ab, c) = abc
  (a, b) = ab
  k(a, b, c, d)

# Com template ~ a função f não permite capturar variáveis do escopo externo, funciona mais otimizado pois o compilador consegue fazer inline?
def inline_with(~A: Type, ~B: Type, ~C: Type, ~f: A -> B -> C, ab: A & B) -> C:
    (a, b) = ab
    f(a, b)

def inline_with3(~A: Type, ~B: Type, ~C: Type, ~D: Type, ~f: A -> B -> C -> D, abc: (A & B) & C) -> D:
    (ab, c) = abc
    (a, b) = ab
    f(a, b, c)

# ----------------------------------------------------------------
# PROJETAR (o `.0` e o `.1` do Rust)
# ----------------------------------------------------------------
# Descartar a outra metade é permitido: valores `Type` são AFINS (no máximo um
# uso), não lineares (exatamente um). Um `Array` descartado é liberado.

def fst(-A: Type, -B: Type, p: A & B) -> A:
  (a, b) = p
  a

def snd(-A: Type, -B: Type, p: A & B) -> B:
  (a, b) = p
  b

# ----------------------------------------------------------------
# TRANSFORMAR
# ----------------------------------------------------------------

# `(a, b)` -> `(b, a)`
def swap(-A: Type, -B: Type, p: A & B) -> B & A:
  (a, b) = p
  (b, a)

def map_fst(~A: Type, ~B: Type, ~C: Type, ~f: A -> C, p: A & B) -> C & B:
  (a, b) = p
  (f(a), b)

def map_snd(~A: Type, ~B: Type, ~C: Type, ~f: B -> C, p: A & B) -> A & C:
  (a, b) = p
  (a, f(b))

# Junta os dois lados num valor só (o `fold`/`reduce` de uma tupla).
def map(~A: Type, ~B: Type, ~C: Type, ~f: A -> B -> C, p: A & B) -> C:
  (a, b) = p
  f(a, b)

### Monads
# The `do` notation works for any monad, not just IO.

# ```python
# import Base

# def add_strs(a: String, b: String) -> Maybe<&2, U32>:
#   do Maybe<&2, U32>:
#     x : U32 <- U32.read(a) # a None here ends the block with None
#     y : U32 <- U32.read(b)
#     return (x + y : U32)

# def main() -> Maybe<&2, U32>:
#   add_strs("40", "2")
# ```

# A `do M<xs.., R>:` block desugars each `x : A <- v` into `M.bind(xs.., A, R, v,
# x => ..)` and each `return e` into `M.pure(xs.., R, e)`, so any type with those
# two defs works: `IO`, `Maybe`, `Result`, or your own. The leading arguments
# (here, the `&2` quantity) are passed along to both.

# Tuple State Monad
# A ideia é encadear várias operações sobre um mesmo valor S que a cada etapa retorna S & A, e precisamos ler o A
type State<-S: Type, -A: Type> is Type:
  State{run: S -> S & A}

def State.run(-S: Type, -B: Type, st: State<S, B>, s: S) -> S & B:
  State{run} = st
  run(s)

# do State<S, A>:
# ...
# return A   # encerra com State<S, A>
def State.pure(-S: Type, -A: Type, x: A) -> State<S, A>:
  State{s => (s, x)}

def State.bind.step(-S: Type, -A: Type, -B: Type, pair: S & A, f: A -> State<S, B>) -> S & B:
  (s1, a) = pair
  State.run(S, B, f(a), s1)

def State.bind(
  -S: Type, -A: Type, -B: Type,
  run_m: S -> S & A,
  f: A -> State<S, B>
) -> State<S, B>:
  State{s => State.bind.step(S, A, B, run_m(s), f)}

# Recebe um estado que foi construído e um valor inicial, para então executar todas as etapas e por fim devolver o resultado
def run_state(-S: Type, -A: Type, st: State<S, A>, s: S) -> S & A:
  State{run} = st
  run(s)

def run_state_consume(-S: Type, -A: Type, st: State<S, A>, s: S) -> A:
  snd(S, A, run_state(S, A, st, s))