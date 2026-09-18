# ================================================================
# BEND 2 GENETIC UTILS - LEIS FORMAIS (LAWS.bend)
# ================================================================
# Declaração das propriedades matemáticas invariantes dos operadores
# genéticos e estruturas da biblioteca (conforme demos/proof_* do Bend).
# ================================================================

import Base
import ./bits.bend as Bits
import ./math.bend as Math
import ./stats.bend as Stats

# LEI 1: Idempotência do Crossover Uniforme
# O cruzamento de dois genomas idênticos sob qualquer máscara produz o próprio genoma:
# para todo a e mask: (a & mask) | (a & ~mask) == a
law crossover_idempotent:
  for +a: U32
  for +m: U32
  {Bits.crossover_uniform(a, a, m) == a : U32}

# LEI 2: Involução da Mutação Pontual
# Aplicar duas vezes consecutivas a mesma mutação pontual reverte o genoma ao estado original:
# (g ^ (1 << b)) ^ (1 << b) == g
law mutation_involution:
  for +g: U32
  for +b: U32
  {Bits.mutate_bit(Bits.mutate_bit(g, b), b) == g : U32}

# LEI 3: Ponto Fixo da Ativação Contínua
# A função de ativação sigmoidal contínua Softsign preserva a origem:
# fast_tanh(0.0) == 0.0
law fast_tanh_zero:
  {Math.fast_tanh({0.0 : F32}) == {0.0 : F32} : F32}

# LEI 4: Conservação de População na Redução de Estatísticas
# A fusão em árvore de duas estatísticas preserva a contagem exata de indivíduos:
# merge_stats(a, b).count == a.count + b.count
law stats_count_conservation:
  for +a: Stats.PopStats
  for +b: Stats.PopStats
  Stats.PopStats{_, _, _, ac} = a
  Stats.PopStats{_, _, _, bc} = b
  Stats.PopStats{_, _, _, mc} = Stats.merge_stats(a, b)
  {mc == (ac + bc : U32) : U32}
