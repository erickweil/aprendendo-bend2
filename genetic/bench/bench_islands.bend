import Base
import ./../ga.bend as GA
import ./../operators.bend as Op
import ./../utils/perm.bend as Perm
import ./../utils/random.bend as R
import ./bench_perm.bend as BP

# ================================================================
# BENCHMARK: ARQUIPELAGO BEM DIMENSIONADO (64 ILHAS)
# ================================================================
# Mesma carga do bench_perm, mas com 64 ilhas x 64 individuos em vez
# de 8 x 64. O escalonador do Bend entrega cada tarefa a um core uma
# unica vez e nunca a move, entao a escala depende de haver MUITAS
# tarefas longevas — nao de tarefas grandes.
#
# Medido em 4 cores, variando so a contagem de ilhas:
#    4 ilhas -> 1,54x    16 ilhas -> 1,63x
#    8 ilhas -> 1,66x    32 ilhas -> 2,55x    64 ilhas -> 2,8x a 3,4x
#
# Regra pratica: dimensione o arquipelago em ~16x o numero de threads.
# ================================================================

def main() -> IO(Unit):
  +s0 = {12345678 : U32}
  +arch0 = GA.gen_archipelago(~Perm.Perm8, ~BP.init_gene, ~BP.fitness, 6n, s0, 6n)
  +arch_fin = GA.run_archipelago(~Perm.Perm8, ~BP.reproduce, ~BP.fitness, 10n, arch0, R.step(s0), 100n)
  +champ = GA.best_archipelago(Perm.Perm8, arch_fin)
  IO.print("bench_islands | distancia campea: " ++ U32.show(BP.tour_distance(GA.Ind.gene(Perm.Perm8, champ))) ++ "\n")
