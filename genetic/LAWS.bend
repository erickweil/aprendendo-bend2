# ================================================================
# BEND 2 GENETIC UTILS - LEIS FORMAIS (LAWS.bend)
# ================================================================
# Especificação formal e invariantes matemáticos verificáveis
# da biblioteca evolutiva e do motor genético paralelo em ilhas
# (conforme convenção oficial do Bend 2).
# ================================================================

import Base
import ./utils/stats.bend as Stats
import ./utils/poptree.bend as Tree
import ./utils/island.bend as Island
import ./utils/bits.bend as Bits
import ./utils/perm.bend as Perm
import ./utils/random.bend as R
import ./operators.bend as Op

# ----------------------------------------------------------------
# PARTE 1: LEIS DE REDUÇÃO ESTATÍSTICA (PopStats)
# ----------------------------------------------------------------

# LEI 1: Conservação de População na Fusão de Estatísticas
# A fusão em árvore de duas estatísticas preserva a contagem exata de indivíduos:
# merge_stats(a, b).count == a.count + b.count
law stats_count_conservation:
  for +a: Stats.PopStats
  for +b: Stats.PopStats
  {Stats.PopStats.count(Stats.merge_stats(a, b)) == (Stats.PopStats.count(a) + Stats.PopStats.count(b) : U32) : U32}

# LEI 2: Conservação da Soma de Aptidão na Redução
# A soma total de aptidão acumulada é exatamente aditiva sob merge_stats:
# merge_stats(a, b).sum == a.sum + b.sum
law stats_sum_conservation:
  for +a: Stats.PopStats
  for +b: Stats.PopStats
  {Stats.PopStats.sum(Stats.merge_stats(a, b)) == (Stats.PopStats.sum(a) + Stats.PopStats.sum(b) : U32) : U32}

# LEI 3: Contagem Unitária de Estatística em Folha
# Uma folha individual sempre inicializa a contagem populacional com exatamente 1 indivíduo:
# leaf_stats(v).count == 1
law stats_leaf_count:
  for +v: U32
  {Stats.PopStats.count(Stats.leaf_stats(v)) == 1 : U32}

# LEI 4: Identidade de Extremos em Folha Individual
# Em uma folha individual, a melhor e a pior aptidão coincidem exatamente com o valor do indivíduo:
# leaf_stats(v).best == leaf_stats(v).worst
law stats_leaf_extremes_equal:
  for +v: U32
  {Stats.PopStats.best(Stats.leaf_stats(v)) == Stats.PopStats.worst(Stats.leaf_stats(v)) : U32}

# LEI 5: Preservação do Valor Máximo em Folha Unitária
law stats_leaf_best:
  for +v: U32
  {Stats.PopStats.best(Stats.leaf_stats(v)) == v : U32}

# LEI 6: Preservação do Valor Mínimo em Folha Unitária
law stats_leaf_worst:
  for +v: U32
  {Stats.PopStats.worst(Stats.leaf_stats(v)) == v : U32}

# LEI 7: Preservação da Soma em Folha Unitária
law stats_leaf_sum:
  for +v: U32
  {Stats.PopStats.sum(Stats.leaf_stats(v)) == v : U32}

# ----------------------------------------------------------------
# PARTE 2: LEIS DA ÁRVORE POPULACIONAL (PopTree)
# ----------------------------------------------------------------

# LEI 8: Invariante Estrutural do Elitismo (Preservação do Tamanho da População)
# Injetar um indivíduo de elite na população preserva exatamente o número de indivíduos da árvore:
# tree_size(inject_elite(tree, elite)) == tree_size(tree)
law elite_preserves_size:
  for +tree: Tree.PopTree<U32>
  for +elite: U32
  {Tree.tree_size(U32, Tree.inject_elite(U32, tree, elite)) == Tree.tree_size(U32, tree) : Nat}

# LEI 9: Dimensão da População em Árvore Balanceada
# Uma população gerada a uma profundidade d contém exatamente 2^d indivíduos:
# tree_size(gen_uniform(d, val)) == pow2(d)
law gen_uniform_size:
  for +d: Nat
  for +val: U32
  {Tree.tree_size(U32, Tree.gen_uniform(U32, d, val)) == Tree.pow2(d) : Nat}

# LEI 10: Involução do Espelhamento da População (Involutive Reverse)
# Espelhar uma árvore populacional duas vezes retorna à árvore original exata:
# tree_reverse(tree_reverse(tree)) == tree
law tree_reverse_involutive:
  for +tree: Tree.PopTree<U32>
  {Tree.tree_reverse(U32, Tree.tree_reverse(U32, tree)) == tree : Tree.PopTree<U32>}

# LEI 11: Altura Balanceada da População Uniforme
# Uma árvore uniforme de profundidade d possui exatamente profundidade d:
# tree_depth(gen_uniform(d, val)) == d
law tree_depth_uniform:
  for +d: Nat
  for +val: U32
  {Tree.tree_depth(U32, Tree.gen_uniform(U32, d, val)) == d : Nat}

# ----------------------------------------------------------------
# PARTE 3: LEIS DO MOTOR GENÉTICO PARALELO (Island Model / PGA)
# ----------------------------------------------------------------

# LEI 12: Conservação de Ilhas na Migração do Campeão
# A fase de migração distribui o campeão sem criar ou destruir ilhas ativas:
# island_count(migrate(arch, champion)) == island_count(arch)
law migration_preserves_islands:
  for +arch: Island.Archipelago<U32>
  for +champ: U32
  {Island.island_count(U32, Island.migrate(U32, arch, champ)) == Island.island_count(U32, arch) : Nat}

# LEI 13: Conservação da Capacidade Global na Migração
# A difusão do campeão entre ilhas preserva exatamente o número total de indivíduos no arquipélago:
# total_pop_size(migrate(arch, champion)) == total_pop_size(arch)
law migration_preserves_total_pop:
  for +arch: Island.Archipelago<U32>
  for +champ: U32
  {Island.total_pop_size(U32, Island.migrate(U32, arch, champ)) == Island.total_pop_size(U32, arch) : Nat}

# LEI 14: Topologia Dimensional do Arquipélago
# Um arquipélago bifurcado em profundidade d contém exatamente 2^d ilhas paralelas:
# island_count(gen_archipelago(d, pop_depth, val)) == pow2(d)
law archipelago_dimension:
  for +d: Nat
  for +pop_depth: Nat
  for +val: U32
  {Island.island_count(U32, Island.gen_archipelago(U32, d, pop_depth, val)) == Tree.pow2(d) : Nat}

# LEI 15: Capacidade Populacional da Ilha Individual
# Uma ilha individual gerada com profundidade pop_depth contém exatamente 2^pop_depth indivíduos:
# total_pop_size(SingleIsland{gen_uniform(pop_depth, val)}) == pow2(pop_depth)
law single_island_capacity:
  for +pop_depth: Nat
  for +val: U32
  {Island.total_pop_size(U32, Island.SingleIsland{Tree.gen_uniform(U32, pop_depth, val)}) == Tree.pow2(pop_depth) : Nat}

# ----------------------------------------------------------------
# PARTE 4: LEIS DOS COMBINADORES DE OPERADORES (operators.bend)
# ----------------------------------------------------------------
# Estas leis respondem formalmente à pergunta "os combinadores
# higher-order custam alguma coisa?": elas afirmam que o pipeline
# montado por combinadores é DEFINICIONALMENTE IGUAL ao código
# escrito à mão. Se provadas por reflexividade ({==}), os dois
# lados normalizam para o mesmo termo — a abstração desaparece
# em tempo de compilação, e não apenas "roda igualmente rápido".

# LEI 16: Pipeline de Reprodução Binário = Código Manual
# O `Op.pipe` sobre crossover uniforme + flip de bit é exatamente o
# corpo original escrito à mão do Cenário 1 (One-Max):
#   s1 = step(seed); s2 = step(s1)
#   mutate_bit(crossover_uniform(parent, champ, s1), s2)
law pipe_bits_is_manual_code:
  for +parent: U32
  for +champ: U32
  for +seed: U32
  {Op.pipe(~U32, ~Op.cross_bits_uniform, ~Op.mut_bit_flip32, parent, champ, seed)
   == Bits.mutate_bit(Bits.crossover_uniform(parent, champ, R.step(seed)), R.step(R.step(seed))) : U32}

# LEI 17: Pipeline de Reprodução sobre Permutações = Composição Manual
# O mesmo combinador, instanciado num genoma completamente diferente
# (Perm8), continua sendo pura composição — a propriedade não depende
# da representação do genoma.
# Nota: instanciar esta lei com `cross_perm_ox1` também é verdadeiro, mas
# normalizar o OX1 simbolicamente (8 níveis de recursão sobre uma permutação
# não-concreta) faz o verificador explodir combinatorialmente. A validade do
# OX1 é coberta pelo teste exaustivo em tests/operators_test.bend.
law pipe_perm_is_manual_code:
  for +parent: Perm.Perm8
  for +champ: Perm.Perm8
  for +seed: U32
  {Op.pipe(~Perm.Perm8, ~Op.cross_perm_elite_bias, ~Op.mut_perm_neighbor_swap, parent, champ, seed)
   == Op.mut_perm_neighbor_swap(Op.cross_perm_elite_bias(parent, champ, R.step(seed)), R.step(R.step(seed))) : Perm.Perm8}

# LEI 18: Encadeamento de Mutações = Composição das Duas Mutações
# `chain_mutations` (equivalente do `mutation_combine` original) aplica
# ambos os operadores em sequência com sementes bifurcadas.
law chain_mutations_is_composition:
  for +g: U32
  for +seed: U32
  {Op.chain_mutations(~U32, ~Op.mut_bit_flip32, ~Op.mut_bits_invert_block, g, seed)
   == Op.mut_bits_invert_block(Op.mut_bit_flip32(g, R.split.fst(seed)), R.split.snd(seed)) : U32}

# LEI 19: Despacho Exclusivo de Mutação (ramo verdadeiro)
# Nenhum trabalho do operador descartado é realizado: o `match` sobre
# Bool escolhe um único ramo, e o outro nunca é construído.
law branch_mut_true_selects_first:
  for +g: U32
  for +seed: U32
  {Op.branch_mut(~U32, ~Op.mut_bit_flip32, ~Op.mut_bits_invert_block, True{}, g, seed)
   == Op.mut_bit_flip32(g, seed) : U32}

# LEI 20: Despacho Exclusivo de Mutação (ramo falso)
law branch_mut_false_selects_second:
  for +g: U32
  for +seed: U32
  {Op.branch_mut(~U32, ~Op.mut_bit_flip32, ~Op.mut_bits_invert_block, False{}, g, seed)
   == Op.mut_bits_invert_block(g, seed) : U32}

# LEI 21: Reprodução Clássica de Holland — sem crossover, o filho é o pai 1
# intacto (nenhum alelo do pai 2 vaza para o filho).
law branch_cross_false_clones_parent:
  for +p1: Perm.Perm8
  for +p2: Perm.Perm8
  for +seed: U32
  {Op.branch_cross(~Perm.Perm8, ~Op.cross_perm_ox1, False{}, p1, p2, seed) == p1 : Perm.Perm8}

# LEI 22: Saturação do Order Crossover (OX1)
# Se todos os 8 alelos já foram herdados na fatia do pai 1 (máscara
# saturada = 255), a fase de preenchimento circular é a identidade:
# nenhuma posição do filho é sobrescrita pelo pai 2.
law ox1_fill_saturated_is_identity:
  for +child: Perm.Perm8
  {Op.ox1_fill(8n, Perm.P8{0, 1, 2, 3, 4, 5, 6, 7}, child, 255, 0, 0, 0) == child : Perm.Perm8}
