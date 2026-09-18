# ================================================================
# BEND 2 GENETIC UTILS - PROVAS FORMAIS (PROOF.bend)
# ================================================================
# Demonstração matemática construtiva das 15 Leis do Motor Genético.
# Cada lei em LAWS.bend é provada através de reflexividade ({==}),
# indução estrutural, indução matemática e reescritas (%e : P).
# ================================================================

import Base
import ./stats.bend as Stats
import ./poptree.bend as Tree
import ./island.bend as Island
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
# PROVAS DA PARTE 2: ÁRVORE POPULACIONAL (PopTree)
# ----------------------------------------------------------------

# PROVA DA LEI 8: Invariante Estrutural do Elitismo (Indução Estrutural)
def Laws.elite_preserves_size(tree, elite):
  match tree:
    case Tree.Leaf{_}:
      {==}
    case Tree.Node{left, right}:
      %Laws.elite_preserves_size(left, elite) : {Nat.add(Tree.tree_size(U32, Tree.inject_elite(U32, left, elite)), Tree.tree_size(U32, right)) == Nat.add(_, Tree.tree_size(U32, right)) : Nat}
      {==}

# PROVA DA LEI 9: Dimensão da População em Árvore Balanceada (Indução Matemática)
def Laws.gen_uniform_size(d, val):
  match d:
    case 0n:
      {==}
    case 1n++p:
      %Laws.gen_uniform_size(p, val) : {Nat.add(Tree.tree_size(U32, Tree.gen_uniform(U32, p, val)), Tree.tree_size(U32, Tree.gen_uniform(U32, p, val))) == Nat.add(Tree.pow2(p), _) : Nat}
      %Laws.gen_uniform_size(p, val) : {Nat.add(Tree.tree_size(U32, Tree.gen_uniform(U32, p, val)), Tree.tree_size(U32, Tree.gen_uniform(U32, p, val))) == Nat.add(_, Tree.tree_size(U32, Tree.gen_uniform(U32, p, val))) : Nat}
      {==}

# PROVA DA LEI 10: Involução do Espelhamento da População (Indução Estrutural)
def Laws.tree_reverse_involutive(tree):
  match tree:
    case Tree.Leaf{val}:
      {==}
    case Tree.Node{left, right}:
      %Laws.tree_reverse_involutive(left) : {Tree.Node{Tree.tree_reverse(U32, Tree.tree_reverse(U32, left)), Tree.tree_reverse(U32, Tree.tree_reverse(U32, right))} == Tree.Node{_, right} : Tree.PopTree<U32>}
      %Laws.tree_reverse_involutive(right) : {Tree.Node{Tree.tree_reverse(U32, Tree.tree_reverse(U32, left)), Tree.tree_reverse(U32, Tree.tree_reverse(U32, right))} == Tree.Node{Tree.tree_reverse(U32, Tree.tree_reverse(U32, left)), _} : Tree.PopTree<U32>}
      {==}

# PROVA DA LEI 11: Altura Balanceada da População Uniforme (Indução Matemática)
def Laws.tree_depth_uniform(d, val):
  match d:
    case 0n:
      {==}
    case 1n++p:
      %Laws.tree_depth_uniform(p, val) : {1n + Tree.tree_depth(U32, Tree.gen_uniform(U32, p, val)) == 1n + _ : Nat}
      {==}

# ----------------------------------------------------------------
# PROVAS DA PARTE 3: MOTOR GENÉTICO PARALELO (Island Model / PGA)
# ----------------------------------------------------------------

# PROVA DA LEI 12: Conservação de Ilhas na Migração do Campeão (Indução Estrutural)
def Laws.migration_preserves_islands(arch, champ):
  match arch:
    case Island.SingleIsland{tree}:
      {==}
    case Island.ArchBranch{left, right}:
      %Laws.migration_preserves_islands(left, champ) : {Nat.add(Island.island_count(U32, Island.migrate(U32, left, champ)), Island.island_count(U32, Island.migrate(U32, right, champ))) == Nat.add(_, Island.island_count(U32, right)) : Nat}
      %Laws.migration_preserves_islands(right, champ) : {Nat.add(Island.island_count(U32, Island.migrate(U32, left, champ)), Island.island_count(U32, Island.migrate(U32, right, champ))) == Nat.add(Island.island_count(U32, Island.migrate(U32, left, champ)), _) : Nat}
      {==}

# PROVA DA LEI 13: Conservação da Capacidade Global na Migração (Composição Modular)
def Laws.migration_preserves_total_pop(arch, champ):
  match arch:
    case Island.SingleIsland{tree}:
      %Laws.elite_preserves_size(tree, champ) : {Tree.tree_size(U32, Tree.inject_elite(U32, tree, champ)) == _ : Nat}
      {==}
    case Island.ArchBranch{left, right}:
      %Laws.migration_preserves_total_pop(left, champ) : {Nat.add(Island.total_pop_size(U32, Island.migrate(U32, left, champ)), Island.total_pop_size(U32, Island.migrate(U32, right, champ))) == Nat.add(_, Island.total_pop_size(U32, right)) : Nat}
      %Laws.migration_preserves_total_pop(right, champ) : {Nat.add(Island.total_pop_size(U32, Island.migrate(U32, left, champ)), Island.total_pop_size(U32, Island.migrate(U32, right, champ))) == Nat.add(Island.total_pop_size(U32, Island.migrate(U32, left, champ)), _) : Nat}
      {==}

# PROVA DA LEI 14: Topologia Dimensional do Arquipélago (Indução Matemática)
def Laws.archipelago_dimension(d, pop_depth, val):
  match d:
    case 0n:
      {==}
    case 1n++p:
      %Laws.archipelago_dimension(p, pop_depth, val) : {Nat.add(Island.island_count(U32, Island.gen_archipelago(U32, p, pop_depth, val)), Island.island_count(U32, Island.gen_archipelago(U32, p, pop_depth, val))) == Nat.add(Tree.pow2(p), _) : Nat}
      %Laws.archipelago_dimension(p, pop_depth, val) : {Nat.add(Island.island_count(U32, Island.gen_archipelago(U32, p, pop_depth, val)), Island.island_count(U32, Island.gen_archipelago(U32, p, pop_depth, val))) == Nat.add(_, Island.island_count(U32, Island.gen_archipelago(U32, p, pop_depth, val))) : Nat}
      {==}

# PROVA DA LEI 15: Capacidade Populacional da Ilha Individual
def Laws.single_island_capacity(pop_depth, val):
  Laws.gen_uniform_size(pop_depth, val)
