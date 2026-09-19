import Base

# ================================================================
# BEND 2 GENETIC UTILS - STATS (Estatísticas e Métricas de População)
# ================================================================
# Permite computação em O(log N) de estatísticas agregadas da população
# através de redução funcional concorrente na árvore de indivíduos.
# ================================================================

type PopStats is Data:
  PopStats{best: U32, worst: U32, sum: U32, count: U32}

def make_stats(+best: U32, +worst: U32, +sum: U32, +count: U32) -> PopStats:
  PopStats{best, worst, sum, count}

def leaf_stats(+val: U32) -> PopStats:
  make_stats(val, val, val, 1)

def merge_stats(+a: PopStats, +b: PopStats) -> PopStats:
  PopStats{ab, aw, as, ac} = a
  PopStats{bb, bw, bs, bc} = b
  +best = U32.max(ab, bb)
  +worst = U32.min(aw, bw)
  +sum = (as + bs : U32)
  +count = (ac + bc : U32)
  make_stats(best, worst, sum, count)

# Média protegida contra população vazia (count == 0)
def mean_of(+sum: U32, +count: U32) -> U32:
  Bool.pick(U32, U32.is_eq(count, 0), 0, (sum / count : U32))

def PopStats.mean(s: PopStats) -> U32:
  PopStats{_, _, sum, count} = s
  mean_of(sum, count)

def PopStats.count(s: PopStats) -> U32:
  PopStats{_, _, _, c} = s
  c

def PopStats.sum(s: PopStats) -> U32:
  PopStats{_, _, sum, _} = s
  sum

def PopStats.best(s: PopStats) -> U32:
  PopStats{b, _, _, _} = s
  b

def PopStats.worst(s: PopStats) -> U32:
  PopStats{_, w, _, _} = s
  w

def PopStats.spread(s: PopStats) -> U32:
  PopStats{best, worst, _, _} = s
  (best - worst : U32)

def PopStats.show(s: PopStats) -> String:
  PopStats{best, worst, sum, +count} = s
  +mean_val = mean_of(sum, count)
  "[Melhor: " ++ U32.show(best) ++ " | Pior: " ++ U32.show(worst) ++ " | Média: " ++ U32.show(mean_val) ++ " | N: " ++ U32.show(count) ++ "]"
