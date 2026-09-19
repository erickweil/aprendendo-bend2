# ================================================================
# BEND 2 GENETIC UTILS - LEIS FORMAIS (LAWS.bend)
# ================================================================
# Especificação formal e invariantes matemáticos verificáveis
# da biblioteca evolutiva e do motor genético paralelo em ilhas
# (conforme convenção oficial do Bend 2).
# ================================================================

import Base
import ./../utils/random.bend as R
import ./utils/poptree.bend as Tree
import ./stats.bend as Stats
import ./operators.bend as Op
import ./mutations.bend as M
import ./ga.bend as GA
import ./utils/genes.bend as Genes

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
# PARTE 2: LEIS DOS COMBINADORES (operators.bend / mutations.bend)
# ----------------------------------------------------------------
# Estas leis respondem formalmente à pergunta "os combinadores de ordem
# superior custam alguma coisa?": elas afirmam que o pipeline montado por
# combinadores é DEFINICIONALMENTE IGUAL ao código escrito à mão. Provadas por
# reflexividade ({==}), os dois lados normalizam para o mesmo termo — a
# abstração desaparece em tempo de compilação.
#
# Operadores concretos sobre genoma `List<&2, U32>` de 8 genes, usados como
# instância (as leis não quantificam sobre parâmetros `~`):

def cross_u(a: List<&2, U32>, b: List<&2, U32>, s: U32) -> List<&2, U32>:
  Op.cross_uniform(U32, a, b, s)

def mut_n(g: List<&2, U32>, s: U32) -> List<&2, U32>:
  M.mut_neighbor(U32, g, 8, R.per(1, 8), s)

def bump(x: U32, s: U32) -> U32:
  U32.inc(x)

def mut_r(g: List<&2, U32>, s: U32) -> List<&2, U32>:
  M.mut_replace(~U32, ~bump, g, 8, R.per(1, 8), s)

# LEI 8: Pipeline de Reprodução = Código Manual
# `Op.pipe` com cruzamento uniforme + troca de vizinhos é exatamente
#   mut_n(cross_u(p, c, step(seed)), step(step(seed)))
law pipe_is_manual_code:
  for +p: List<&2, U32>
  for +c: List<&2, U32>
  for +seed: U32
  {Op.pipe(~List<&2, U32>, ~cross_u, ~mut_n, p, c, seed)
   == mut_n(cross_u(p, c, R.step(seed)), R.step(R.step(seed))) : List<&2, U32>}

# LEI 9: Encadeamento de Mutações = Composição das Duas Mutações
law chain_mutations_is_composition:
  for +g: List<&2, U32>
  for +seed: U32
  {M.chain_mutations(~List<&2, U32>, ~mut_n, ~mut_r, g, seed)
   == mut_r(mut_n(g, R.split.fst(seed)), R.split.snd(seed)) : List<&2, U32>}

# LEI 10: Despacho Exclusivo de Mutação (ramo verdadeiro)
# O `match` sobre Bool escolhe um único ramo; o outro nunca é construído.
law branch_mut_true_selects_first:
  for +g: List<&2, U32>
  for +seed: U32
  {M.branch_mut(~List<&2, U32>, ~mut_n, ~mut_r, True{}, g, seed) == mut_n(g, seed) : List<&2, U32>}

# LEI 11: Despacho Exclusivo de Mutação (ramo falso)
law branch_mut_false_selects_second:
  for +g: List<&2, U32>
  for +seed: U32
  {M.branch_mut(~List<&2, U32>, ~mut_n, ~mut_r, False{}, g, seed) == mut_r(g, seed) : List<&2, U32>}

# ----------------------------------------------------------------
# PARTE 3: LEIS DO MOTOR REAL (ga.bend)
# ----------------------------------------------------------------
# Leis sobre o arquipélago e a fusão de gerações que o motor realmente
# executa (o `ArchTree` e o `merge_gen` de ga.bend).

# LEI 12: Conservação de Ilhas na Migração (arquipélago REAL do motor)
# A migração do campeão global não cria nem destrói ilhas:
# arch_island_count(migrate_champion(arch, champ)) == arch_island_count(arch)
law arch_migration_preserves_islands:
  for +arch: GA.ArchTree<U32>
  for +champ: GA.Ind<U32>
  {GA.arch_island_count(U32, GA.migrate_champion(U32, arch, champ))
   == GA.arch_island_count(U32, arch) : Nat}

# LEI 13: a fusão de duas meias-gerações soma exatamente as duas populações
law merge_gen_size:
  for +gl: GA.Gen<U32>
  for +gr: GA.Gen<U32>
  {Nat.add(Tree.tree_size(GA.Ind<U32>, GA.Gen.pop(U32, gl)), Tree.tree_size(GA.Ind<U32>, GA.Gen.pop(U32, gr)))
   == Tree.tree_size(GA.Ind<U32>, GA.Gen.pop(U32, GA.merge_gen(U32, gl, gr))) : Nat}

# ----------------------------------------------------------------
# PARTE 4: LEIS DO VETOR DE GENES (utils/genes.bend)
# ----------------------------------------------------------------

# LEI 14: `take` e `drop` particionam a lista exatamente
# take(l, k) ++ drop(l, k) == l, para qualquer k.
# É o invariante que sustenta `rotate` — e, por consequência, o OX1, que
# monta o filho como uma rotação de `faltantes ++ segmento`. Se a partição
# perdesse ou duplicasse um gene, o filho deixaria de ser uma permutação.
#
# Enunciada sobre os `.go`, que é onde a condição do passo é um parâmetro:
# nas versões de entrada ela é calculada por dentro e o verificador não teria
# como reduzir o termo.
law take_drop_split:
  for +l: List<&2, U32>
  for  s: Bool
  for +k: U32
  {Genes.append(U32, Genes.take.go(U32, l, s, k), Genes.drop.go(U32, l, s, k)) == l : List<&2, U32>}

# PENDENTE (LEI 15): "a reprodução preserva o tamanho da população".
# O enunciado seria
#   tree_size(Gen.pop(breed_tree(~repro, ~fit, tree, on_elite, seed, cf, cg)))
#     == tree_size(tree)
# e a indução estrutural é trivial no papel, mas as reescritas `%` encadeadas
# no caso Node não convergiram: as duas hipóteses de indução precisam ser
# aplicadas dentro de um `Nat.add` cujos dois lados mudam, e o motivo aceito
# pelo verificador nessa posição não foi encontrado. A Lei 22 acima já cobre a
# metade difícil (a fusão soma as duas populações); falta só fechar a indução.
