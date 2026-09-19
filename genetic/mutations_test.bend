import Base
import ./../utils/random.bend as R
import ./utils/genes.bend as V
import ./mutations.bend as M

# ================================================================
# TESTE DAS MUTAÇÕES (mutations.bend)
# ================================================================

def eq(a: List<&2, U32>, b: List<&2, U32>) -> Bool:
  match a b:
    case Nil{} Nil{}:
      True{}
    case Nil{} Con{y, ys}:
      False{}
    case Con{x, xs} Nil{}:
      False{}
    case Con{x, xs} Con{y, ys}:
      Bool.and(U32.is_eq(x, y), eq(xs, ys))

def ok(b: Bool) -> U32:
  Bool.to_u32(b)

def verdict(+name: String, +got: U32, +want: U32) -> String:
  "  " ++ Bool.pick(String, U32.is_eq(got, want), "[OK]     ", "[FALHOU] ") ++
  name ++ ": " ++ U32.show(got) ++ " / " ++ U32.show(want) ++ "\n"

def NEVER() -> U32:
  0

def ALWAYS() -> U32:
  R.per(1, 1)

# --- genes Bool: mut_replace com inversão ---
def flip(b: Bool, s: U32) -> Bool:
  Bool.not(b)

def falses(k: Nat) -> List<&2, Bool>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      Con{False{}, falses(p)}

def count_true(l: List<&2, Bool>, +acc: U32) -> U32:
  match l:
    case Nil{}:
      acc
    case Con{h, t}:
      count_true(t, (acc + Bool.to_u32(h) : U32))

def flipped(+rate: U32, +seed: U32) -> U32:
  count_true(M.mut_replace(~Bool, ~flip, falses(100000n), 100000, rate, seed), 0)

# --- permutações: as trocas preservam o multiconjunto ---
def check_perm(+n: U32, +s: U32) -> U32:
  +p = V.perm_random(n, s)
  (ok(V.is_permutation(M.mut_swap(~U32, p, n, R.per(1, 2), s), n)) +
   ok(V.is_permutation(M.mut_swap(~U32, p, n, R.per(1, n), s), n)) +
   ok(V.is_permutation(M.mut_neighbor(~U32, p, n, R.per(1, 2), s), n)) +
   ok(V.is_permutation(M.mut_neighbor(~U32, p, n, R.per(1, n), s), n)) : U32)

def sweep_perm(k: Nat, +n: U32, +s: U32, +acc: U32) -> U32:
  match k:
    case 0n:
      acc
    case 1n+p:
      sweep_perm(p, n, R.step(s), (acc + check_perm(n, s) : U32))

# --- identidades nos extremos das taxas ---
def check_identity(+n: U32, +s: U32) -> U32:
  +p = V.perm_random(n, s)
  (ok(eq(M.mut_swap(~U32, p, n, NEVER(), s), p)) +
   ok(eq(M.mut_neighbor(~U32, p, n, NEVER(), s), p)) +
   ok(Bool.not(eq(M.mut_swap(~U32, p, n, ALWAYS(), s), p))) : U32)

def sweep_identity(k: Nat, +n: U32, +s: U32, +acc: U32) -> U32:
  match k:
    case 0n:
      acc
    case 1n+p:
      sweep_identity(p, n, R.step(s), (acc + check_identity(n, s) : U32))

# --- combine (mutation_combine) ---
def flip_n(l: List<&2, Bool>, n: U32, rate: U32, seed: U32) -> List<&2, Bool>:
  M.mut_replace(~Bool, ~flip, l, n, rate, seed)

# Duas inversões com metade da taxa cada: o total esperado é o de uma taxa só
def combined_flips(+rate: U32, +seed: U32) -> U32:
  count_true(M.combine(~Bool, ~flip_n, ~flip_n, {0.5 : F32}, {0.5 : F32}, falses(100000n), 100000, rate, seed), 0)

def check_comb(+s: U32) -> U32:
  +p = V.perm_random(50, s)
  (ok(eq(M.combine(~U32, ~M.mut_swap(~U32), ~M.mut_neighbor(~U32), {0.5 : F32}, {0.5 : F32}, p, 50, NEVER(), s), p)) +
   ok(V.is_permutation(M.combine(~U32, ~M.mut_swap(~U32), ~M.mut_neighbor(~U32), {0.5 : F32}, {0.5 : F32}, p, 50, R.per(1, 5), s), 50)) : U32)

def sweep_comb(k: Nat, +s: U32, +acc: U32) -> U32:
  match k:
    case 0n:
      acc
    case 1n+p:
      sweep_comb(p, R.split.trd(s), (acc + check_comb(s) : U32))

# --- parceiros de troca: vizinho é pos±1 (circular), aleatório nunca é pos ---
def check_partner(+s: U32) -> U32:
  +pos = R.range(s, 10)
  +nb = M.neighbor_partner(pos, 10, s)
  (ok(Bool.or(U32.is_eq(nb, U32.mod(U32.inc(pos), 10)), U32.is_eq(nb, U32.mod((pos + 9 : U32), 10)))) +
   ok(U32.is_ne(M.random_partner(pos, 10, s), pos)) : U32)

def sweep_partner(k: Nat, +s: U32, +acc: U32) -> U32:
  match k:
    case 0n:
      acc
    case 1n+p:
      sweep_partner(p, R.split.trd(s), (acc + check_partner(s) : U32))

def between(+x: U32, +lo: U32, +hi: U32) -> U32:
  ok(Bool.and(U32.is_ge(x, lo), U32.is_le(x, hi)))

def main() -> IO(Unit):
  IO.print(
    "=== TESTE DAS MUTAÇÕES (mutations.bend) ===\n" ++
    verdict("mut_replace 0% / 100% em 100000 genes Bool", (ok(U32.is_zero(flipped(NEVER(), 5))) + ok(U32.is_eq(flipped(ALWAYS(), 5), 100000)) : U32), 2) ++
    verdict("mut_replace 50% inverte entre 49% e 51%", between(flipped(R.per(1, 2), 5), 49000, 51000), 1) ++
    verdict("mut_replace 1/1000 inverte entre 70 e 130", between(flipped(R.per(1, 1000), 9), 70, 130), 1) ++
    verdict("mut_replace 1/10000 inverte entre 2 e 20", between(flipped(R.per(1, 10000), 11), 2, 20), 1) ++
    verdict("trocas preservam a permutação, n = 12, 1000 sementes x 4", sweep_perm(1000n, 12, 777, 0), 4000) ++
    verdict("trocas preservam a permutação, n = 100000, 5 sementes x 4", sweep_perm(5n, 100000, 888, 0), 20) ++
    verdict("taxa 0 é identidade, taxa 100% altera, n = 1000, 200 sementes x 3", sweep_identity(200n, 1000, 999, 0), 600) ++
    verdict("combine: taxa 0 é identidade e preserva permutação, 500 x 2", sweep_comb(500n, 1234, 0), 1000) ++
    verdict("combine 0,5 + 0,5 de 1/1000 inverte entre 70 e 130", between(combined_flips(R.per(1, 1000), 21), 70, 130), 1) ++
    verdict("parceiros: vizinho ±1 circular, aleatório nunca a própria posição, 10000 x 2", sweep_partner(10000n, 5, 0), 20000)
  )
