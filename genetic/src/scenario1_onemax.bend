import Base
import ./../ga.bend as GA
import ./../utils/bits.bend as Bits
import ./../utils/random.bend as R

# ================================================================
# CENÁRIO 1: BIT MAXING (ONE-MAX) COM MOTOR GENÉTICO GENÉRICO
# ================================================================
# Problema: Encontrar um número de 32 bits com todos os bits ligados (32).
# Toda a lógica genérica (árvore, elitismo, estatísticas, fork-join)
# é delegada para o motor ga.bend e utilitários.
# ================================================================

# Inicialização aleatória do genoma de 32 bits
def init_gene(seed: U32) -> U32:
  R.step(seed)

# Função de Aptidão (Fitness): contar bits '1' via SWAR O(1)
def fitness(gene: U32) -> U32:
  Bits.popcount(gene)

# Operador de Reprodução: Crossover Uniforme + Mutação Pontual
def reproduce(parent: U32, champ: U32, seed: U32) -> U32:
  +s1 = R.step(seed)
  +s2 = R.step(s1)
  +child = Bits.crossover_uniform(parent, champ, s1)
  Bits.mutate_bit(child, s2)

def main() -> IO(Unit):
  +s0 = {12345678 : U32}
  # População inicial: 32 indivíduos (árvore de profundidade 5)
  +pop0 = GA.gen_population(~U32, ~init_gene, ~fitness, 5n, s0)
  +best0 = GA.best_ind(U32, pop0)
  +f0 = GA.Ind.fit(U32, best0)

  # Evolução por 25 gerações com elitismo no motor genérico ga.bend
  +pop_fin = GA.run_generations(~U32, ~reproduce, ~fitness, 25n, pop0, R.step(s0))
  +best_fin = GA.best_ind(U32, pop_fin)
  +f_fin = GA.Ind.fit(U32, best_fin)
  +g_fin = GA.Ind.gene(U32, best_fin)

  IO.print(
    "=== CENÁRIO 1: BIT MAXING (ONE-MAX) ===\n" ++
    "População: 32 indivíduos (árvore binária profundidade 5)\n" ++
    "Geração 0 - Melhor Fitness: " ++ U32.show(f0) ++ " / 32 bits\n" ++
    "Geração 25 - Melhor Fitness: " ++ U32.show(f_fin) ++ " / 32 bits\n" ++
    "Gene final (U32): " ++ U32.show(g_fin) ++ "\n" ++
    "Solução Ótima Atingida? " ++ Bool.show(U32.is_eq(f_fin, 32)) ++ "\n"
  )
