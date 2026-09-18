import Base
import ./../utils/perm.bend as Perm
import ./../utils/random.bend as R

# ================================================================
# MICROBENCHMARK: REPRESENTACAO DE PERMUTACAO
# ================================================================
# A) Perm8 como registro de 8 campos (representacao atual)
# B) Permutacao empacotada em U32 (3 bits por elemento, 24 bits)
# Mede o custo de swap + leitura em um laco apertado.
# ================================================================

# ---------- A: registro de 8 campos ----------
def loop_record(n: Nat, +p: Perm.Perm8, +s: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+q:
      +s = s
      +s1 = R.step(s)
      +s1 = s1
      +p2 = Perm.Perm8.swap(p, U32.mod(s, 8), U32.mod(s1, 8))
      +p2 = p2
      loop_record(q, p2, s1, (acc + Perm.Perm8.get(p2, U32.mod(s1, 8)) : U32))

# ---------- B: empacotado em U32 (3 bits por elemento) ----------
def pk_get(+p: U32, +i: U32) -> U32:
  U32.and(U32.shrn(p, U32.to_nat(U32.mul(i, 3))), 7)

def pk_set(+p: U32, +i: U32, +v: U32) -> U32:
  +sh = U32.to_nat(U32.mul(i, 3))
  +sh = sh
  U32.or(U32.and(p, U32.not(U32.shln(7, sh))), U32.shln(v, sh))

def pk_swap(+p: U32, +i: U32, +j: U32) -> U32:
  +p = p
  +i = i
  +j = j
  +vi = pk_get(p, i)
  +vj = pk_get(p, j)
  pk_set(pk_set(p, i, vj), j, vi)

def loop_packed(n: Nat, +p: U32, +s: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+q:
      +s = s
      +s1 = R.step(s)
      +s1 = s1
      +p2 = pk_swap(p, U32.mod(s, 8), U32.mod(s1, 8))
      +p2 = p2
      loop_packed(q, p2, s1, (acc + pk_get(p2, U32.mod(s1, 8)) : U32))
