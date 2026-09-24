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
