import Base

# ================================================================
# ALEATORIEDADE (random.bend)
# ================================================================
# Bend é puro: não existe um gerador com estado global como o `fastrand` que o
# motor em Rust usa. Aqui a "semente" é o próprio estado e é passada adiante
# explicitamente; cada ramo de uma chamada paralela recebe um fluxo derivado
# com `split.*`.
#
# O passo é xorshift32 — rápido (3 operações) e uma bijeção nos inteiros não
# nulos —, com uma guarda: `step(0)` vai para uma constante. Sem a guarda o 0
# é um ponto fixo (`xorshift(0) = 0`), e a versão anterior caía nele: os
# `split.*` eram `step(step(s) xor K)`, e para a semente 3783986154
# `split.snd` dava exatamente 0 — dali em diante TODO número daquele ramo
# era 0. Agora nenhum estado é absorvente.
#
# Os `split.*` são `step(s + K)` com constantes distintas, então os fluxos dos
# ramos não coincidem entre si nem com `step` (antes `split.fst` ERA `step`).
#
# Para transformar uma semente num número uniforme (probabilidades, índices),
# `mix` aplica metade do hash `lowbias32`: o xorshift a partir de uma semente
# pequena produz números pequenos nos primeiros passos, e o `mod` de um índice
# usa os bits baixos — `mix` espalha os bits altos para os baixos.
#
# (Um hash completo por passo, no estilo SplitMix, foi medido: custa o dobro
# do xorshift, e o gerador é chamado em quase toda operação dos operadores.)

def xorshift(+x: U32) -> U32:
  +b = U32.xor(x, U32.shln(x, 13n))
  +d = U32.xor(b, U32.shrn(b, 17n))
  U32.xor(d, U32.shln(d, 5n))

# Próximo estado do fluxo (nunca fica preso no 0)
def step(+x: U32) -> U32:
  xorshift(Bool.pick(U32, U32.is_zero(x), 2654435769, x))

# Fluxos independentes para os ramos de uma chamada paralela e para avançar
# um laço externo sem colidir com o que os ramos usam
def split.fst(+seed: U32) -> U32:
  step(U32.add(seed, 1640531527))

def split.snd(+seed: U32) -> U32:
  step(U32.add(seed, 3242174889))

def split.trd(+seed: U32) -> U32:
  step(U32.add(seed, 1013904223))

def split.fth(+seed: U32) -> U32:
  step(U32.add(seed, 3141592653))

# lowbias32 completo (Chris Wellons): usado onde a qualidade importa mais que
# o custo, como derivar sementes de ilhas
def hash32(+x: U32) -> U32:
  +a = U32.xor(x, U32.shrn(x, 16n))
  +b = U32.mul(a, 2146121005)
  +c = U32.xor(b, U32.shrn(b, 15n))
  +d = U32.mul(c, 2221713035)
  U32.xor(d, U32.shrn(d, 16n))

# Semente -> número uniforme em U32 (metade do lowbias32: xor-shift,
# multiplicação e xor-shift, que traz os bits altos para os baixos)
def mix(+seed: U32) -> U32:
  +a = U32.mul(U32.xor(seed, U32.shrn(seed, 16n)), 2146121005)
  U32.xor(a, U32.shrn(a, 15n))

# ----------------------------------------------------------------
# INTEIROS (random_range, random_range_except, random_bool)
# ----------------------------------------------------------------

# Uniforme em [0, n). Com n = 0 devolve 0.
def range(+seed: U32, +n: U32) -> U32:
  U32.mod(mix(seed), U32.max(n, 1))

# Uniforme em [0, n) excluindo `except` (random_range_except do Rust).
# Com n = 1 devolve 0, o único valor possível. Um `except` fora de [0, n)
# significa "sem exclusão" (o primeiro pai de um torneio não exclui ninguém).
def range_except(+seed: U32, +n: U32, +except: U32) -> U32:
  +m = mix(seed)
  +r = U32.mod(m, U32.max((n - 1 : U32), 1))
  Bool.pick(U32, U32.is_ge(except, n), U32.mod(m, U32.max(n, 1)),
    Bool.pick(U32, U32.is_le(n, 1), 0, Bool.pick(U32, U32.is_ge(r, except), U32.inc(r), r)))

def bool(+seed: U32) -> Bool:
  U32.is_even(U32.shrn(mix(seed), 16n))

# `n` números uniformes em [0, max), a partir da semente
def list(n: Nat, +seed: U32, +max: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Con{range(seed, max), list(p, step(seed), max)}

# ----------------------------------------------------------------
# PROBABILIDADE COMO LIMIAR SOBRE 2^32
# ----------------------------------------------------------------
# Uma probabilidade p é o limiar `p * 2^32`; `hit` acerta quando o sorteio cai
# abaixo dele, como `random_f64() < rate` no Rust. Granularidade de 2^-32, o
# que permite taxas por gene como 1/N com N = 1 milhão.

def MAX() -> U32:
  4294967295

# Limiar para a probabilidade num/den (satura em 1 quando num >= den)
def per(+num: U32, +den: U32) -> U32:
  Bool.pick(U32, U32.is_ge(num, den), MAX(),
    U32.mul(U32.div(MAX(), U32.max(den, 1)), num))

# Probabilidade `threshold / 2^32`, com os extremos exatos: limiar 0 nunca
# acerta, limiar máximo sempre acerta
def hit(+seed: U32, +threshold: U32) -> Bool:
  Bool.or(U32.is_eq(threshold, MAX()), U32.is_lt(mix(seed), threshold))

# Limiar como F32 em [0, 1]
def prob(+threshold: U32) -> F32:
  (U32.to_f32(threshold) / {4294967296.0 : F32} : F32)

# Multiplica um limiar por `m`, saturando
def scale(+threshold: U32, +m: F32) -> U32:
  F32.to_u32(F32.min((U32.to_f32(threshold) * m : F32), {4294967040.0 : F32}))

# Uniforme em (0, 1], com 24 bits de precisão (o que um F32 representa)
# (o `mix` sai de dentro da anotação: desde o 2.0.17 um nome local dentro de
# `( .. : F32)` pode ser resolvido como `F32.<nome>` quando o módulo é
# importado, e o erro vira `expected: a defined name, observed: F32.<nome>`)
def unit(+seed: U32) -> F32:
  +m = U32.to_f32(U32.shrn(mix(seed), 8n))
  ((m + {1.0 : F32}) / {16777216.0 : F32} : F32)

# Amostra uniforme em [lo, hi] com 10000 níveis discretos
def rnd_range_f32(+seed: U32, +lo: F32, +hi: F32) -> F32:
  +norm = (U32.to_f32(U32.mod(seed, 10000)) / {10000.0 : F32} : F32)
  (lo + ((hi - lo) * norm) : F32)

# ----------------------------------------------------------------
# POISSON (poisson_knuth_iterator.rs)
# ----------------------------------------------------------------
# Mutar "cada gene com probabilidade p" tem dois portes do Rust:
#
#  - for_each_poisson / PoissonIterator: em vez de sortear p em cada gene,
#    sorteia a DISTÂNCIA até o próximo gene sorteado, com distribuição
#    geométrica: floor(ln(u) / ln(1 - p)). Os operadores de mutação usam `gap`
#    para percorrer a lista pulando direto de um gene sorteado ao próximo.
#    (O Rust troca para o sorteio gene a gene quando p >= 0.1, dizendo que o
#    salto "começa a divergir"; o salto geométrico com ln(1 - p) é exato para
#    qualquer p, então aqui ele é usado sempre.)
#
#  - poisson_knuth_sample: sorteia QUANTAS mutações acontecem, com média
#    lambda = N * p, para operadores que escolhem as posições por conta
#    própria (os horários do Rust, o sudoku daqui).

# ln(1 - p), calculado uma vez por chamada de mutação. Para p pequeno usa a
# série -(p + p²/2): em F32, `1 - 1e-7` arredonda para 1 e o log daria zero.
# (O Rust usa `(-rate).ln_1p()` pelo mesmo motivo.)
def ln_miss(+threshold: U32) -> F32:
  +p = prob(threshold)
  Bool.pick(F32, F32.is_lt(p, {0.01 : F32}),
    (({0.0 : F32} - p) - ((p * p) / {2.0 : F32}) : F32),
    F32.log(({1.0 : F32} - p : F32)))

# Quantos genes pular até o próximo sorteado (geometric_poisson_gap).
# Limiar 0 nunca sorteia; o quociente é limitado antes da conversão porque
# converter um F32 acima de 2^32 para U32 é indefinido em C.
def gap(+seed: U32, +threshold: U32, +lnq: F32) -> U32:
  +lu = F32.log(unit(seed))
  Bool.pick(U32, U32.is_zero(threshold), MAX(),
    F32.to_u32(F32.min((lu / lnq : F32), {4000000000.0 : F32})))

def poisson.go(k: Nat, done: Bool, +p: F32, +l: F32, +count: U32, +seed: U32) -> U32:
  match k done:
    case _ True{}:
      count
    case 0n False{}:
      count
    case 1n+q False{}:
      +u = unit(seed)
      +p2 = (p * u : F32)
      +stop = F32.is_le(p2, l)
      poisson.go(q, stop, p2, l, Bool.pick(U32, stop, count, U32.inc(count)), step(seed))

# Uma amostra de Poisson com média `lambda` (algoritmo de Knuth: multiplica
# uniformes até o produto cair abaixo de e^-lambda). O custo é O(lambda), então
# serve para lambdas pequenos — o caso de "poucas mutações por genoma". O
# combustível limita o laço em 4·lambda + 64 passos (o verificador de
# terminação exige um limite; na prática ele nunca é atingido para lambda
# abaixo de algumas dezenas).
def poisson(+seed: U32, +lambda: F32) -> U32:
  poisson.go(U32.to_nat((F32.to_u32((lambda * {4.0 : F32} : F32)) + 64 : U32)),
    False{}, {1.0 : F32}, F32.exp(({0.0 : F32} - lambda : F32)), 0, seed)
