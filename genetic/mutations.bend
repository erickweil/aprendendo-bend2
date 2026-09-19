import Base
import ./../utils/random.bend as R
import ./utils/genes.bend as V

# ================================================================
# BEND 2 GENETIC OPERATORS - MUTAÇÕES (mutations.bend)
# ================================================================
# Portes de `rust-wasm/src/genetic/operators/mutation_operators.rs`.
#
# Todos operam sobre `List<&2, G>`, são genéricos sobre o tipo do gene e não
# têm limite de tamanho. Todos têm a MESMA assinatura final,
#     (l, n, rate, seed) -> l'
# (a lista, seu comprimento, a taxa por gene como limiar `R.per`, a semente),
# para que possam ser combinados por `combine`. Os parâmetros finais são
# SEM `+` de propósito: um template exige a assinatura exata, inclusive as
# quantidades (Armadilha 7), e `~M.mut_swap(~U32)` precisa encaixar em
# `List -> U32 -> U32 -> U32 -> List`. O reuso é feito por dentro com `+x = x`.
#
# A posição de cada mutação vem do salto geométrico `R.gap` (o
# `for_each_poisson` do Rust): em vez de sortear em cada gene, sorteia-se a
# distância até o próximo gene sorteado.
# ================================================================

# ----------------------------------------------------------------
# SUBSTITUIÇÃO (mutation_replace)
# ----------------------------------------------------------------
# Percorre a lista saltando de um gene sorteado ao próximo. Quando a próxima
# mutação cairia depois do fim, a cauda restante é devolvida COMPARTILHADA,
# sem copiar: com taxa 1/N só o trecho até a última mutação é realocado.
#
# `left` = genes a pular até a próxima mutação; `rem` = genes restantes.
# done = left >= rem; hit = left == 0. As duas decisões descem como parâmetro
# (match não escrutina valor computado).
def mut_replace.go(~G: Data, ~gen: G -> U32 -> G, l: List<&2, G>, done: Bool, hit: Bool,
                   +left: U32, +rem: U32, +rate: U32, +lnq: F32, +seed: U32) -> List<&2, G>:
  match l done hit:
    case Nil{} _ _:
      Nil{}
    case Con{h, t} True{} _:
      Con{h, t}
    case Con{h, t} False{} True{}:
      +s1 = R.step(seed)
      +g = R.gap(s1, rate, lnq)
      +r = (rem - 1 : U32)
      Con{gen(h, seed), mut_replace.go(~G, ~gen, t, U32.is_ge(g, r), U32.is_zero(g), g, r, rate, lnq, R.step(s1))}
    case Con{h, t} False{} False{}:
      +l1 = (left - 1 : U32)
      +r = (rem - 1 : U32)
      Con{h, mut_replace.go(~G, ~gen, t, U32.is_ge(l1, r), U32.is_zero(l1), l1, r, rate, lnq, seed)}

# Cada gene, com probabilidade `rate`, vira `gen(gene, semente)`
def mut_replace(~G: Data, ~gen: G -> U32 -> G, l: List<&2, G>,
                n: U32, rate: U32, seed: U32) -> List<&2, G>:
  +n = n
  +rate = rate
  +seed = seed
  +lnq = R.ln_miss(rate)
  +g = R.gap(seed, rate, lnq)
  mut_replace.go(~G, ~gen, l, U32.is_ge(g, n), U32.is_zero(g), g, n, rate, lnq, R.step(seed))

# ----------------------------------------------------------------
# TROCAS (mutation_random_swap, mutation_neighbor_swap)
# ----------------------------------------------------------------
# Trocar duas posições precisa de acesso aleatório: numa lista cada troca
# custaria O(n). A lista vira um `Array` (rascunho local de dono único), as
# trocas são in-place em O(1) e o array volta a ser lista: O(n) para qualquer
# taxa. As duas mutações só diferem em COM QUEM a posição sorteada troca —
# o template `~partner(pos, n, seed)`.

# Laço sobre as MUTAÇÕES, não sobre as posições: `pos` salta direto para a
# próxima posição sorteada. O combustível `k` existe para o verificador de
# terminação; o laço para assim que `pos` passa do fim (`done`).
def swap_loop(~G: Data, ~partner: U32 -> U32 -> U32 -> U32,
              k: Nat, a: Array<G>, done: Bool, +pos: U32, +n: U32,
              +rate: U32, +lnq: F32, +seed: U32) -> Array<G>:
  match k done:
    case _ True{}:
      a
    case 0n False{}:
      a
    case 1n+p False{}:
      +s = R.step(seed)
      +next = (pos + 1 + R.gap(R.split.fst(s), rate, lnq) : U32)
      swap_loop(~G, ~partner, p, V.swap2(~G, a, pos, partner(pos, n, s)),
                U32.is_ge(next, n), next, n, rate, lnq, R.split.snd(s))

def swaps(~G: Data, ~partner: U32 -> U32 -> U32 -> U32,
          l: List<&2, G>, +n: U32, +rate: U32, +seed: U32) -> List<&2, G>:
  match l:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      +lnq = R.ln_miss(rate)
      +first = R.gap(seed, rate, lnq)
      V.from_array(~G, swap_loop(~G, ~partner, U32.to_nat(n), V.to_array(~G, Con{h, t}, n, h),
                                 U32.is_ge(first, n), first, n, rate, lnq, R.step(seed)), n)

# Qualquer outra posição (random_range_except)
def random_partner(pos: U32, n: U32, seed: U32) -> U32:
  R.range_except(seed, n, pos)

# A vizinha da esquerda ou da direita, dando a volta nas pontas
def neighbor_partner(pos: U32, n: U32, seed: U32) -> U32:
  +pos = pos
  +n = n
  Bool.pick(U32, R.bool(seed), U32.mod(U32.inc(pos), n), U32.mod((pos + n - 1 : U32), n))

# Cada posição, com probabilidade `rate`, troca com outra posição sorteada.
# Preserva o multiconjunto de genes: seguro para permutações.
def mut_swap(~G: Data, l: List<&2, G>, n: U32, rate: U32, seed: U32) -> List<&2, G>:
  swaps(~G, ~random_partner, l, n, rate, seed)

# Cada posição, com probabilidade `rate`, troca com a vizinha da esquerda ou
# da direita (dando a volta nas pontas, como no Rust). Com menos de 2 genes
# não há vizinha.
def mut_neighbor(~G: Data, l: List<&2, G>, n: U32, rate: U32, seed: U32) -> List<&2, G>:
  +n = n
  swaps(~G, ~neighbor_partner, l, n, Bool.pick(U32, U32.is_lt(n, 2), 0, rate), seed)

# ----------------------------------------------------------------
# COMBINAÇÃO (mutation_combine)
# ----------------------------------------------------------------
# Aplica os DOIS operadores em sequência, cada um com uma fração da taxa por
# gene, com sementes independentes — o `mutation_combine` do Rust. Como os
# operadores são templates, `combine` pode ser aninhado para combinar mais de
# dois (o `mutationCombineOperator` do TS aceita uma lista).
def combine(~G: Data,
            ~ma: List<&2, G> -> U32 -> U32 -> U32 -> List<&2, G>,
            ~mb: List<&2, G> -> U32 -> U32 -> U32 -> List<&2, G>,
            +fa: F32, +fb: F32, l: List<&2, G>, +n: U32, +rate: U32, +seed: U32) -> List<&2, G>:
  mb(ma(l, n, R.scale(rate, fa), R.split.fst(seed)), n, R.scale(rate, fb), R.split.snd(seed))
