import Base

# PRNG Xorshift32 de alta performance
def step(+x: U32) -> U32:
  +b = U32.xor(x, U32.shln(x, 13n))
  +d = U32.xor(b, U32.shrn(b, 17n))
  U32.xor(d, U32.shln(d, 5n))

# Divisão de sementes para paralelismo de árvore binária
def split.fst(+seed: U32) -> U32:
  step(seed)

def split.snd(+seed: U32) -> U32:
  step(U32.xor(step(seed), 2654435761))

def split.trd(+seed: U32) -> U32:
  step(U32.xor(step(seed), 1013904223))

def split.fth(+seed: U32) -> U32:
  step(U32.xor(step(seed), 3141592653))

# Valor aleatório em [min, max] inclusivo
def mod_range(+rnd: U32, +min: U32, +max: U32) -> U32:
  +span = ((max - min : U32) + 1 : U32)
  (min + U32.mod(rnd, span) : U32)

# Probabilidade percentual: chance(rnd, 40) é True com 40% de probabilidade
def chance(+rnd: U32, +percent: U32) -> Bool:
  U32.is_lt(U32.mod(rnd, 100), percent)

# ----------------------------------------------------------------
# PROBABILIDADE COMO LIMIAR SOBRE 2^32
# ----------------------------------------------------------------
# `chance` tem granularidade de 1%, o que não serve para taxas por gene do
# tipo 1/N com N = 1 milhão. Aqui a probabilidade é um limiar U32: um sorteio
# `seed` "acerta" quando cai abaixo dele. `per(1, n)` é a chance 1/n.

# Limiar para a probabilidade num/den (satura em 1 quando num >= den)
def per(+num: U32, +den: U32) -> U32:
  Bool.pick(U32, U32.is_ge(num, den), 4294967295,
    U32.mul(U32.div(4294967295, U32.max(den, 1)), num))

# Espalha a semente antes de usá-la como número uniforme. O xorshift a partir
# de uma semente pequena produz números pequenos nos primeiros passos
# (step(5) = 1351845), o que viciaria qualquer probabilidade calculada
# diretamente da semente. A multiplicação pela constante de Knuth é uma
# bijeção em U32, então sobre sementes uniformes a distribuição não muda.
def mix(+seed: U32) -> U32:
  U32.mul(seed, 2654435761)

# Verdadeiro com a probabilidade representada por `threshold`.
# O limiar máximo sempre acerta; o limiar 0 acerta só se mix(seed) = 0, o que
# só acontece para a semente 0 (que o xorshift nunca produz).
def hit(+seed: U32, +threshold: U32) -> Bool:
  U32.is_le(mix(seed), threshold)
