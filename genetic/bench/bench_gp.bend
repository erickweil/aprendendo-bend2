import Base
import ./../ga.bend as GA
import ./../utils/random.bend as R
import ./../src/scenario10_gp.bend as GP

# ================================================================
# BENCHMARK: PROGRAMACAO GENETICA (ADTs EM ARVORE)
# ================================================================
# 4 ilhas x 64 individuos x 10 epocas x 150 geracoes.
# Carga dominada por pattern-matching e construcao de nos de AST,
# o perfil mais pesado segundo o bench symreg do repo oficial.
# ================================================================

def main() -> IO(Unit):
  +s0 = {24680135 : U32}
  +arch0 = GA.gen_archipelago(~GP.Expr, ~GP.init_expr, ~GP.fitness, 2n, s0, 6n)
  +arch_fin = GA.run_archipelago(~GP.Expr, ~GP.reproduce, ~GP.fitness, 10n, arch0, R.step(s0), 150n)
  +champ = GA.best_archipelago(GP.Expr, arch_fin)
  IO.print("bench_gp | melhor aptidao: " ++ U32.show(GA.Ind.fit(GP.Expr, champ)) ++ "\n")
