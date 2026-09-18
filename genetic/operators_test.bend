import Base
import ./../utils/random.bend as R
import ./utils/bits.bend as B
import operators.bend as Op

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

def verdict(+got: U32, +want: U32) -> String:
  U32.show(got) ++ " / " ++ U32.show(want) ++
  Bool.pick(String, U32.is_eq(got, want), "  [OK]", "  [FALHOU]")

def main() -> IO(Unit):
  +n_bits = sweep_bits(2000n, 77777777, 0)
  +n_comb = sweep_comb(2000n, 13572468, 0)
  IO.print(
    "=== TESTE DA BIBLIOTECA DE OPERADORES (operators.bend) ===\n\n" ++
    "Secao B - invariantes binarios (7 checagens x 2000 sementes): " ++ verdict(n_bits, 2000) ++ "\n" ++
    "Secao A - combinadores nos extremos (5 checagens x 2000 sementes): " ++ verdict(n_comb, 2000) ++ "\n\n"
  )
