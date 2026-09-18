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
