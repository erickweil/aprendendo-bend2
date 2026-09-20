import Base
import ./../utils/arrays.bend as Arr
import ./../utils/tuples.bend as T
import ./../utils/random.bend as R

# ================================================================
# OPERADORES DE GENE (operators.bend)
# ================================================================
# Genoma = `Array<U32>` de `n` genes. Todos os operadores são IN-PLACE e não
# alocam: recebem os genomas e devolvem os mesmos buffers.
#
# Há duas famílias:
#
#  - `breed_*` (4 argumentos): o que o motor chama. Lê os dois pais e escreve
#    os dois filhos numa varredura só, que é o "4 entram, 4 saem" do modelo
#    geracional.
#  - `cross_*` (2 argumentos): troca material ENTRE dois genomas, in-place.
#    O motor não os usa diretamente, mas o `~breed` de um problema pode: copie
#    os pais nos filhos com `Arr.copy_range` e depois cruze os filhos entre si.
#    É como escrever um cruzamento que não tem versão de 4 argumentos ainda
#    (o uniforme, por exemplo).
#
# Custo medido das primitivas (n = 2^20): troca de faixa 1,1 ns por posição,
# cópia 0,6 ns, sorteio 2–3,6 ns.

# ----------------------------------------------------------------
# CRUZAMENTO
# ----------------------------------------------------------------

# Um ponto: sorteia o corte em [1, n) e troca o sufixo. O sufixo do pai A é o
# do filho B e vice-versa, exatamente como no crossover clássico.
def cross_1point(a: Array<U32>, b: Array<U32>, +n: U32, +seed: U32) -> Array<U32> & Array<U32>:
  +cut = U32.inc(R.range(seed, U32.max((n - 1 : U32), 1)))
  Arr.swap_range(~U32, a, b, cut, (n - cut : U32))

# Dois pontos: troca o miolo [lo, hi). Com lo == hi não troca nada, o que é o
# mesmo que "sem cruzamento" e acontece com probabilidade 1/n.
def cross_2point(a: Array<U32>, b: Array<U32>, +n: U32, +seed: U32) -> Array<U32> & Array<U32>:
  +p1 = R.range(seed, n)
  +p2 = R.range(R.split.fst(seed), n)
  +lo = U32.min(p1, p2)
  +hi = U32.max(p1, p2)
  Arr.swap_range(~U32, a, b, lo, (hi - lo : U32))

# Uniforme: uma moeda por posição; quando dá cara, os dois genes trocam de
# lugar. `rate` é o limiar de R.hit (use R.per(1, 2) para meio a meio).
def uniform.set_a(a: Array<U32>, +i: U32, r: Array<U32> & U32) -> Array<U32> & Array<U32>:
  (b, value_b) = r
  T.pair(Array<U32>, Array<U32>, Array.set(U32, a, i, value_b), b)

def uniform.one(b: Array<U32>, +i: U32, r: Array<U32> & U32) -> Array<U32> & Array<U32>:
  (a, value_a) = r
  uniform.set_a(a, i, Array.swap(U32, b, i, value_a))

def uniform.pick(hit: Bool, a: Array<U32>, b: Array<U32>, +i: U32) -> Array<U32> & Array<U32>:
  match hit:
    case True{}:
      uniform.one(b, i, Array.get(U32, a, i))
    case False{}:
      T.pair(Array<U32>, Array<U32>, a, b)

def uniform.go(k: Nat, st: Array<U32> & Array<U32>, +i: U32, +rate: U32, +seed: U32) -> Array<U32> & Array<U32>:
  match k:
    case 0n:
      st
    case 1n+p:
      (a, b) = st
      uniform.go(p, uniform.pick(R.hit(seed, rate), a, b, i), (i + 1 : U32), rate, R.step(seed))

def cross_uniform(a: Array<U32>, b: Array<U32>, +n: U32, +rate: U32, +seed: U32) -> Array<U32> & Array<U32>:
  uniform.go(U32.to_nat(n), T.pair(Array<U32>, Array<U32>, a, b), 0, rate, seed)

# ----------------------------------------------------------------
# MUTAÇÃO
# ----------------------------------------------------------------

# Substituição com taxa por gene, pulando com o salto geométrico (o
# for_each_poisson do Rust): em vez de sortear em cada gene, sorteia a
# distância até o próximo gene mutado. Custo O(mutações), não O(n).
# `values` é quantos valores diferentes um gene pode ter (2 para bits).
def mut_replace.go(fuel: Nat, stop: Bool, g: Array<U32>, +i: U32, +n: U32,
                   +values: U32, +rate: U32, +lnq: F32, +seed: U32) -> Array<U32>:
  match fuel stop:
    case _ True{}:
      g
    case 0n False{}:
      g
    case 1n+p False{}:
      +jump = U32.inc(R.gap(R.split.fst(seed), rate, lnq))
      +j = (i + jump : U32)
      mut_replace.go(p, U32.is_ge(j, n),
        Array.set(U32, g, i, R.range(R.split.snd(seed), values)),
        j, n, values, rate, lnq, R.step(seed))

def mut_replace(g: Array<U32>, +n: U32, +values: U32, +rate: U32, +seed: U32) -> Array<U32>:
  +lnq = R.ln_miss(rate)
  +first = R.gap(seed, rate, lnq)
  mut_replace.go(U32.to_nat(n), U32.is_ge(first, n), g, first, n, values, rate, lnq, R.step(seed))

# Troca duas posições sorteadas, `count` vezes. Preserva o multiconjunto de
# genes, então serve para genoma-permutação.
def mut_swap.go(k: Nat, g: Array<U32>, +n: U32, +seed: U32) -> Array<U32>:
  match k:
    case 0n:
      g
    case 1n+p:
      mut_swap.go(p, Arr.swap_at(~U32, g, R.range(seed, n), R.range(R.split.fst(seed), n)), n, R.step(seed))

def mut_swap(g: Array<U32>, +n: U32, +count: U32, +seed: U32) -> Array<U32>:
  mut_swap.go(U32.to_nat(count), g, n, seed)

# ----------------------------------------------------------------
# CRUZAMENTO "4 ENTRAM, 4 SAEM"
# ----------------------------------------------------------------
# Lê os dois pais e escreve os dois filhos numa varredura só, sem cópia
# intermediária. O laço NÃO tem desvio por elemento: o corte divide em duas
# faixas e a segunda só troca o papel dos dois pais. (Uma versão que escolhia
# o pai com `Bool.pick` genérico dentro do laço ficou 3× MAIS LENTA: o
# Bool.pick genérico encaixota o valor, ou seja, aloca por elemento.)

def b1.w(~T: Data, ca: Array<T>, cb: Array<T>, +i: U32, r: Array<T> & T, y: T, pb: Array<T>) ->
  (Array<T> & Array<T>) & (Array<T> & Array<T>):
  (pa, x) = r
  ((Array.set(T, ca, i, x), Array.set(T, cb, i, y)), (pa, pb))

def b1.rb(~T: Data, ca: Array<T>, cb: Array<T>, pa: Array<T>, +i: U32, r: Array<T> & T) ->
  (Array<T> & Array<T>) & (Array<T> & Array<T>):
  (pb, y) = r
  b1.w(~T, ca, cb, i, Array.get(T, pa, i), y, pb)

def b1.step(~T: Data, st: (Array<T> & Array<T>) & (Array<T> & Array<T>), +i: U32) ->
  (Array<T> & Array<T>) & (Array<T> & Array<T>):
  (filhos, pais) = st
  (ca, cb) = filhos
  (pa, pb) = pais
  b1.rb(~T, ca, cb, pa, i, Array.get(T, pb, i))

# copia a faixa [i, i+k): filho A recebe do pai A, filho B do pai B
def b1.go(~T: Data, k: Nat, st: (Array<T> & Array<T>) & (Array<T> & Array<T>), +i: U32) ->
  (Array<T> & Array<T>) & (Array<T> & Array<T>):
  match k:
    case 0n:
      st
    case 1n+p:
      b1.go(~T, p, b1.step(~T, st, i), (i + 1 : U32))

# troca o papel dos dois pais (para a segunda faixa)
def b1.troca(~T: Data, st: (Array<T> & Array<T>) & (Array<T> & Array<T>)) ->
  (Array<T> & Array<T>) & (Array<T> & Array<T>):
  (filhos, pais) = st
  (pa, pb) = pais
  (filhos, (pb, pa))

def b1.dois(~T: Data, st: (Array<T> & Array<T>) & (Array<T> & Array<T>), +cut: U32, +n: U32) ->
  (Array<T> & Array<T>) & (Array<T> & Array<T>):
  b1.troca(~T, b1.go(~T, U32.to_nat((n - cut : U32)), b1.troca(~T, st), cut))

def breed_1point(~T: Data, ca: Array<T>, cb: Array<T>, pa: Array<T>, pb: Array<T>,
                 +n: U32, cruza: Bool, +seed: U32) ->
  (Array<T> & Array<T>) & (Array<T> & Array<T>):
  +cut = Bool.pick(U32, cruza, U32.inc(R.range(seed, U32.max((n - 1 : U32), 1))), n)
  b1.dois(~T, b1.go(~T, U32.to_nat(cut), ((ca, cb), (pa, pb)), 0), cut, n)
