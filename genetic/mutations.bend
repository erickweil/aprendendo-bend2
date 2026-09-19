import Base
import ./../utils/random.bend as R
import ./utils/genes.bend as V

# ================================================================
# BEND 2 GENETIC OPERATORS - MUTAÇÕES (mutations.bend)
# ================================================================
# Todos os operadores de mutação do motor, portados do motor em Rust
# (`rust-wasm/src/genetic/operators/mutation_operators.rs`).
#
# Todos operam sobre `List<&2, G>`, são genéricos sobre o tipo do gene `G` e
# não têm limite de tamanho. As taxas são limiares sobre 2^32 (`R.per`), o
# que permite taxas por gene como 1/N mesmo com N = 1 milhão.
#
# Molde comum (porte do `for_each_poisson` do Rust): em vez de sortear
# "mutar?" em cada gene, sorteia-se a DISTÂNCIA até a próxima mutação, com
# distribuição geométrica. Isso tem duas vantagens numa lista imutável:
#  - nenhum número aleatório por gene, só um por mutação;
#  - quando a próxima mutação cairia além do fim da lista, a cauda restante
#    é devolvida COMPARTILHADA, sem copiar nada. Com taxa 1/N, só o trecho
#    até a última mutação é realocado.
#
# As decisões "acabou?" e "é aqui?" são calculadas no passo anterior e descem
# como parâmetros `Bool`, para que cada ramo do `match` tenha no máximo UMA
# chamada recursiva (Armadilha 2).
# ================================================================

# ----------------------------------------------------------------
# SALTO GEOMÉTRICO (for_each_poisson)
# ----------------------------------------------------------------

# ln(1 - p) para a probabilidade p = rate / 2^32. Para p pequeno usa a série
# -(p + p²/2): em F32, `1 - 1e-7` arredonda para 1 e o log daria zero.
def ln_miss(+rate: U32) -> F32:
  +p = (U32.to_f32(rate) / {4294967296.0 : F32} : F32)
  Bool.pick(F32, F32.is_lt(p, {0.01 : F32}),
    (({0.0 : F32} - p) - ((p * p) / {2.0 : F32}) : F32),
    F32.log(({1.0 : F32} - p : F32)))

# Quantos genes pular até a próxima mutação: floor(ln(u) / ln(1 - p)).
# Taxa 0 nunca muta (salto infinito); o quociente é limitado antes da
# conversão, porque converter um F32 acima de 2^32 para U32 é indefinido em C.
def gap(+seed: U32, +rate: U32, +lnq: F32) -> U32:
  +u = (U32.to_f32(R.mix(seed)) / {4294967296.0 : F32} : F32)
  Bool.pick(U32, U32.is_zero(rate), 4294967295,
    F32.to_u32(F32.min((F32.log(u) / lnq : F32), {4000000000.0 : F32})))

# ----------------------------------------------------------------
# SUBSTITUIÇÃO (mutation_replace)
# ----------------------------------------------------------------

# `left` = genes a pular até a próxima mutação; `rem` = genes restantes.
# done = left >= rem (a próxima mutação cai depois do fim); hit = left == 0.
def mut_replace.go(~G: Data, ~gen: G -> U32 -> G, l: List<&2, G>, done: Bool, hit: Bool,
                   +left: U32, +rem: U32, +rate: U32, +lnq: F32, +seed: U32) -> List<&2, G>:
  match l done hit:
    case Nil{} True{} True{}:
      Nil{}
    case Nil{} True{} False{}:
      Nil{}
    case Nil{} False{} True{}:
      Nil{}
    case Nil{} False{} False{}:
      Nil{}
    case Con{h, t} True{} True{}:
      Con{h, t}
    case Con{h, t} True{} False{}:
      Con{h, t}
    case Con{h, t} False{} True{}:
      +s1 = R.step(seed)
      +g = gap(s1, rate, lnq)
      +r = (rem - 1 : U32)
      Con{gen(h, seed), mut_replace.go(~G, ~gen, t, U32.is_ge(g, r), U32.is_zero(g), g, r, rate, lnq, R.step(s1))}
    case Con{h, t} False{} False{}:
      +l1 = (left - 1 : U32)
      +r = (rem - 1 : U32)
      Con{h, mut_replace.go(~G, ~gen, t, U32.is_ge(l1, r), U32.is_zero(l1), l1, r, rate, lnq, seed)}

# Cada um dos `n` genes, com probabilidade `rate`, é trocado por
# `gen(gene, semente)`. `~gen` é template: some em tempo de compilação.
def mut_replace(~G: Data, ~gen: G -> U32 -> G, l: List<&2, G>,
                +n: U32, +rate: U32, +seed: U32) -> List<&2, G>:
  +lnq = ln_miss(rate)
  +g = gap(seed, rate, lnq)
  mut_replace.go(~G, ~gen, l, U32.is_ge(g, n), U32.is_zero(g), g, n, rate, lnq, R.step(seed))

# ----------------------------------------------------------------
# TROCA DE VIZINHOS (mutation_neighbor_swap)
# ----------------------------------------------------------------

# Insere `h` logo DEPOIS da cabeça de `l` — ou seja, troca `h` com o vizinho.
# Auxiliar NÃO recursivo sobre a lista que a recursão já produziu: é isso que
# permite uma única chamada recursiva por ramo (não há recursão mútua).
def push_after_head(-G: Data, h: G, l: List<&2, G>) -> List<&2, G>:
  match l:
    case Nil{}:
      Con{h, Nil{}}
    case Con{h2, rest}:
      Con{h2, Con{h, rest}}

def mut_neighbor.go(-G: Data, l: List<&2, G>, done: Bool, hit: Bool,
                    +left: U32, +rem: U32, +rate: U32, +lnq: F32, +seed: U32) -> List<&2, G>:
  match l done hit:
    case Nil{} True{} True{}:
      Nil{}
    case Nil{} True{} False{}:
      Nil{}
    case Nil{} False{} True{}:
      Nil{}
    case Nil{} False{} False{}:
      Nil{}
    case Con{h, t} True{} True{}:
      Con{h, t}
    case Con{h, t} True{} False{}:
      Con{h, t}
    case Con{h, t} False{} True{}:
      +g = gap(seed, rate, lnq)
      +r = (rem - 1 : U32)
      push_after_head(G, h, mut_neighbor.go(G, t, U32.is_ge(g, r), U32.is_zero(g), g, r, rate, lnq, R.step(seed)))
    case Con{h, t} False{} False{}:
      +l1 = (left - 1 : U32)
      +r = (rem - 1 : U32)
      Con{h, mut_neighbor.go(G, t, U32.is_ge(l1, r), U32.is_zero(l1), l1, r, rate, lnq, seed)}

# Cada uma das `n` posições, com probabilidade `rate`, troca de lugar com a
# seguinte. Preserva o multiconjunto de genes: seguro para permutações.
def mut_neighbor(-G: Data, l: List<&2, G>, +n: U32, +rate: U32, +seed: U32) -> List<&2, G>:
  +lnq = ln_miss(rate)
  +g = gap(seed, rate, lnq)
  mut_neighbor.go(G, l, U32.is_ge(g, n), U32.is_zero(g), g, n, rate, lnq, R.step(seed))

# ----------------------------------------------------------------
# TROCA ALEATÓRIA (mutation_random_swap)
# ----------------------------------------------------------------
# Troca entre posições distantes precisa de acesso aleatório. Numa lista,
# cada troca custaria O(n), e com taxa `rate` são rate*n trocas: O(rate*n²).
# Então a lista vira um `Array` (rascunho local, dono único), as trocas são
# feitas in-place em O(1), e o array volta a ser lista: O(n) para qualquer
# taxa, e sem limite de tamanho.


# Laço sobre as MUTAÇÕES, não sobre as posições: `pos` salta direto para a
# próxima posição sorteada. O combustível `k` só existe para o verificador de
# terminação; o laço para assim que `pos` passa do fim (`done`).
def swap_loop(~G: Data, k: Nat, a: Array<G>, done: Bool, +pos: U32, +n: U32,
              +rate: U32, +lnq: F32, +seed: U32) -> Array<G>:
  match k done:
    case 0n True{}:
      a
    case 0n False{}:
      a
    case 1n+p True{}:
      a
    case 1n+p False{}:
      +s = R.step(seed)
      # outra posição, garantidamente diferente de pos (random_range_except)
      +j = U32.mod((pos + 1 + U32.mod(s, U32.max((n - 1 : U32), 1)) : U32), n)
      +next = (pos + 1 + gap(R.step(s), rate, lnq) : U32)
      swap_loop(~G, p, V.swap2(~G, a, pos, j), U32.is_ge(next, n), next, n, rate, lnq, R.step(R.step(s)))

# Cada posição, com probabilidade `rate`, troca com outra posição sorteada.
# Preserva o multiconjunto de genes: seguro para permutações.
def mut_swap(~G: Data, l: List<&2, G>, +n: U32, +rate: U32, +seed: U32) -> List<&2, G>:
  match l:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      +lnq = ln_miss(rate)
      +first = gap(seed, rate, lnq)
      V.from_array(~G, swap_loop(~G, U32.to_nat(n), V.to_array(~G, Con{h, t}, n, h),
                                 U32.is_ge(first, n), first, n, rate, lnq, R.step(seed)), n)

# ----------------------------------------------------------------
# COMBINADORES DE MUTAÇÃO
# ----------------------------------------------------------------

# Despacho exclusivo entre duas mutações: só um dos ramos toca o genoma
def branch_mut(~G: Type, ~m1: G -> U32 -> G, ~m2: G -> U32 -> G,
               cond: Bool, g: G, +seed: U32) -> G:
  match cond:
    case True{}:
      m1(g, seed)
    case False{}:
      m2(g, seed)

# Despacho exclusivo entre mutar e preservar
def branch_maybe_mut(~G: Type, ~mut: G -> U32 -> G, cond: Bool, g: G, +seed: U32) -> G:
  match cond:
    case True{}:
      mut(g, seed)
    case False{}:
      g

# Aplica a mutação ao indivíduo com probabilidade `rate` (a `mutation_rate`
# por indivíduo do Rust; a taxa por gene fica dentro do próprio operador)
def maybe_mutate(~G: Type, ~mut: G -> U32 -> G, +rate: U32, g: G, +seed: U32) -> G:
  branch_maybe_mut(~G, ~mut, R.hit(seed, rate), g, R.step(seed))

# Exatamente UM dos dois operadores, escolhido com probabilidade `rate_m1`
def combine_mutations(~G: Type, ~m1: G -> U32 -> G, ~m2: G -> U32 -> G,
                      +rate_m1: U32, g: G, +seed: U32) -> G:
  branch_mut(~G, ~m1, ~m2, R.hit(seed, rate_m1), g, R.step(seed))

# Os DOIS operadores em sequência, com sementes independentes: o equivalente
# de `mutation_combine` do Rust (cada operador recebe sua fração da taxa)
def chain_mutations(~G: Type, ~m1: G -> U32 -> G, ~m2: G -> U32 -> G,
                    g: G, +seed: U32) -> G:
  m2(m1(g, R.split.fst(seed)), R.split.snd(seed))
