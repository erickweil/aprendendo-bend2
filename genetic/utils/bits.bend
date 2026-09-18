import Base

# Contagem de bits '1' (Popcount) por indução em palavras Word(32)
def popcount.word(n: Nat, w: Word(n)) -> U32:
  match n w:
    case 0n WNil{}:
      0
    case 1n+p WCon{b, tail}:
      match b:
        case True{}:
          U32.inc(popcount.word(p, tail))
        case False{}:
          popcount.word(p, tail)

def popcount(u: U32) -> U32:
  match u:
    case U32{w}:
      popcount.word(32n, w)

# Máscara de bit: 1 << d
def bit_of(+d: U32) -> U32:
  U32.shln(1, U32.to_nat(d))

# Cruzamento uniforme bit a bit guiado por máscara
def crossover_uniform(+a: U32, +b: U32, +mask: U32) -> U32:
  U32.or(U32.and(a, mask), U32.and(b, U32.not(mask)))

# Mutação pontual: inverte um bit aleatório
def mutate_bit(+g: U32, +rnd: U32) -> U32:
  +bit_idx = U32.to_nat(U32.mod(rnd, 32))
  U32.xor(g, U32.shln(1, bit_idx))

# Unicidade de 9 elementos em microsegundos via bitwise OR + popcount
def group_unique9(
  +c0: U32, +c1: U32, +c2: U32,
  +c3: U32, +c4: U32, +c5: U32,
  +c6: U32, +c7: U32, +c8: U32
) -> U32:
  +m0 = bit_of(c0); +m1 = bit_of(c1); +m2 = bit_of(c2)
  +m3 = bit_of(c3); +m4 = bit_of(c4); +m5 = bit_of(c5)
  +m6 = bit_of(c6); +m7 = bit_of(c7); +m8 = bit_of(c8)
  +mask = U32.or(m0, U32.or(m1, U32.or(m2, U32.or(m3, U32.or(m4, U32.or(m5, U32.or(m6, U32.or(m7, m8))))))))
  popcount(mask)
