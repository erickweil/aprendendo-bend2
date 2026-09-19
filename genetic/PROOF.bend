# ================================================================
# BEND 2 GENETIC UTILS - PROVAS FORMAIS (PROOF.bend)
# ================================================================
# Demonstração construtiva das 13 leis de LAWS.bend.
# Cada lei em LAWS.bend é provada através de reflexividade ({==}),
# indução estrutural, indução matemática e reescritas (%e : P).
# ================================================================

import Base
import ./../utils/random.bend as R
import ./utils/poptree.bend as Tree
import ./stats.bend as Stats
import ./operators.bend as Op
import ./mutations.bend as M
import ./ga.bend as GA
import ./utils/genes.bend as Genes
import ./LAWS.bend as Laws

# ----------------------------------------------------------------
# PROVAS DA PARTE 1: REDUÇÃO ESTATÍSTICA (PopStats)
# ----------------------------------------------------------------

# PROVA DA LEI 1: Conservação de População
def Laws.stats_count_conservation(a, b):
  match a b:
    case Stats.PopStats{ab, aw, as, ac} Stats.PopStats{bb, bw, bs, bc}:
      {==}

# PROVA DA LEI 2: Conservação da Soma de Aptidão
def Laws.stats_sum_conservation(a, b):
  match a b:
    case Stats.PopStats{ab, aw, as, ac} Stats.PopStats{bb, bw, bs, bc}:
      {==}

# PROVA DA LEI 3: Contagem Unitária em Folha
def Laws.stats_leaf_count(v):
  {==}

# PROVA DA LEI 4: Identidade de Extremos em Folha Individual
def Laws.stats_leaf_extremes_equal(v):
  {==}

# PROVA DA LEI 5: Preservação do Valor Máximo em Folha Unitária
def Laws.stats_leaf_best(v):
  {==}

# PROVA DA LEI 6: Preservação do Valor Mínimo em Folha Unitária
def Laws.stats_leaf_worst(v):
  {==}

# PROVA DA LEI 7: Preservação da Soma em Folha Unitária
def Laws.stats_leaf_sum(v):
  {==}

# ----------------------------------------------------------------
# PROVAS DA PARTE 2: COMBINADORES E DESPACHO
# ----------------------------------------------------------------
# Todas por reflexividade pura: os templates são substituídos em tempo de
# compilação, então não há closure nem despacho dinâmico — os dois lados são
# literalmente o mesmo termo.

def Laws.combine_is_manual_code(l, n, rate, seed):
  {==}

def Laws.cross_maybe_false_clones(ctx, a, b, seed):
  {==}

def Laws.cross_maybe_true_crosses(ctx, a, b, seed):
  {==}

def Laws.mutate_maybe_false_keeps(ctx, g, rate, seed):
  {==}

# ----------------------------------------------------------------
# PROVAS DA PARTE 3: MOTOR REAL (ga.bend)
# ----------------------------------------------------------------

# PROVA DA LEI 12: Conservação de Ilhas na Migração em Anel (Indução Estrutural)
def Laws.arch_migration_preserves_islands(arch, bests, k, i, size):
  match arch:
    case GA.SingleIsland{isl}:
      match isl:
        case GA.Island{gen, bf, bg, ss, sf, g}:
          {==}
    case GA.ArchBranch{left, right}:
      %Laws.arch_migration_preserves_islands(left, bests, k, i, U32.shrn(size, 1n)) : {Nat.add(GA.arch_island_count(U32, GA.migrate_ring(U32, left, bests, k, i, U32.shrn(size, 1n))), GA.arch_island_count(U32, GA.migrate_ring(U32, right, bests, k, (i + U32.shrn(size, 1n) : U32), U32.shrn(size, 1n)))) == Nat.add(_, GA.arch_island_count(U32, right)) : Nat}
      %Laws.arch_migration_preserves_islands(right, bests, k, (i + U32.shrn(size, 1n) : U32), U32.shrn(size, 1n)) : {Nat.add(GA.arch_island_count(U32, GA.migrate_ring(U32, left, bests, k, i, U32.shrn(size, 1n))), GA.arch_island_count(U32, GA.migrate_ring(U32, right, bests, k, (i + U32.shrn(size, 1n) : U32), U32.shrn(size, 1n)))) == Nat.add(GA.arch_island_count(U32, GA.migrate_ring(U32, left, bests, k, i, U32.shrn(size, 1n))), _) : Nat}
      {==}

# PROVA DA LEI 13: abrir os dois `Gen` basta — `Gen.pop` projeta o nó sem
# depender da comparação de aptidões.
def Laws.merge_gen_size(gl, gr):
  match gl gr:
    case GA.Gen{lp, lf, lg, lh} GA.Gen{rp, rf, rg, rh}:
      {==}

# ----------------------------------------------------------------
# PROVAS DA PARTE 4: VETOR DE GENES
# ----------------------------------------------------------------

# PROVA DA LEI 14: indução estrutural na lista.
# Nos três primeiros casos os dois lados já normalizam para o mesmo termo;
# no último, a hipótese de indução fecha a cauda dentro do `Con`.
def Laws.take_drop_split(l, s, k):
  match l s:
    case Nil{} True{}:
      {==}
    case Nil{} False{}:
      {==}
    case Con{h, t} True{}:
      {==}
    case Con{h, t} False{}:
      %Laws.take_drop_split(t, U32.is_eq(k, 1), U32.sub(k, 1)) : {Con{h, Genes.append(U32, Genes.take.go(U32, t, U32.is_eq(k, 1), U32.sub(k, 1)), Genes.drop.go(U32, t, U32.is_eq(k, 1), U32.sub(k, 1)))} == Con{h, _} : List<&2, U32>}
      {==}
