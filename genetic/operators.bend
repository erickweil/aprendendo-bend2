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
# Como no Rust, DOIS PAIS PRODUZEM DOIS FILHOS. Em todos os operadores do
# Rust o filho B é o filho A com os papéis dos pais trocados e os MESMOS
# sorteios (mesmos cortes, mesmas moedas). Então cada operador tem duas
# formas:
#   child_*(a, b, ..., seed) -> G        o filho A (para compor, ex.: sudoku)
#   cross_*(a, b, ..., seed) -> G & G    o par (child(a, b, s), child(b, a, s))
#
# Por que duas varreduras e não uma que monta os dois filhos juntos,
# devolvendo o par a cada gene? Medido no motor, no nativo: a varredura
# fundida deixou o GA 1,6x (1 ponto) a 3,4x (uniforme) mais LENTO, apesar de
# um microbenchmark isolado (filhos somados e descartados na hora) a mostrar
# 2x mais rápida. Os filhos de um GA vivem gerações e são percorridos de
# novo; montados por pares, saem mais caros de percorrer.
#
# O problema escolhe o operador passando-o como template `~cross` ao motor:
# substituído em tempo de compilação, não vira uma closure em runtime. As
# Leis 9-10 (LAWS.bend) provam isso por reflexividade.
# ================================================================

# ----------------------------------------------------------------
# CRUZAMENTO DE 1 E 2 PONTOS: copia o prefixo, COMPARTILHA a cauda
# ----------------------------------------------------------------
# O Rust faz `clone_from_slice` dos trechos. Numa lista imutável dá para fazer
# melhor: depois do último corte, o filho é LITERALMENTE a cauda de um dos
# pais, então ela é compartilhada em vez de copiada. Só o prefixo até o corte
# é alocado, e nenhum número aleatório é sorteado por gene.

# Os `k` primeiros genes de `a` seguidos de `b` a partir da posição k.
# Percorre os dois pais juntos só até o corte; o resto de `b` volta como está.
def splice.go(-G: Data, a: List<&2, G>, b: List<&2, G>, stop: Bool, +k: U32) -> List<&2, G>:
  match a b stop:
    case _ Nil{} _:
      Nil{}
    case _ Con{y, ys} True{}:
      Con{y, ys}
    case Nil{} Con{y, ys} False{}:
      Con{y, ys}
    case Con{x, xs} Con{y, ys} False{}:
      Con{x, splice.go(G, xs, ys, U32.is_eq(k, 1), (k - 1 : U32))}

def splice(-G: Data, a: List<&2, G>, b: List<&2, G>, +k: U32) -> List<&2, G>:
  splice.go(G, a, b, U32.is_zero(k), k)

# Prefixo de A até um corte em [0, n) (random_range(0, len) do Rust; com corte
# 0 o filho é B inteiro), sufixo de B
def child_1point(-G: Data, a: List<&2, G>, b: List<&2, G>, +n: U32, +seed: U32) -> List<&2, G>:
  splice(G, a, b, R.range(seed, n))

# (a[0, k) ++ b[k, n),  b[0, k) ++ a[k, n))
def cross_1point(-G: Data, +a: List<&2, G>, +b: List<&2, G>, +n: U32, +seed: U32) -> List<&2, G> & List<&2, G>:
  (child_1point(G, a, b, n, seed), child_1point(G, b, a, n, seed))

# Dois cortes DISTINTOS e ordenados lo < hi (como no Rust): A[0, lo) ++
# B[lo, hi) ++ A[hi, n). Montado como dois splices: primeiro B[0, hi) ++
# A[hi, n), depois o prefixo A[0, lo) sobre isso. A cauda A[hi, n) é
# compartilhada com o pai.
def child_2point(-G: Data, +a: List<&2, G>, b: List<&2, G>, +n: U32, +seed: U32) -> List<&2, G>:
  +c1 = R.range(seed, n)
  +c2 = R.range_except(R.step(seed), n, c1)
  splice(G, a, splice(G, b, a, U32.max(c1, c2)), U32.min(c1, c2))

# O trecho [lo, hi) trocado entre os pais
def cross_2point(-G: Data, +a: List<&2, G>, +b: List<&2, G>, +n: U32, +seed: U32) -> List<&2, G> & List<&2, G>:
  (child_2point(G, a, b, n, seed), child_2point(G, b, a, n, seed))

# ----------------------------------------------------------------
# CRUZAMENTO UNIFORME
# ----------------------------------------------------------------
# Cada posição vem de um pai ou do outro com 50% de chance (random_bool). A
# escolha da próxima posição é sorteada aqui e desce como PARÂMETRO. Com a
# mesma semente e os pais trocados, as moedas são as mesmas: o filho B leva
# exatamente os genes que o A não levou.

def uniform.go(-G: Data, a: List<&2, G>, b: List<&2, G>, from_a: Bool, +seed: U32) -> List<&2, G>:
  match a b from_a:
    case Nil{} _ _:
      Nil{}
    case _ Nil{} _:
      Nil{}
    case Con{x, xs} Con{y, ys} True{}:
      +ns = R.step(seed)
      Con{x, uniform.go(G, xs, ys, R.bool(ns), ns)}
    case Con{x, xs} Con{y, ys} False{}:
      +ns = R.step(seed)
      Con{y, uniform.go(G, xs, ys, R.bool(ns), ns)}

def child_uniform(-G: Data, a: List<&2, G>, b: List<&2, G>, +seed: U32) -> List<&2, G>:
  uniform.go(G, a, b, R.bool(seed), seed)

def cross_uniform(-G: Data, +a: List<&2, G>, +b: List<&2, G>, +seed: U32) -> List<&2, G> & List<&2, G>:
  (child_uniform(G, a, b, seed), child_uniform(G, b, a, seed))

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
# sudoku as chaves são os dígitos 1..9 (keys = 10). As marcas de "já copiado"
# ficam num `Array<U32>` local — O(1) por consulta no nativo, e sem limite de tamanho (o Rust usa um
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

# Um filho com cortes dados: o segmento [p1, p2] de `a`, completado com os genes de `b`
def ox1_fill(~G: Data, ~key: G -> U32, a: List<&2, G>, b: List<&2, G>,
              +n: U32, +keys: U32, +p1: U32, +p2: U32) -> List<&2, G>:
  +seg = V.take(G, V.drop(G, a, p1), ((p2 - p1 : U32) + 1 : U32))
  +start = U32.mod((p2 + 1 : U32), n)
  marks = mark(~G, ~key, seg, Array.new(U32, V.depth_for(keys), 0))
  rest = unmarked(~G, ~key, V.rotate(G, b, start), marks)
  V.rotate(G, V.append(G, rest, seg), U32.mod((n - start : U32), n))

# O filho A, com dois cortes distintos sorteados como no Rust
# (random_range_except)
def child_ox1(~G: Data, ~key: G -> U32, a: List<&2, G>, b: List<&2, G>,
              +n: U32, +keys: U32, +seed: U32) -> List<&2, G>:
  +c1 = R.range(seed, n)
  +c2 = R.range_except(R.step(seed), n, c1)
  ox1_fill(~G, ~key, a, b, n, keys, U32.min(c1, c2), U32.max(c1, c2))

# Os dois filhos, com os MESMOS cortes (como os dois laços do Rust): o A leva
# o segmento de `a` e é completado por `b`; o B, o contrário
def cross_ox1(~G: Data, ~key: G -> U32, +a: List<&2, G>, +b: List<&2, G>,
              +n: U32, +keys: U32, +seed: U32) -> List<&2, G> & List<&2, G>:
  (child_ox1(~G, ~key, a, b, n, keys, seed), child_ox1(~G, ~key, b, a, n, keys, seed))
