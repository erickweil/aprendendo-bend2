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
# PARTE 2: COMBINADORES E DESPACHO (mutations.bend / ga.bend)
# ----------------------------------------------------------------
# Estas leis respondem formalmente à pergunta "a abstração de ordem superior
# custa alguma coisa?": elas afirmam que o código montado por templates é
# DEFINICIONALMENTE IGUAL ao escrito à mão. Provadas por reflexividade ({==}),
# os dois lados normalizam para o mesmo termo.

# Instâncias concretas (as leis não quantificam sobre parâmetros `~`):
def cross_u(ctx: U32, a: List<&2, U32>, b: List<&2, U32>, s: U32) -> List<&2, U32>:
  Op.cross_uniform(U32, a, b, s)

def mut_s(ctx: U32, g: List<&2, U32>, rate: U32, s: U32) -> List<&2, U32>:
  M.mut_swap(~U32, g, ctx, rate, s)

# LEI 8: mutation_combine = composição manual com a taxa dividida
# `combine` com troca aleatória + troca de vizinhos (templates aninhados) é
# exatamente os dois operadores em sequência, cada um com sua fração da taxa.
law combine_is_manual_code:
  for +l: List<&2, U32>
  for +n: U32
  for +rate: U32
  for +seed: U32
  {M.combine(~U32, ~M.mut_swap(~U32), ~M.mut_neighbor(~U32), {0.5 : F32}, {0.5 : F32}, l, n, rate, seed)
   == M.mut_neighbor(~U32, M.mut_swap(~U32, l, n, R.scale(rate, {0.5 : F32}), R.split.fst(seed)),
                     n, R.scale(rate, {0.5 : F32}), R.split.snd(seed)) : List<&2, U32>}

# LEI 9: sem sorteio de cruzamento, o filho é o pai 1 (o cruzamento nem é
# construído)
law cross_maybe_false_clones:
  for +ctx: U32
  for +a: List<&2, U32>
  for +b: List<&2, U32>
  for +seed: U32
  {GA.cross_maybe(~U32, ~List<&2, U32>, ~cross_u, False{}, ctx, a, b, seed) == a : List<&2, U32>}

# LEI 10: com sorteio, o filho é exatamente o cruzamento do problema
law cross_maybe_true_crosses:
  for +ctx: U32
  for +a: List<&2, U32>
  for +b: List<&2, U32>
  for +seed: U32
  {GA.cross_maybe(~U32, ~List<&2, U32>, ~cross_u, True{}, ctx, a, b, seed)
   == cross_u(ctx, a, b, seed) : List<&2, U32>}

# LEI 11: sem sorteio de mutação, o genoma passa intacto
law mutate_maybe_false_keeps:
  for +ctx: U32
  for +g: List<&2, U32>
  for +rate: U32
  for +seed: U32
  {GA.mutate_maybe(~U32, ~List<&2, U32>, ~mut_s, False{}, ctx, g, rate, seed) == g : List<&2, U32>}

# ----------------------------------------------------------------
# PARTE 3: LEIS DO MOTOR REAL (ga.bend)
# ----------------------------------------------------------------
# Leis sobre o arquipélago e a fusão de gerações que o motor realmente
# executa (o `ArchTree` e o `merge_gen` de ga.bend).

# LEI 12: Conservação de Ilhas na Migração em Anel (arquipélago real do motor)
# Trocar os melhores entre ilhas vizinhas não cria nem destrói ilhas, para
# qualquer lista de migrantes, qualquer posição inicial e qualquer tamanho:
# arch_island_count(migrate_ring(arch, ...)) == arch_island_count(arch)
law arch_migration_preserves_islands:
  for +arch: GA.ArchTree<U32>
  for +bests: List<&2, GA.Ind<U32>>
  for +k: U32
  for +i: U32
  for +size: U32
  {GA.arch_island_count(U32, GA.migrate_ring(U32, arch, bests, k, i, size))
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
