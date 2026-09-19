import Base
import ./../utils/random.bend as R
import ./utils/genes.bend as V

# ================================================================
# BEND 2 GENETIC OPERATORS - CRUZAMENTOS (operators.bend)
# ================================================================
# Todos os operadores de cruzamento do motor, portados do motor em Rust
# (`rust-wasm/src/genetic/operators/crossover_operators.rs`).
#
# Todos operam sobre `List<&2, G>` e são genéricos sobre o tipo do gene `G`.
# Nenhum tem limite de tamanho: funcionam igual para 10 genes ou 1 milhão.
#
# As combinações de operadores usam parâmetros template `~`, substituídos em
# tempo de compilação: o operador escolhido NÃO vira uma closure em runtime,
# é inlinado no ponto de chamada. As Leis 8-11 (LAWS.bend) provam isso por
# reflexividade.
# ================================================================

# ----------------------------------------------------------------
# CRUZAMENTO DE 1 E 2 PONTOS: copia o prefixo, COMPARTILHA a cauda
# ----------------------------------------------------------------
# O Rust faz `clone_from_slice` dos trechos. Numa lista imutável dá para fazer
# melhor: depois do último corte, o filho é LITERALMENTE a cauda de um dos
# pais, então ela é compartilhada em vez de copiada. Só o prefixo até o corte
# é alocado, e nenhum número aleatório é sorteado por gene.

# Os `k` primeiros genes de `a` seguidos de `b` a partir da posição k.
# Percorre os dois pais juntos só até o corte; o resto de `b` é devolvido
# como está.
def splice.go(-G: Data, a: List<&2, G>, b: List<&2, G>, stop: Bool, +k: U32) -> List<&2, G>:
  match a b stop:
    case Nil{} Nil{} True{}:
      Nil{}
    case Nil{} Nil{} False{}:
      Nil{}
    case Nil{} Con{y, ys} True{}:
      Con{y, ys}
    case Nil{} Con{y, ys} False{}:
      Con{y, ys}
    case Con{x, xs} Nil{} True{}:
      Nil{}
    case Con{x, xs} Nil{} False{}:
      Nil{}
    case Con{x, xs} Con{y, ys} True{}:
      Con{y, ys}
    case Con{x, xs} Con{y, ys} False{}:
      Con{x, splice.go(G, xs, ys, U32.is_eq(k, 1), (k - 1 : U32))}

def splice(-G: Data, a: List<&2, G>, b: List<&2, G>, +k: U32) -> List<&2, G>:
  splice.go(G, a, b, U32.is_zero(k), k)

# Prefixo de A até um corte em [1, n-1], sufixo de B
def cross_1point(-G: Data, a: List<&2, G>, b: List<&2, G>, +n: U32, +seed: U32) -> List<&2, G>:
  splice(G, a, b, (1 + U32.mod(seed, U32.max((n - 1 : U32), 1)) : U32))

# Dois cortes ordenados: A[0, lo) ++ B[lo, hi) ++ A[hi, n)
# Montado como dois splices: primeiro B[0, hi) ++ A[hi, n), depois o prefixo
# A[0, lo) sobre isso. A cauda A[hi, n) é compartilhada com o pai.
def cross_2point(-G: Data, +a: List<&2, G>, b: List<&2, G>, +n: U32, +seed: U32) -> List<&2, G>:
  +c1 = U32.mod(seed, n)
  +c2 = U32.mod(R.step(seed), n)
  splice(G, a, splice(G, b, a, U32.max(c1, c2)), U32.min(c1, c2))

# ----------------------------------------------------------------
# CRUZAMENTO UNIFORME
# ----------------------------------------------------------------
# Cada posição vem de um pai ou do outro com 50% de chance. A escolha da
# próxima posição é sorteada aqui e desce como PARÂMETRO (Armadilha 5).

def uniform.go(-G: Data, a: List<&2, G>, b: List<&2, G>, from_a: Bool, +seed: U32) -> List<&2, G>:
  match a b from_a:
    case Nil{} Nil{} True{}:
      Nil{}
    case Nil{} Nil{} False{}:
      Nil{}
    case Nil{} Con{y, ys} True{}:
      Nil{}
    case Nil{} Con{y, ys} False{}:
      Nil{}
    case Con{x, xs} Nil{} True{}:
      Nil{}
    case Con{x, xs} Nil{} False{}:
      Nil{}
    case Con{x, xs} Con{y, ys} True{}:
      +ns = R.step(seed)
      Con{x, uniform.go(G, xs, ys, U32.is_even(U32.shrn(ns, 16n)), ns)}
    case Con{x, xs} Con{y, ys} False{}:
      +ns = R.step(seed)
      Con{y, uniform.go(G, xs, ys, U32.is_even(U32.shrn(ns, 16n)), ns)}

def cross_uniform(-G: Data, a: List<&2, G>, b: List<&2, G>, +seed: U32) -> List<&2, G>:
  uniform.go(G, a, b, U32.is_even(U32.shrn(seed, 16n)), seed)

# ----------------------------------------------------------------
# ORDER CROSSOVER (OX1) — para genomas que SÃO uma permutação
# ----------------------------------------------------------------
# Cruzamento posicional gera genes repetidos e destrói permutações. O OX1
# copia um segmento [p1, p2] de A e completa o resto com os genes de B que
# faltam, na ordem em que B os apresenta, começando logo depois de p2 e dando
# a volta.
#
# Como no Rust, o chamador fornece `~key: G -> U32`, que dá a cada gene um
# índice único em [0, keys) — `keys` é o `possible_gene_values` do
# `CrossoverOX1::new`. Pode ser maior que o comprimento `n`: numa linha de
# sudoku com 5 células livres as chaves são os dígitos 1..9 (keys = 10). As marcas de "já copiado" ficam num `Array<U32>`
# local — O(1) por consulta no nativo, e sem limite de tamanho (o Rust usa um
# vetor de marcas com epoch; aqui o array é novo a cada cruzamento, então nem
# o epoch é necessário).
#
# A montagem é feita na ordem "dando a volta a partir de p2+1": nessa ordem o
# filho é exatamente `faltantes ++ segmento`. Uma rotação final devolve o
# segmento para a posição p1 original. Custo total: O(n).

def mark(~G: Data, ~key: G -> U32, l: List<&2, G>, a: Array<U32>) -> Array<U32>:
  match l:
    case Nil{}:
      a
    case Con{h, t}:
      mark(~G, ~key, t, Array.set(U32, a, key(h), 1))

def put_if(-G: Data, h: G, rest: List<&2, G>, keep: Bool) -> List<&2, G>:
  match keep:
    case True{}:
      Con{h, rest}
    case False{}:
      rest

# `cur` é o gene em avaliação e `r` traz o array junto com a marca DELE.
# O array desce afim pela recursão: um dono só, escrita e leitura in-place.
def unmarked.go(~G: Data, ~key: G -> U32, l: List<&2, G>, r: Array<U32> & U32, cur: G) -> List<&2, G>:
  match l:
    case Nil{}:
      (a, v) = r
      put_if(G, cur, Nil{}, U32.is_zero(v))
    case Con{+h, t}:
      (a, v) = r
      put_if(G, cur, unmarked.go(~G, ~key, t, Array.get(U32, a, key(h)), h), U32.is_zero(v))

# Os genes de `l` ainda não marcados, na ordem em que aparecem
def unmarked(~G: Data, ~key: G -> U32, l: List<&2, G>, a: Array<U32>) -> List<&2, G>:
  match l:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      unmarked.go(~G, ~key, t, Array.get(U32, a, key(h)), h)

def cross_ox1(~G: Data, ~key: G -> U32, a: List<&2, G>, b: List<&2, G>,
              +n: U32, +keys: U32, +seed: U32) -> List<&2, G>:
  +c1 = U32.mod(seed, n)
  +c2 = U32.mod(R.step(seed), n)
  +p1 = U32.min(c1, c2)
  +p2 = U32.max(c1, c2)
  +seg = V.take(G, V.drop(G, a, p1), ((p2 - p1 : U32) + 1 : U32))
  +start = U32.mod((p2 + 1 : U32), n)
  marks = mark(~G, ~key, seg, Array.new(U32, V.depth_for(keys), 0))
  rest = unmarked(~G, ~key, V.rotate(G, b, start), marks)
  V.rotate(G, V.append(G, rest, seg), U32.mod((n - start : U32), n))

# ----------------------------------------------------------------
# COMBINADORES DE REPRODUÇÃO
# ----------------------------------------------------------------
# Taxas são limiares sobre 2^32 (veja `R.per`): `R.per(9, 10)` = 90%.

# Despacho exclusivo entre cruzar e clonar o pai 1
def branch_cross(~G: Type, ~cross: G -> G -> U32 -> G,
                 cond: Bool, p1: G, p2: G, +seed: U32) -> G:
  match cond:
    case True{}:
      cross(p1, p2, seed)
    case False{}:
      p1

# Cruza com probabilidade `rate`; senão herda o pai 1 intacto (Holland)
def crossover_or_clone(~G: Type, ~cross: G -> G -> U32 -> G,
                       +rate: U32, p1: G, p2: G, +seed: U32) -> G:
  branch_cross(~G, ~cross, R.hit(seed, rate), p1, p2, R.step(seed))

# Pipeline canônico: cruzamento seguido de mutação, sementes independentes
def pipe(~G: Type, ~cross: G -> G -> U32 -> G, ~mut: G -> U32 -> G,
         p1: G, p2: G, +seed: U32) -> G:
  +s1 = R.step(seed)
  +s2 = R.step(s1)
  mut(cross(p1, p2, s1), s2)
