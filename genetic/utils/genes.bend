import Base
import ./../../utils/random.bend as R

# ================================================================
# BEND 2 GENETIC UTILS - GENES (genes.bend)
# ================================================================
# O "array de genes" do motor: `List<&2, A>`, genérico sobre o tipo do gene.
#
# Por que lista encadeada e não `Array`? Porque `Array<T>` é um `Type` em
# Bend 2, não um `Data`: tem exatamente um dono, não pode ser duplicado com
# `+` nem morar dentro de `Ind<G>` ou da `PopTree`. Um genoma PRECISA ser
# `Data` — o motor clona o campeão para toda a população a cada geração.
#
# A lista é a estrutura que espelha o `&[G]` do motor em Rust: todo operador
# de cruzamento e mutação lá é uma varredura sequencial dos pais, e aqui é
# exatamente a mesma varredura. Medido: 1024 indivíduos x 400 gerações com
# genoma de 64 genes custa 1,3s e 4 MB de residente no binário nativo — a
# "explosão de nós DUP" só aparece com acesso indexado via `U32.to_nat` em
# laço quente, não com a lista em si.
#
# Convenções deste módulo:
#  - todo índice e contagem é `U32`; nenhum `Nat` é alocado em laço quente;
#  - toda recursão escruta um PARÂMETRO e a condição do passo seguinte entra
#    como parâmetro `Bool` (o padrão da Armadilha 2 do AGENTS.md);
#  - o argumento que encolhe vem sempre primeiro.
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
# CRUZAMENTO POSICIONAL (genérico sobre o tipo do gene)
# ----------------------------------------------------------------
# Os três cruzamentos posicionais do motor em Rust (uniforme, 1 ponto e
# 2 pontos) são a MESMA varredura dos dois pais; só muda quem decide, para
# cada posição, de qual pai o gene vem. Aqui essa decisão é um parâmetro
# template `~pred`, substituído em tempo de compilação — nenhuma closure,
# nenhum despacho dinâmico no código gerado.
#
# `pred(i, k, seed)` responde "esta posição vem do pai A?":
#   - uniforme : ignora `i` e `k`, sorteia com `seed`
#   - 1 ponto  : ignora `seed`, compara `i` com o corte guardado em `k`
#   - 2 pontos : ignora `seed`, `k` empacota os dois cortes (16 bits cada)
#
# A condição da posição seguinte é calculada aqui e desce como PARÂMETRO,
# porque `match` não escrutina valor computado (Armadilha 5).
def cross.go(~pred: U32 -> U32 -> U32 -> Bool, -A: Data,
             a: List<&2, A>, b: List<&2, A>, from_a: Bool,
             +i: U32, +k: U32, +seed: U32) -> List<&2, A>:
  match a b from_a:
    case Nil{} Nil{} True{}:
      Nil{}
    case Nil{} Nil{} False{}:
      Nil{}
    case Nil{} Con{y, ys} True{}:
      Nil{}
    case Nil{} Con{y, ys} False{}:
      Nil{}
    case Con{x, xs} Nil{} True{}:
      Nil{}
    case Con{x, xs} Nil{} False{}:
      Nil{}
    case Con{x, xs} Con{y, ys} True{}:
      +ni = U32.inc(i)
      +ns = R.step(seed)
      Con{x, cross.go(~pred, A, xs, ys, pred(ni, k, ns), ni, k, ns)}
    case Con{x, xs} Con{y, ys} False{}:
      +ni = U32.inc(i)
      +ns = R.step(seed)
      Con{y, cross.go(~pred, A, xs, ys, pred(ni, k, ns), ni, k, ns)}

def cross(~pred: U32 -> U32 -> U32 -> Bool, -A: Data,
          a: List<&2, A>, b: List<&2, A>, +k: U32, +seed: U32) -> List<&2, A>:
  cross.go(~pred, A, a, b, pred(0, k, seed), 0, k, seed)

# --- predicados ---

def pred_uniform(i: U32, k: U32, seed: U32) -> Bool:
  R.chance(seed, 50)

def pred_1point(i: U32, k: U32, seed: U32) -> Bool:
  U32.is_lt(i, k)

# `k` = corte inicial nos 16 bits baixos, corte final nos 16 altos.
# Fora do intervalo vem de A, dentro vem de B (igual ao crossover_2_point).
def pred_2point(i: U32, k: U32, seed: U32) -> Bool:
  +i = i
  +k = k
  Bool.or(U32.is_lt(i, U32.and(k, 65535)), U32.is_ge(i, U32.shrn(k, 16n)))

# --- cortes ---

# Corte único em [1, n-1]: nunca clona um pai inteiro
def cut_1point(+n: U32, +seed: U32) -> U32:
  (1 + U32.mod(seed, U32.max((n - 1 : U32), 1)) : U32)

# Dois cortes distintos e ordenados, empacotados em um U32
def cut_2point(+n: U32, +seed: U32) -> U32:
  +c1 = U32.mod(seed, n)
  +c2 = U32.mod(R.step(seed), n)
  +lo = U32.min(c1, c2)
  +hi = U32.max(c1, c2)
  U32.or(lo, U32.shln(hi, 16n))

# --- cruzamentos prontos ---

# Cada posição vem de um pai ou do outro, com 50% de chance
def cross_uniform(-A: Data, a: List<&2, A>, b: List<&2, A>, +seed: U32) -> List<&2, A>:
  cross(~pred_uniform, A, a, b, 0, seed)

# Prefixo de A até o corte, sufixo de B
def cross_1point(-A: Data, a: List<&2, A>, b: List<&2, A>, +n: U32, +seed: U32) -> List<&2, A>:
  cross(~pred_1point, A, a, b, cut_1point(n, seed), R.step(seed))

# Segmento interno de B, extremos de A
def cross_2point(-A: Data, a: List<&2, A>, b: List<&2, A>, +n: U32, +seed: U32) -> List<&2, A>:
  cross(~pred_2point, A, a, b, cut_2point(n, seed), R.step(seed))

# ----------------------------------------------------------------
# MUTAÇÕES (genéricas sobre o tipo do gene)
# ----------------------------------------------------------------
# Todas seguem o mesmo molde: a decisão "mutar esta posição?" é calculada no
# passo ANTERIOR e desce como parâmetro `do`, de modo que cada ramo do `match`
# tenha no máximo UMA chamada recursiva. Se a decisão virasse um `Bool.pick`
# com a recursão nos dois ramos, a HVM avaliaria as duas e o custo viraria
# exponencial (Armadilha 2).

# Insere `h` logo DEPOIS da cabeça de `l` — ou seja, troca `h` com o vizinho.
# Auxiliar NÃO recursivo sobre uma lista já pronta: é isso que permite ter uma
# única chamada recursiva por ramo (Bend 2 não tem recursão mútua).
def push_after_head(-A: Data, h: A, l: List<&2, A>) -> List<&2, A>:
  match l:
    case Nil{}:
      Con{h, Nil{}}
    case Con{h2, rest}:
      Con{h2, Con{h, rest}}

# Troca a posição atual com a seguinte
def mut_neighbor_swap(-A: Data, l: List<&2, A>, hit: Bool,
                      +rate_pct: U32, +seed: U32) -> List<&2, A>:
  match l hit:
    case Nil{} True{}:
      Nil{}
    case Nil{} False{}:
      Nil{}
    case Con{h, t} True{}:
      push_after_head(A, h, mut_neighbor_swap(A, t, R.chance(seed, rate_pct), rate_pct, R.step(seed)))
    case Con{h, t} False{}:
      Con{h, mut_neighbor_swap(A, t, R.chance(seed, rate_pct), rate_pct, R.step(seed))}

# Troca de vizinhos com `rate_pct`% de chance por posição
def mut_neighbor(-A: Data, l: List<&2, A>, +rate_pct: U32, +seed: U32) -> List<&2, A>:
  mut_neighbor_swap(A, l, R.chance(seed, rate_pct), rate_pct, R.step(seed))

# Substitui o gene por um novo sorteado por `~gen` (equivalente do
# `mutation_replace`): `~gen` é template, some em tempo de compilação
def mut_replace.go(~gen: A -> U32 -> A, -A: Data, l: List<&2, A>, hit: Bool,
                   +rate_pct: U32, +seed: U32) -> List<&2, A>:
  match l hit:
    case Nil{} True{}:
      Nil{}
    case Nil{} False{}:
      Nil{}
    case Con{h, t} True{}:
      Con{gen(h, seed), mut_replace.go(~gen, A, t, R.chance(seed, rate_pct), rate_pct, R.step(seed))}
    case Con{h, t} False{}:
      Con{h, mut_replace.go(~gen, A, t, R.chance(seed, rate_pct), rate_pct, R.step(seed))}

def mut_replace(~gen: A -> U32 -> A, -A: Data, l: List<&2, A>,
                +rate_pct: U32, +seed: U32) -> List<&2, A>:
  mut_replace.go(~gen, A, l, R.chance(seed, rate_pct), rate_pct, R.step(seed))

def maybe_swap(-A: Data, +l: List<&2, A>, hit: Bool, +i: U32, +j: U32, +dflt: A) -> List<&2, A>:
  match hit:
    case True{}:
      swap_at(A, l, i, j, dflt)
    case False{}:
      l

# Com `rate_pct`% de chance, troca duas posições sorteadas.
# Preserva o multiconjunto de genes, então é seguro para permutações.
def mut_swap(-A: Data, +l: List<&2, A>, +rate_pct: U32, +n: U32,
             +seed: U32, +dflt: A) -> List<&2, A>:
  +s1 = R.step(seed)
  maybe_swap(A, l, R.chance(seed, rate_pct),
             U32.mod(s1, n), U32.mod(R.step(s1), n), dflt)

# ----------------------------------------------------------------
# PERMUTAÇÕES (genes U32 em [0, 32) — TSP, ordenação, escalas)
# ----------------------------------------------------------------
# Cruzamento e mutação posicionais destroem permutações (geram genes
# repetidos). Para genomas que SÃO uma permutação, o operador correto é o
# Order Crossover (OX1). O motor em Rust guarda quais genes já foram copiados
# num vetor de marcas com epoch; aqui, como o gene é um índice < 32, a marca
# inteira cabe num único `U32` usado como conjunto de bits — teste de
# pertencimento em O(1) sem alocar nada.

def bit_of(+v: U32) -> U32:
  U32.shln(1, U32.to_nat(v))

# Conjunto de bits com todos os genes da lista
def mask_of(l: List<&2, U32>, +acc: U32) -> U32:
  match l:
    case Nil{}:
      acc
    case Con{h, t}:
      mask_of(t, U32.or(acc, bit_of(h)))

# Auxiliar não recursivo: decide se a cabeça entra no resultado já calculado
def put_if(h: U32, rest: List<&2, U32>, keep: Bool) -> List<&2, U32>:
  match keep:
    case True{}:
      Con{h, rest}
    case False{}:
      rest

# Genes da lista que NÃO estão no conjunto, preservando a ordem
def filter_unmarked(l: List<&2, U32>, +mask: U32) -> List<&2, U32>:
  match l:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      +h = h
      put_if(h, filter_unmarked(t, mask), U32.is_zero(U32.and(mask, bit_of(h))))

# Order Crossover (OX1). O filho herda o segmento [p1, p2] de `a` e completa
# as demais posições com os genes de `b` que faltam, na ordem em que `b` os
# apresenta, começando logo depois de p2 e dando a volta.
#
# A montagem é feita na ordem "dando a volta a partir de p2+1": nessa ordem o
# filho é exatamente `faltantes ++ segmento`. Uma rotação final devolve o
# segmento para a posição p1 original.
def cross_ox1(a: List<&2, U32>, b: List<&2, U32>, +n: U32, +seed: U32) -> List<&2, U32>:
  +c1 = U32.mod(seed, n)
  +c2 = U32.mod(R.step(seed), n)
  +p1 = U32.min(c1, c2)
  +p2 = U32.max(c1, c2)
  +seg = take(U32, drop(U32, a, p1), ((p2 - p1 : U32) + 1 : U32))
  +start = U32.mod((p2 + 1 : U32), n)
  +rest = filter_unmarked(rotate(U32, b, start), mask_of(seg, 0))
  rotate(U32, append(U32, rest, seg), U32.mod(((n - start : U32)), n))

# ----------------------------------------------------------------
# CONSTRUÇÃO DE PERMUTAÇÕES
# ----------------------------------------------------------------

def perm_range.go(k: Nat, +i: U32) -> List<&2, U32>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      Con{i, perm_range.go(p, U32.inc(i))}

# A permutação identidade [0, 1, ..., n-1]
def perm_range(k: Nat) -> List<&2, U32>:
  perm_range.go(k, 0)

def perm_shuffle.go(k: Nat, +l: List<&2, U32>, +n: U32, +seed: U32) -> List<&2, U32>:
  match k:
    case 0n:
      l
    case 1n+p:
      +s = R.step(seed)
      perm_shuffle.go(p, swap_at(U32, l, U32.mod(seed, n), U32.mod(s, n), 0), n, R.step(s))

# Embaralha por `k` transposições aleatórias (preserva a permutação)
def perm_shuffle(k: Nat, +l: List<&2, U32>, +n: U32, +seed: U32) -> List<&2, U32>:
  perm_shuffle.go(k, l, n, seed)

# Verdadeiro se a lista é uma permutação de [0, n-1].
# Usado pelos testes: é o invariante que OX1 e as mutações de troca preservam.
def is_permutation(+l: List<&2, U32>, +n: U32) -> Bool:
  Bool.and(U32.is_eq(len(U32, l), n),
           U32.is_eq(mask_of(l, 0), (U32.shln(1, U32.to_nat(n)) - 1 : U32)))
