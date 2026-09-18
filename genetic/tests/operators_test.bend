import Base
import ./../operators.bend as Op
import ./../utils/perm.bend as Perm
import ./../utils/bits.bend as B
import ./../utils/random.bend as R

# ================================================================
# TESTE EXAUSTIVO DA BIBLIOTECA DE OPERADORES (operators.bend)
# ================================================================
# Varre milhares de sementes verificando os invariantes de cada
# operador. Complementa as leis formais de LAWS.bend: as leis provam
# as propriedades que o verificador consegue normalizar simbolicamente
# (composição dos combinadores, despacho exclusivo), este teste cobre
# as que exigiriam explosão combinatória para serem provadas
# (validade de permutação do OX1/PMX, conservação de popcount).
# ================================================================

# ----------------------------------------------------------------
# SEÇÃO C: OPERADORES DE PERMUTAÇÃO
# ----------------------------------------------------------------

# Popcount da máscara de alelos: 8 <=> permutação válida de 0..7
def perm_valid(p: Perm.Perm8) -> U32:
  Perm.P8{x0, x1, x2, x3, x4, x5, x6, x7} = p
  B.popcount(U32.or(B.bit_of(x0), U32.or(B.bit_of(x1), U32.or(B.bit_of(x2),
    U32.or(B.bit_of(x3), U32.or(B.bit_of(x4), U32.or(B.bit_of(x5),
      U32.or(B.bit_of(x6), B.bit_of(x7)))))))))

def shuffle(n: Nat, +p: Perm.Perm8, +s: U32) -> Perm.Perm8:
  match n:
    case 0n:
      p
    case 1n+q:
      +s = s
      +s1 = R.step(s)
      +s1 = s1
      shuffle(q, Perm.Perm8.swap(p, U32.mod(s, 8), U32.mod(s1, 8)), R.step(s1))

# Todo operador de permutação deve fechar sobre permutações válidas
def check_perm(+s: U32) -> U32:
  +s = s
  +p1 = shuffle(12n, Perm.P8{0, 1, 2, 3, 4, 5, 6, 7}, s)
  +p2 = shuffle(9n, Perm.P8{0, 1, 2, 3, 4, 5, 6, 7}, R.step(U32.xor(s, 987654321)))
  +v_ox1 = perm_valid(Op.cross_perm_ox1(p1, p2, s))
  +v_pmx = perm_valid(Op.cross_perm_pmx(p1, p2, s))
  +v_ds  = perm_valid(Op.cross_perm_directed_swap(p1, p2, s))
  +v_rev = perm_valid(Op.mut_perm_reverse_segment(p1, s))
  +v_scr = perm_valid(Op.mut_perm_scramble(p1, s))
  +v_nsw = perm_valid(Op.mut_perm_neighbor_swap(p2, s))
  +ok = Bool.and(U32.is_eq(v_ox1, 8), Bool.and(U32.is_eq(v_pmx, 8),
        Bool.and(U32.is_eq(v_ds, 8), Bool.and(U32.is_eq(v_rev, 8),
        Bool.and(U32.is_eq(v_scr, 8), U32.is_eq(v_nsw, 8))))))
  Bool.pick(U32, ok, 1, 0)

# ----------------------------------------------------------------
# SEÇÃO B: OPERADORES BINÁRIOS
# ----------------------------------------------------------------

# Invariantes verificados por semente:
#  1. mut_bits_swap conserva o popcount (troca posições, não valores)
#  2. mut_bits_swap_blocks conserva o popcount (permuta bytes)
#  3. mut_bits_invert_block é involutivo com a mesma semente
#  4. mut_bits_multi(0%)   é a identidade
#  5. mut_bits_multi(100%) é a negação bit a bit
#  6. todo bit do filho de 1-point / 2-point vem de algum dos pais
def from_parents(+child: U32, +p1: U32, +p2: U32) -> Bool:
  +ones_ok  = U32.is_zero(U32.and(child, U32.and(U32.not(p1), U32.not(p2))))
  +zeros_ok = U32.is_zero(U32.and(U32.not(child), U32.and(p1, p2)))
  Bool.and(ones_ok, zeros_ok)

def check_bits(+s: U32) -> U32:
  +s = s
  +g  = R.step(s)
  +g  = g
  +p2 = R.step(R.step(U32.xor(s, 2654435761)))
  +p2 = p2
  +pc = B.popcount(g)
  +pc = pc
  +i1 = U32.is_eq(B.popcount(Op.mut_bits_swap(g, s)), pc)
  +i2 = U32.is_eq(B.popcount(Op.mut_bits_swap_blocks(g, s)), pc)
  +i3 = U32.is_eq(Op.mut_bits_invert_block(Op.mut_bits_invert_block(g, s), s), g)
  +i4 = U32.is_eq(Op.mut_bits_multi(0, g, s), g)
  +i5 = U32.is_eq(Op.mut_bits_multi(100, g, s), U32.not(g))
  +i6 = from_parents(Op.cross_bits_1point(g, p2, s), g, p2)
  +i7 = from_parents(Op.cross_bits_2point(g, p2, s), g, p2)
  +ok = Bool.and(i1, Bool.and(i2, Bool.and(i3, Bool.and(i4,
        Bool.and(i5, Bool.and(i6, i7))))))
  Bool.pick(U32, ok, 1, 0)

# ----------------------------------------------------------------
# SEÇÃO A: COMBINADORES HIGHER-ORDER
# ----------------------------------------------------------------

# Invariantes das taxas de probabilidade nos extremos:
#  1. crossover_or_clone a 0%   sempre clona o pai 1
#  2. crossover_or_clone a 100% sempre cruza
#  3. maybe_mutate a 0%         é a identidade
#  4. maybe_mutate a 100%       sempre muta
#  5. combine_mutations a 100%  sempre escolhe o primeiro operador
def check_combinators(+s: U32) -> U32:
  +s = s
  +g  = R.step(s)
  +g  = g
  +p2 = R.step(R.step(U32.xor(s, 1013904223)))
  +p2 = p2
  +s1 = R.step(s)
  +s1 = s1
  +c1 = U32.is_eq(Op.crossover_or_clone(~U32, ~Op.cross_bits_uniform, 0, g, p2, s), g)
  +c2 = U32.is_eq(Op.crossover_or_clone(~U32, ~Op.cross_bits_uniform, 100, g, p2, s),
                  Op.cross_bits_uniform(g, p2, s1))
  +c3 = U32.is_eq(Op.maybe_mutate(~U32, ~Op.mut_bit_flip32, 0, g, s), g)
  +c4 = U32.is_eq(Op.maybe_mutate(~U32, ~Op.mut_bit_flip32, 100, g, s),
                  Op.mut_bit_flip32(g, s1))
  +c5 = U32.is_eq(
          Op.combine_mutations(~U32, ~Op.mut_bit_flip32, ~Op.mut_bits_invert_block, 100, g, s),
          Op.mut_bit_flip32(g, s1))
  +ok = Bool.and(c1, Bool.and(c2, Bool.and(c3, Bool.and(c4, c5))))
  Bool.pick(U32, ok, 1, 0)

# ----------------------------------------------------------------
# VARREDURA
# ----------------------------------------------------------------

def sweep_perm(n: Nat, +s: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+q:
      +s = s
      sweep_perm(q, R.step(s), (acc + check_perm(s) : U32))

def sweep_bits(n: Nat, +s: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+q:
      +s = s
      sweep_bits(q, R.step(s), (acc + check_bits(s) : U32))

def sweep_comb(n: Nat, +s: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+q:
      +s = s
      sweep_comb(q, R.step(s), (acc + check_combinators(s) : U32))

# Demonstração de que a inversão 2-opt é uma reversão completa do trecho
def rev_demo(+lo: U32, +hi: U32) -> String:
  +lo = lo
  +hi = hi
  Perm.Perm8.show(Op.perm_reverse_range(4n, U32.is_lt(lo, hi), Perm.P8{0, 1, 2, 3, 4, 5, 6, 7}, lo, hi))

def verdict(+got: U32, +want: U32) -> String:
  U32.show(got) ++ " / " ++ U32.show(want) ++
  Bool.pick(String, U32.is_eq(got, want), "  [OK]", "  [FALHOU]")

def main() -> IO(Unit):
  +n_perm = sweep_perm(2000n, 20250918, 0)
  +n_bits = sweep_bits(2000n, 77777777, 0)
  +n_comb = sweep_comb(2000n, 13572468, 0)
  IO.print(
    "=== TESTE DA BIBLIOTECA DE OPERADORES (operators.bend) ===\n\n" ++
    "Secao C - permutacoes validas (6 operadores x 2000 sementes): " ++ verdict(n_perm, 2000) ++ "\n" ++
    "Secao B - invariantes binarios (7 checagens x 2000 sementes): " ++ verdict(n_bits, 2000) ++ "\n" ++
    "Secao A - combinadores nos extremos (5 checagens x 2000 sementes): " ++ verdict(n_comb, 2000) ++ "\n\n" ++
    "Inversao 2-Opt (reversao completa do trecho [lo, hi]):\n" ++
    "  perm_reverse_range(0, 7): " ++ rev_demo(0, 7) ++ "\n" ++
    "  perm_reverse_range(1, 5): " ++ rev_demo(1, 5) ++ "\n" ++
    "  perm_reverse_range(2, 3): " ++ rev_demo(2, 3) ++ "\n" ++
    "  perm_reverse_range(4, 4): " ++ rev_demo(4, 4) ++ "\n\n" ++
    "Exemplos com p1 = [0..7] e p2 = [7..0] (semente 42):\n" ++
    "  OX1: " ++ Perm.Perm8.show(Op.cross_perm_ox1(Perm.P8{0,1,2,3,4,5,6,7}, Perm.P8{7,6,5,4,3,2,1,0}, 42)) ++ "\n" ++
    "  PMX: " ++ Perm.Perm8.show(Op.cross_perm_pmx(Perm.P8{0,1,2,3,4,5,6,7}, Perm.P8{7,6,5,4,3,2,1,0}, 42)) ++ "\n"
  )
