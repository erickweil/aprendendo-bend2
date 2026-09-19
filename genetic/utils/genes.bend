import Base
import ./../../utils/random.bend as R

# ================================================================
# BEND 2 GENETIC UTILS - GENES (genes.bend)
# ================================================================
# O "vetor de genes" do motor: `List<&2, G>`, genérico sobre o tipo do gene.
# Este módulo tem só o núcleo (acesso, fatiamento, permutações e a ponte com
# `Array`). Os cruzamentos estão em `operators.bend`, as mutações em
# `mutations.bend`.
#
# Por que lista e não `Array`? `Array<T>` é um `Type` em Bend 2: tem um único
# dono, não pode ser duplicado com `+` nem morar dentro de `Ind<G>`. O motor
# duplica o campeão para a população inteira a cada geração, então o genoma
# PRECISA ser `Data`.
#
# Mas `Array` é excelente como RASCUNHO LOCAL dentro de um operador: no
# binário nativo é um buffer plano com get/set O(1) (medido: 40 milhões de
# acessos aleatórios em 0,09 s). O OX1 usa um `Array` de marcas e a mutação
# por troca converte a lista em `Array`, troca in-place, e converte de volta.
#
# Convenções: índices e contagens em `U32`; a condição do passo seguinte
# desce como parâmetro `Bool` (Armadilha 2); o argumento que encolhe vem
# primeiro. Nada aqui tem limite de tamanho além do próprio U32.
# ================================================================

# ----------------------------------------------------------------
# ACESSO BÁSICO (índices em U32)
# ----------------------------------------------------------------

def len.go(-A: Data, l: List<&2, A>, +acc: U32) -> U32:
  match l:
    case Nil{}:
      acc
    case Con{h, t}:
      len.go(A, t, U32.inc(acc))

def len(-A: Data, l: List<&2, A>) -> U32:
  len.go(A, l, 0)

# `here` diz se a posição ATUAL é a procurada; a do próximo passo é calculada
# aqui e entra como parâmetro.
def nth.go(-A: Data, l: List<&2, A>, here: Bool, +i: U32, +dflt: A) -> A:
  match l here:
    case Nil{} True{}:
      dflt
    case Nil{} False{}:
      dflt
    case Con{h, t} True{}:
      h
    case Con{h, t} False{}:
      nth.go(A, t, U32.is_eq(i, 1), U32.sub(i, 1), dflt)

# Elemento na posição `i`, ou `dflt` se a lista for curta demais
def nth(-A: Data, l: List<&2, A>, +i: U32, +dflt: A) -> A:
  nth.go(A, l, U32.is_zero(i), i, dflt)

def set_at.go(-A: Data, l: List<&2, A>, here: Bool, +i: U32, x: A) -> List<&2, A>:
  match l here:
    case Nil{} True{}:
      Nil{}
    case Nil{} False{}:
      Nil{}
    case Con{h, t} True{}:
      Con{x, t}
    case Con{h, t} False{}:
      Con{h, set_at.go(A, t, U32.is_eq(i, 1), U32.sub(i, 1), x)}

# Substitui a posição `i`; fora do intervalo devolve a lista intacta
def set_at(-A: Data, l: List<&2, A>, +i: U32, x: A) -> List<&2, A>:
  set_at.go(A, l, U32.is_zero(i), i, x)

def take.go(-A: Data, l: List<&2, A>, stop: Bool, +k: U32) -> List<&2, A>:
  match l stop:
    case Nil{} True{}:
      Nil{}
    case Nil{} False{}:
      Nil{}
    case Con{h, t} True{}:
      Nil{}
    case Con{h, t} False{}:
      Con{h, take.go(A, t, U32.is_eq(k, 1), U32.sub(k, 1))}

# Primeiros `k` genes
def take(-A: Data, l: List<&2, A>, +k: U32) -> List<&2, A>:
  take.go(A, l, U32.is_zero(k), k)

def drop.go(-A: Data, l: List<&2, A>, stop: Bool, +k: U32) -> List<&2, A>:
  match l stop:
    case Nil{} True{}:
      Nil{}
    case Nil{} False{}:
      Nil{}
    case Con{h, t} True{}:
      Con{h, t}
    case Con{h, t} False{}:
      drop.go(A, t, U32.is_eq(k, 1), U32.sub(k, 1))

# Todos menos os primeiros `k` genes
def drop(-A: Data, l: List<&2, A>, +k: U32) -> List<&2, A>:
  drop.go(A, l, U32.is_zero(k), k)

# Concatenação
def append(-A: Data, xs: List<&2, A>, ys: List<&2, A>) -> List<&2, A>:
  match xs:
    case Nil{}:
      ys
    case Con{h, t}:
      Con{h, append(A, t, ys)}

# Rotação à esquerda por `r` posições: o gene `r` passa a ser o primeiro
def rotate(-A: Data, +l: List<&2, A>, +r: U32) -> List<&2, A>:
  append(A, drop(A, l, r), take(A, l, r))

# Troca as posições `i` e `j` (preserva o multiconjunto de genes)
def swap_at(-A: Data, +l: List<&2, A>, +i: U32, +j: U32, +dflt: A) -> List<&2, A>:
  +vi = nth(A, l, i, dflt)
  +vj = nth(A, l, j, dflt)
  set_at(A, set_at(A, l, i, vj), j, vi)

# ----------------------------------------------------------------
# PONTE COM ARRAY (rascunho local de acesso O(1))
# ----------------------------------------------------------------
# O tipo do elemento é TEMPLATE (`~G`), não apagado (`-G`): o backend nativo
# precisa saber o tipo concreto do elemento de um `Array` ("an open Array
# element type"). Com `~G` cada uso é especializado em tempo de compilação.

def bits_of.go(k: Nat, +x: U32, +acc: U32) -> U32:
  match k:
    case 0n:
      acc
    case 1n+p:
      Bool.pick(U32, U32.is_zero(x), acc, bits_of.go(p, U32.shr(x), U32.inc(acc)))

# Menor `d` tal que 2^d >= n: a profundidade de um `Array` com n posições
def depth_for(+n: U32) -> Nat:
  U32.to_nat(bits_of.go(32n, (U32.max(n, 1) - 1 : U32), 0))

def fill(~G: Data, l: List<&2, G>, a: Array<G>, +i: U32) -> Array<G>:
  match l:
    case Nil{}:
      a
    case Con{h, t}:
      fill(~G, t, Array.set(G, a, i, h), U32.inc(i))

# Copia os `n` genes da lista para um `Array` (de 2^d posições, d = depth_for(n)).
# `dflt` preenche as posições excedentes até a potência de 2.
def to_array(~G: Data, l: List<&2, G>, +n: U32, +dflt: G) -> Array<G>:
  fill(~G, l, Array.new(G, depth_for(n), dflt), 0)

# Lê as `k` primeiras posições de volta para uma lista. O par (array, valor
# lido) é o próprio estado do laço: desestruturar um PARÂMETRO é permitido,
# desestruturar o retorno de uma chamada não é.
def unfill(~G: Data, k: Nat, r: Array<G> & G, +i: U32) -> List<&2, G>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      (a, v) = r
      +j = U32.inc(i)
      Con{v, unfill(~G, p, Array.get(G, a, j), j)}

def from_array(~G: Data, a: Array<G>, +n: U32) -> List<&2, G>:
  unfill(~G, U32.to_nat(n), Array.get(G, a, 0), 0)

def swap2.c(~G: Data, r: Array<G> & G, +i: U32) -> Array<G>:
  (a, vj) = r
  Array.set(G, a, i, vj)

def swap2.b(~G: Data, r: Array<G> & G, +i: U32, +j: U32) -> Array<G>:
  (a, vi) = r
  swap2.c(~G, Array.swap(G, a, j, vi), i)

# Troca in-place as posições `i` e `j` de um array, in-place
def swap2(~G: Data, a: Array<G>, +i: U32, +j: U32) -> Array<G>:
  swap2.b(~G, Array.get(G, a, i), i, j)

# ----------------------------------------------------------------
# PERMUTAÇÕES
# ----------------------------------------------------------------

def perm_range.go(k: Nat, +i: U32) -> List<&2, U32>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      Con{i, perm_range.go(p, U32.inc(i))}

# A permutação identidade [0, 1, ..., n-1]
def perm_range(+n: U32) -> List<&2, U32>:
  perm_range.go(U32.to_nat(n), 0)

# Fisher–Yates sobre o array: para i = n-1 .. 1, troca i com j em [0, i]
def fisher_yates(~G: Data, k: Nat, a: Array<G>, +i: U32, +seed: U32) -> Array<G>:
  match k:
    case 0n:
      a
    case 1n+p:
      fisher_yates(~G, p, swap2(~G, a, i, U32.mod(seed, U32.inc(i))), (i - 1 : U32), R.step(seed))

# Embaralhamento uniforme de uma lista de n genes, em O(n)
def shuffle(~G: Data, l: List<&2, G>, +n: U32, +seed: U32) -> List<&2, G>:
  match l:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      from_array(~G, fisher_yates(~G, U32.to_nat((n - 1 : U32)), to_array(~G, Con{h, t}, n, h), (n - 1 : U32), seed), n)

# Uma permutação aleatória de [0, n-1]
def perm_random(+n: U32, +seed: U32) -> List<&2, U32>:
  shuffle(~U32, perm_range(n), n, seed)

# Quantos genes aparecem pela primeira vez. `Array.swap` grava a marca e
# devolve a anterior numa operação só.
def fresh.go(l: List<&2, U32>, r: Array<U32> & U32, +acc: U32) -> U32:
  match l:
    case Nil{}:
      (a, old) = r
      (acc + Bool.to_u32(U32.is_zero(old)) : U32)
    case Con{h, t}:
      (a, old) = r
      fresh.go(t, Array.swap(U32, a, h, 1), (acc + Bool.to_u32(U32.is_zero(old)) : U32))

def all_below(l: List<&2, U32>, +n: U32) -> Bool:
  match l:
    case Nil{}:
      True{}
    case Con{h, t}:
      Bool.and(U32.is_lt(h, n), all_below(t, n))

# Verdadeiro se a lista é uma permutação de [0, n-1], para qualquer n.
def is_permutation(+l: List<&2, U32>, +n: U32) -> Bool:
  match l:
    case Nil{}:
      U32.is_zero(n)
    case Con{h, t}:
      Bool.and(U32.is_eq(len(U32, l), n),
      Bool.and(all_below(l, n),
               U32.is_eq(fresh.go(t, Array.swap(U32, Array.new(U32, depth_for(n), 0), h, 1), 0), n)))

# ----------------------------------------------------------------
# HASH (para o diversity_check do motor)
# ----------------------------------------------------------------

# Hash polinomial (h*31 + gene) sobre a lista; `~h` dá o valor de cada gene
def hash_list(~G: Data, ~h: G -> U32, l: List<&2, G>, +acc: U32) -> U32:
  match l:
    case Nil{}:
      acc
    case Con{x, t}:
      hash_list(~G, ~h, t, U32.add(U32.mul(acc, 31), h(x)))
