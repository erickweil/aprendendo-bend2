import Base
import ./../utils/random.bend as R

# Laço puramente sequencial, sem alocacao: o "corpo da ilha"
def busy(n: Nat, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      busy(p, R.step(acc))

# Arvore de bifurcacao de profundidade d; cada folha roda `n` passos sequenciais.
# d grande  = granularidade fina (forma do pow2)
# d pequeno = granularidade grossa (forma do arquipelago)
def fork_tree(d: Nat, +n: Nat, +s: U32) -> U32:
  match d:
    case 0n:
      busy(n, s)
    case 1n+p:
      +p = p; +n = n; +s = s
      a b = fork_tree(p, n, R.split.fst(s)) fork_tree(p, n, R.split.snd(s))
      (a + b : U32)
