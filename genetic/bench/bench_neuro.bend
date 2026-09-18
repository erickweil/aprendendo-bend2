import Base
import ./../ga.bend as GA
import ./../utils/random.bend as R
import ./../src/scenario15_neuroevolution.bend as NE

# ================================================================
# BENCHMARK: NEUROEVOLUCAO (COMPUTACAO DENSA, POUCA ALOCACAO)
# ================================================================
# 4 ilhas x 32 redes x 10 epocas x 40 geracoes. Cada avaliacao de
# aptidao roda 2 simulacoes fisicas de 100 passos em F32 — centenas de
# operacoes de ponto flutuante em registradores por individuo, contra
# uma unica alocacao de Policy.
#
# E' o extremo oposto do bench_gp na razao computacao/alocacao.
# ================================================================

def main() -> IO(Unit):
  +s0 = {987654321 : U32}
  +arch0 = GA.gen_archipelago(~NE.Policy, ~NE.init_policy, ~NE.fitness, 2n, s0, 5n)
  +arch_fin = GA.run_archipelago(~NE.Policy, ~NE.reproduce, ~NE.fitness, 10n, arch0, R.step(s0), 40n)
  +champ = GA.best_archipelago(NE.Policy, arch_fin)
  IO.print("bench_neuro | sobrevivencia: " ++ U32.show(GA.Ind.fit(NE.Policy, champ)) ++ "/200\n")
