import Base
import ./../../utils/random.bend as R
import ./../../utils/io.bend as IOHelper
import ./../ga.bend as GA
import ./../utils/genes.bend as V
import ./../operators.bend as Op
import ./../mutations.bend as M

# ================================================================
# CENÁRIO 1: BIT MAXING (ONE-MAX) (onemax.bend)
# ================================================================
# Problema: encontrar uma lista de N booleanos com todos em `True`.
# Porte direto do `problem_onemax.rs`:
#
# Genoma...: List<&2, Bool> com N genes (qualquer N: 100, 1000, 1 milhão)
# Aptidão..: número de genes em True (máximo N)
# Cruzam...: 1 ponto, com probabilidade 90%
# Mutação..: com probabilidade 90% por indivíduo, cada gene é invertido com
#            probabilidade 1/N (mutation_replace)
# Seleção..: torneio de 5 dentro de cada ilha, elitismo estrito, migração do
#            campeão global a cada época
#
# Uso: bend onemax.bend [N] [GERAÇÕES] [ILHAS] [POP] [SEMENTE]
#      2^ILHAS ilhas com 2^POP indivíduos cada (padrão: 8 x 8 = 64)
# ================================================================

# ----------------------------------------------------------------
# PROBLEMA (os quatro métodos do GAProblem; o contexto é N)
# ----------------------------------------------------------------

def random_bools(k: Nat, +seed: U32) -> List<&2, Bool>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      Con{R.hit(seed, R.per(1, 2)), random_bools(p, R.step(seed))}

def init_gene(n: U32, seed: U32) -> List<&2, Bool>:
  random_bools(U32.to_nat(n), R.step(seed))

def count_true(l: List<&2, Bool>, +acc: U32) -> U32:
  match l:
    case Nil{}:
      acc
    case Con{h, t}:
      count_true(t, (acc + Bool.to_u32(h) : U32))

def fitness(n: U32, gene: List<&2, Bool>) -> U32:
  count_true(gene, 0)

def cross(n: U32, a: List<&2, Bool>, b: List<&2, Bool>, seed: U32) -> List<&2, Bool>:
  Op.cross_1point(Bool, a, b, n, seed)

def b2u(b: Bool) -> U32:
  Bool.to_u32(b)

def hash(n: U32, g: List<&2, Bool>) -> U32:
  V.hash_list(~Bool, ~b2u, g, 7)

def flip(b: Bool, s: U32) -> Bool:
  Bool.not(b)

def mutate(n: U32, g: List<&2, Bool>, rate: U32, seed: U32) -> List<&2, Bool>:
  M.mut_replace(~Bool, ~flip, g, n, rate, seed)

# ----------------------------------------------------------------
# EXECUÇÃO
# ----------------------------------------------------------------
# A população é um ARQUIPÉLAGO: 2^ILHAS ilhas de 2^POP indivíduos, com
# torneio dentro da ilha e migração do campeão global entre épocas — o
# desenho que o fork-join do Bend paraleliza. Evolui em 10 épocas, relatando
# o melhor ao fim de cada uma, e para cedo ao atingir N/N.

def best(arch: GA.ArchTree<List<&2, Bool>>) -> U32:
  GA.Ind.fit(List<&2, Bool>, GA.best_archipelago(List<&2, Bool>, arch))

def report(k: Nat, arch: GA.ArchTree<List<&2, Bool>>, +e: Nat, +done: U32,
           +n: U32, +cfg: GA.Config, +seed: U32) -> IO(Unit):
  match k:
    case 0n:
      +b = best(arch)
      IO.print(
        "Final (até a geração " ++ U32.show(done) ++ "): " ++ U32.show(b) ++ " / " ++ U32.show(n) ++ "\n" ++
        "Solução ótima atingida? " ++ Bool.show(U32.is_eq(b, n)))
    case 1n+p:
      +next = GA.run_archipelago(~U32, ~List<&2, Bool>, ~init_gene, ~fitness, ~hash, ~cross, ~mutate, 1n, arch, e, n, cfg, seed)
      +now = (done + U32.from_nat(e) : U32)
      IO.bind(Unit, Unit,
        IO.print("  geração " ++ U32.show(now) ++ ": " ++ U32.show(best(next))),
        u => report(p, next, e, now, n, cfg, R.split.trd(seed)))

def run(args: List<String>) -> IO(Unit):
  +nums = IOHelper.numbers(args)
  +n = U32.max(IOHelper.num_at(nums, 0n, 100), 2)
  +gens = U32.max(IOHelper.num_at(nums, 1n, 300), 10)
  +isl = IOHelper.num_at(nums, 2n, 3)
  +pop = IOHelper.num_at(nums, 3n, 3)
  +s0 = IOHelper.num_at(nums, 4n, 12345678)
  # Mesma configuração do teste do Rust: 90% / 90% / 1/N, torneio de 5
  +cfg = GA.config(R.per(9, 10), R.per(9, 10), R.per(1, n), 5, 0, n, pop, 0)
  +a0 = GA.gen_archipelago(~U32, ~List<&2, Bool>, ~init_gene, ~fitness, U32.to_nat(isl), n, cfg, s0)
  IO.bind(Unit, Unit,
    IO.print(
      "=== CENÁRIO 1: BIT MAXING (ONE-MAX) ===\n" ++
      "Genes: " ++ U32.show(n) ++
      " | ilhas: " ++ U32.show(U32.shln(1, U32.to_nat(isl))) ++
      " x " ++ U32.show(U32.shln(1, U32.to_nat(pop))) ++ " indivíduos" ++
      " | gerações: " ++ U32.show(gens) ++ "\n" ++
      "  geração 0: " ++ U32.show(best(a0))),
    u => report(10n, a0, U32.to_nat(U32.div(gens, 10)), 0, n, cfg, R.step(s0)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
