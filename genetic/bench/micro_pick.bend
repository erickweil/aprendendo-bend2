import Base
import ./../utils/perm.bend as Perm
import ./../utils/random.bend as R

# ================================================================
# MICROBENCHMARK: Bool.pick vs despacho por match
# ================================================================
# Hipotese: Bool.pick(T, c, caro_a, caro_b) avalia OS DOIS ramos,
# porque sao argumentos de uma chamada comum. Um `match` sobre o
# Bool constroi so o ramo escolhido.
# ================================================================

# A) Bool.pick: o swap descartado ainda e' construido
def loop_pick(n: Nat, +p: Perm.Perm8, +s: U32) -> Perm.Perm8:
  match n:
    case 0n:
      p
    case 1n+q:
      +s = s
      +p = p
      +s1 = R.step(s)
      +s1 = s1
      +r = Bool.pick(Perm.Perm8, U32.is_lt(U32.mod(s, 100), 50),
                     Perm.Perm8.swap(p, U32.mod(s, 8), U32.mod(s1, 8)), p)
      loop_pick(q, r, s1)

# B) match sobre o Bool: so o ramo escolhido aloca
def branch_swap(cond: Bool, p: Perm.Perm8, +i: U32, +j: U32) -> Perm.Perm8:
  match cond:
    case True{}:
      Perm.Perm8.swap(p, i, j)
    case False{}:
      p

def loop_match(n: Nat, +p: Perm.Perm8, +s: U32) -> Perm.Perm8:
  match n:
    case 0n:
      p
    case 1n+q:
      +s = s
      +s1 = R.step(s)
      +s1 = s1
      +r = branch_swap(U32.is_lt(U32.mod(s, 100), 50), p, U32.mod(s, 8), U32.mod(s1, 8))
      loop_match(q, r, s1)
