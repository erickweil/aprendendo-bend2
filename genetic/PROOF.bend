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
import ./utils/bits.bend as Bits
import ./stats.bend as Stats
import ./operators.bend as Op
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
# PROVAS DA PARTE 2: COMBINADORES DE OPERADORES (operators.bend)
# ----------------------------------------------------------------
# As quatro leis desta parte são provadas por REFLEXIVIDADE PURA ({==}).
# Isso é o resultado mais forte possível sobre o custo da abstração:
# o verificador normaliza os dois lados e obtém literalmente o mesmo
# termo. Os parâmetros `~` são substituídos em tempo de compilação,
# então não existe closure, ponteiro de função nem despacho dinâmico
# no código gerado — é uma abstração de custo zero por construção,
# não por otimização do compilador.

# PROVA DA LEI 8: Pipeline Binário = Código Manual
def Laws.pipe_bits_is_manual_code(parent, champ, seed):
  {==}

# PROVA DA LEI 9: Encadeamento de Mutações = Composição
def Laws.chain_mutations_is_composition(g, seed):
  {==}

# PROVA DA LEI 10: Despacho Exclusivo (ramo verdadeiro)
def Laws.branch_mut_true_selects_first(g, seed):
  {==}

# PROVA DA LEI 11: Despacho Exclusivo (ramo falso)
def Laws.branch_mut_false_selects_second(g, seed):
  {==}
# ----------------------------------------------------------------
# PROVAS DA PARTE 3: MOTOR REAL (ga.bend)
# ----------------------------------------------------------------

# PROVA DA LEI 12: Conservação de Ilhas na Migração (Indução Estrutural)
def Laws.arch_migration_preserves_islands(arch, champ):
  match arch:
    case GA.SingleIsland{gen}:
      match gen champ:
        case GA.Gen{pop, bf, bg} GA.Ind{cg, cf}:
          {==}
    case GA.ArchBranch{left, right}:
      %Laws.arch_migration_preserves_islands(left, champ) : {Nat.add(GA.arch_island_count(U32, GA.migrate_champion(U32, left, champ)), GA.arch_island_count(U32, GA.migrate_champion(U32, right, champ))) == Nat.add(_, GA.arch_island_count(U32, right)) : Nat}
      %Laws.arch_migration_preserves_islands(right, champ) : {Nat.add(GA.arch_island_count(U32, GA.migrate_champion(U32, left, champ)), GA.arch_island_count(U32, GA.migrate_champion(U32, right, champ))) == Nat.add(GA.arch_island_count(U32, GA.migrate_champion(U32, left, champ)), _) : Nat}
      {==}

# PROVA DA LEI 13: abrir os dois `Gen` basta — `Gen.pop` projeta o nó sem
# depender da comparação de aptidões.
def Laws.merge_gen_size(gl, gr):
  match gl gr:
    case GA.Gen{lp, lf, lg} GA.Gen{rp, rf, rg}:
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
