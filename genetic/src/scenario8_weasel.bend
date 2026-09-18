import Base
import ./../ga.bend as GA
import ./../utils/random.bend as R

# ================================================================
# CENÁRIO 8: EVOLUÇÃO DE STRINGS (DAWKINS WEASEL) COM MOTOR GENÉRICO
# ================================================================
# Representação: String de 16 caracteres ASCII em U32 (String16).
# Alvo: "BEND IS PARALLEL"
# Fitness: Quantidade de caracteres coincidentes (0..16).
# ================================================================

type String16 is Data:
  S16{
    c0: U32, c1: U32, c2: U32, c3: U32,
    c4: U32, c5: U32, c6: U32, c7: U32,
    c8: U32, c9: U32, c10: U32, c11: U32,
    c12: U32, c13: U32, c14: U32, c15: U32
  }

def char_match(+c: U32, +target: U32) -> U32:
  Bool.pick(U32, U32.is_eq(c, target), 1, 0)

# Target: "BEND IS PARALLEL"
# 'B'=66, 'E'=69, 'N'=78, 'D'=68, ' '=32
# 'I'=73, 'S'=83, ' '=32
# 'P'=80, 'A'=65, 'R'=82, 'A'=65
# 'L'=76, 'L'=76, 'E'=69, 'L'=76
def fitness(s: String16) -> U32:
  S16{
    c0, c1, c2, c3,
    c4, c5, c6, c7,
    c8, c9, c10, c11,
    c12, c13, c14, c15
  } = s
  +m0 = char_match(c0, 66)
  +m1 = char_match(c1, 69)
  +m2 = char_match(c2, 78)
  +m3 = char_match(c3, 68)
  +m4 = char_match(c4, 32)
  +m5 = char_match(c5, 73)
  +m6 = char_match(c6, 83)
  +m7 = char_match(c7, 32)
  +m8 = char_match(c8, 80)
  +m9 = char_match(c9, 65)
  +m10 = char_match(c10, 82)
  +m11 = char_match(c11, 65)
  +m12 = char_match(c12, 76)
  +m13 = char_match(c13, 76)
  +m14 = char_match(c14, 69)
  +m15 = char_match(c15, 76)

  (m0 + m1 + m2 + m3 + m4 + m5 + m6 + m7 + m8 + m9 + m10 + m11 + m12 + m13 + m14 + m15 : U32)

# Random character: 26 letters ('A'..'Z' = 65..90) or ' ' (32)
def random_char(+s: U32) -> U32:
  +r = U32.mod(s, 27)
  Bool.pick(U32, U32.is_eq(r, 26), 32, (65 + r : U32))

def random_string(+s: U32) -> String16:
  +s0 = R.step(s)
  +s1 = R.step(s0); +s2 = R.step(s1); +s3 = R.step(s2); +s4 = R.step(s3)
  +s5 = R.step(s4); +s6 = R.step(s5); +s7 = R.step(s6); +s8 = R.step(s7)
  +s9 = R.step(s8); +s10 = R.step(s9); +s11 = R.step(s10); +s12 = R.step(s11)
  +s13 = R.step(s12); +s14 = R.step(s13); +s15 = R.step(s14)
  S16{
    random_char(s0), random_char(s1), random_char(s2), random_char(s3),
    random_char(s4), random_char(s5), random_char(s6), random_char(s7),
    random_char(s8), random_char(s9), random_char(s10), random_char(s11),
    random_char(s12), random_char(s13), random_char(s14), random_char(s15)
  }

def init_string(seed: U32) -> String16:
  random_string(seed)

def String16.set(s: String16, +idx: U32, +val: U32) -> String16:
  S16{
    c0, c1, c2, c3,
    c4, c5, c6, c7,
    c8, c9, c10, c11,
    c12, c13, c14, c15
  } = s
  S16{
    Bool.pick(U32, U32.is_eq(idx, 0), val, c0),
    Bool.pick(U32, U32.is_eq(idx, 1), val, c1),
    Bool.pick(U32, U32.is_eq(idx, 2), val, c2),
    Bool.pick(U32, U32.is_eq(idx, 3), val, c3),
    Bool.pick(U32, U32.is_eq(idx, 4), val, c4),
    Bool.pick(U32, U32.is_eq(idx, 5), val, c5),
    Bool.pick(U32, U32.is_eq(idx, 6), val, c6),
    Bool.pick(U32, U32.is_eq(idx, 7), val, c7),
    Bool.pick(U32, U32.is_eq(idx, 8), val, c8),
    Bool.pick(U32, U32.is_eq(idx, 9), val, c9),
    Bool.pick(U32, U32.is_eq(idx, 10), val, c10),
    Bool.pick(U32, U32.is_eq(idx, 11), val, c11),
    Bool.pick(U32, U32.is_eq(idx, 12), val, c12),
    Bool.pick(U32, U32.is_eq(idx, 13), val, c13),
    Bool.pick(U32, U32.is_eq(idx, 14), val, c14),
    Bool.pick(U32, U32.is_eq(idx, 15), val, c15)
  }

def mutate_string(+s: String16, +rnd: U32) -> String16:
  +s1 = R.step(rnd)
  +s2 = R.step(s1)
  +idx = U32.mod(s1, 16)
  +new_char = random_char(s2)
  String16.set(s, idx, new_char)

def crossover_string(a: String16, b: String16, +mask: U32) -> String16:
  S16{
    a0, a1, a2, a3, a4, a5, a6, a7,
    a8, a9, a10, a11, a12, a13, a14, a15
  } = a
  S16{
    b0, b1, b2, b3, b4, b5, b6, b7,
    b8, b9, b10, b11, b12, b13, b14, b15
  } = b
  S16{
    Bool.pick(U32, U32.is_ne(U32.and(mask, 1), 0), a0, b0),
    Bool.pick(U32, U32.is_ne(U32.and(mask, 2), 0), a1, b1),
    Bool.pick(U32, U32.is_ne(U32.and(mask, 4), 0), a2, b2),
    Bool.pick(U32, U32.is_ne(U32.and(mask, 8), 0), a3, b3),
    Bool.pick(U32, U32.is_ne(U32.and(mask, 16), 0), a4, b4),
    Bool.pick(U32, U32.is_ne(U32.and(mask, 32), 0), a5, b5),
    Bool.pick(U32, U32.is_ne(U32.and(mask, 64), 0), a6, b6),
    Bool.pick(U32, U32.is_ne(U32.and(mask, 128), 0), a7, b7),
    Bool.pick(U32, U32.is_ne(U32.and(mask, 256), 0), a8, b8),
    Bool.pick(U32, U32.is_ne(U32.and(mask, 512), 0), a9, b9),
    Bool.pick(U32, U32.is_ne(U32.and(mask, 1024), 0), a10, b10),
    Bool.pick(U32, U32.is_ne(U32.and(mask, 2048), 0), a11, b11),
    Bool.pick(U32, U32.is_ne(U32.and(mask, 4096), 0), a12, b12),
    Bool.pick(U32, U32.is_ne(U32.and(mask, 8192), 0), a13, b13),
    Bool.pick(U32, U32.is_ne(U32.and(mask, 16384), 0), a14, b14),
    Bool.pick(U32, U32.is_ne(U32.and(mask, 32768), 0), a15, b15)
  }

def reproduce(parent: String16, champ: String16, seed: U32) -> String16:
  +s1 = R.step(seed)
  +s2 = R.step(s1)
  +crossed = crossover_string(parent, champ, s1)
  mutate_string(crossed, s2)

def String16.show(s: String16) -> String:
  S16{
    c0, c1, c2, c3,
    c4, c5, c6, c7,
    c8, c9, c10, c11,
    c12, c13, c14, c15
  } = s
  "\"" ++
  Char.show(Char.from_u32(c0)) ++ Char.show(Char.from_u32(c1)) ++
  Char.show(Char.from_u32(c2)) ++ Char.show(Char.from_u32(c3)) ++
  Char.show(Char.from_u32(c4)) ++ Char.show(Char.from_u32(c5)) ++
  Char.show(Char.from_u32(c6)) ++ Char.show(Char.from_u32(c7)) ++
  Char.show(Char.from_u32(c8)) ++ Char.show(Char.from_u32(c9)) ++
  Char.show(Char.from_u32(c10)) ++ Char.show(Char.from_u32(c11)) ++
  Char.show(Char.from_u32(c12)) ++ Char.show(Char.from_u32(c13)) ++
  Char.show(Char.from_u32(c14)) ++ Char.show(Char.from_u32(c15)) ++
  "\""

def main_seed() -> U32:
  991122

def main() -> IO(Unit):
  +s0 = main_seed()
  # População inicial: 64 indivíduos (profundidade 6)
  +pop0 = GA.gen_population(~String16, ~init_string, ~fitness, 6n, s0)
  +best0 = GA.best_ind(String16, pop0)
  +g0 = GA.Ind.gene(String16, best0)
  +f0 = GA.Ind.fit(String16, best0)

  # Evolução por 75 gerações com elitismo no motor ga.bend
  +pop_final = GA.run_generations(~String16, ~reproduce, ~fitness, 75n, pop0, R.step(s0))
  +best_fin = GA.best_ind(String16, pop_final)
  +g_fin = GA.Ind.gene(String16, best_fin)
  +f_fin = GA.Ind.fit(String16, best_fin)

  IO.print(
    "=== CENÁRIO 8: EVOLUÇÃO DE STRINGS (DAWKINS WEASEL) ===\n" ++
    "Alvo: \"BEND IS PARALLEL\" (16 caracteres)\n" ++
    "População: 64 indivíduos (árvore binária profundidade 6)\n" ++
    "Geração 0  - " ++ String16.show(g0) ++ " | Fitness: " ++ U32.show(f0) ++ " / 16\n" ++
    "Geração 75 - " ++ String16.show(g_fin) ++ " | Fitness: " ++ U32.show(f_fin) ++ " / 16\n" ++
    "Alvo Alcançado? " ++ Bool.show(U32.is_eq(f_fin, 16)) ++ "\n"
  )
