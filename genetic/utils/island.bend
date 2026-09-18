import Base
import ./poptree.bend as Tree

# ================================================================
# BEND 2 GENETIC UTILS - ISLAND MODEL (Arquipélago Paralelo)
# ================================================================
# Topologia formal de ilhas concorrentes estruturadas em árvore binária.
# Permite computação fork-join perfeitamente balanceada e sincronização
# de migração de campeão global em O(1) passos por época.
# ================================================================

type Archipelago<-A: Data> is Data:
  SingleIsland{tree: Tree.PopTree<A>}
  ArchBranch{left: Archipelago<A>, right: Archipelago<A>}

def single_island(-A: Data, tree: Tree.PopTree<A>) -> Archipelago<A>:
  SingleIsland{tree}

def arch_branch(-A: Data, left: Archipelago<A>, right: Archipelago<A>) -> Archipelago<A>:
  ArchBranch{left, right}

# Contagem de ilhas no arquipélago (número de núcleos/ilhas ativas)
def island_count(-A: Data, arch: Archipelago<A>) -> Nat:
  match arch:
    case SingleIsland{_}:
      1n
    case ArchBranch{left, right}:
      Nat.add(island_count(A, left), island_count(A, right))

# Tamanho populacional global somando todos os indivíduos de todas as ilhas
def total_pop_size(-A: Data, arch: Archipelago<A>) -> Nat:
  match arch:
    case SingleIsland{tree}:
      Tree.tree_size(A, tree)
    case ArchBranch{left, right}:
      Nat.add(total_pop_size(A, left), total_pop_size(A, right))

# Difusão / Migração do campeão global para todas as ilhas do arquipélago
def migrate(-A: Data, arch: Archipelago<A>, +champion: A) -> Archipelago<A>:
  match arch:
    case SingleIsland{tree}:
      SingleIsland{Tree.inject_elite(A, tree, champion)}
    case ArchBranch{left, right}:
      ArchBranch{migrate(A, left, champion), migrate(A, right, champion)}

# Geração uniforme de topologia de arquipélago balanceado de profundidade d
def gen_archipelago(-A: Data, d: Nat, +pop_depth: Nat, +val: A) -> Archipelago<A>:
  match d:
    case 0n:
      SingleIsland{Tree.gen_uniform(A, pop_depth, val)}
    case 1n++p:
      ArchBranch{gen_archipelago(A, p, pop_depth, val), gen_archipelago(A, p, pop_depth, val)}
