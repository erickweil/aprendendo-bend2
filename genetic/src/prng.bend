import Base

type Seeds is Data:
  Seeds{s1: U32, s2: U32}

# Xorshift32 PRNG step
def step(+x: U32) -> U32:
  +b = U32.xor(x, U32.shln(x, 13n))
  +d = U32.xor(b, U32.shrn(b, 17n))
  U32.xor(d, U32.shln(d, 5n))

# Seed-splitting for pure tree parallelism
def split(+seed: U32) -> Seeds:
  +s1 = step(seed)
  +s2 = step(U32.xor(s1, 2654435761))
  Seeds{s1, s2}

# Bounded random number in [0, max - 1] (where max > 0)
def range(+seed: U32, +max: U32) -> U32:
  U32.mod(seed, max)
