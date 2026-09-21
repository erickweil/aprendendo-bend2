import Base
import ./../utils/arrays.bend as Arr
import ./../utils/tuples.bend as T
import ./../utils/random.bend as R

# ================================================================
# OPERADORES DE GENE (operators.bend)
# ================================================================
# Genoma = `Array<U32>` de `n` genes. Todos os operadores são IN-PLACE e não
# alocam: recebem os genomas e devolvem os mesmos buffers.
#
# Há duas famílias:
#
#  - `breed_*` (4 argumentos): o que o motor chama. Lê os dois pais e escreve
#    os dois filhos numa varredura só, que é o "4 entram, 4 saem" do modelo
#    geracional.
#  - `cross_*` (2 argumentos): troca material ENTRE dois genomas, in-place.
#    O motor não os usa diretamente, mas o `~breed` de um problema pode: copie
#    os pais nos filhos com `Arr.copy_range` e depois cruze os filhos entre si.
#    É como escrever um cruzamento que não tem versão de 4 argumentos ainda
#    (o uniforme, por exemplo).
#
# Custo medido das primitivas (n = 2^20): troca de faixa 1,1 ns por posição,
# cópia 0,6 ns, sorteio 2–3,6 ns.

# ----------------------------------------------------------------
# CRUZAMENTO
# ----------------------------------------------------------------

# Um ponto: sorteia o corte em [1, n) e troca o sufixo. O sufixo do pai A é o
# do filho B e vice-versa, exatamente como no crossover clássico.
def cross_1point(a: Array<U32>, b: Array<U32>, +n: U32, +seed: U32) -> Array<U32> & Array<U32>:
  +cut = U32.inc(R.range(seed, U32.max((n - 1 : U32), 1)))
  Arr.swap_range(~U32, a, b, cut, (n - cut : U32))

# Dois pontos: troca o miolo [lo, hi). Com lo == hi não troca nada, o que é o
# mesmo que "sem cruzamento" e acontece com probabilidade 1/n.
def cross_2point(a: Array<U32>, b: Array<U32>, +n: U32, +seed: U32) -> Array<U32> & Array<U32>:
  +p1 = R.range(seed, n)
  +p2 = R.range(R.split.fst(seed), n)
  +lo = U32.min(p1, p2)
  +hi = U32.max(p1, p2)
  Arr.swap_range(~U32, a, b, lo, (hi - lo : U32))

# Uniforme: uma moeda por posição; quando dá cara, os dois genes trocam de
# lugar. `rate` é o limiar de R.hit (use R.per(1, 2) para meio a meio).
def uniform.set_a(a: Array<U32>, +i: U32, r: Array<U32> & U32) -> Array<U32> & Array<U32>:
  (b, value_b) = r
  T.pair(Array<U32>, Array<U32>, Array.set(U32, a, i, value_b), b)

def uniform.one(b: Array<U32>, +i: U32, r: Array<U32> & U32) -> Array<U32> & Array<U32>:
  (a, value_a) = r
  uniform.set_a(a, i, Array.swap(U32, b, i, value_a))

def uniform.pick(hit: Bool, a: Array<U32>, b: Array<U32>, +i: U32) -> Array<U32> & Array<U32>:
  match hit:
    case True{}:
      uniform.one(b, i, Array.get(U32, a, i))
    case False{}:
      T.pair(Array<U32>, Array<U32>, a, b)

def uniform.go(k: Nat, st: Array<U32> & Array<U32>, +i: U32, +rate: U32, +seed: U32) -> Array<U32> & Array<U32>:
  match k:
    case 0n:
      st
    case 1n+p:
      (a, b) = st
      uniform.go(p, uniform.pick(R.hit(seed, rate), a, b, i), (i + 1 : U32), rate, R.step(seed))

def cross_uniform(a: Array<U32>, b: Array<U32>, +n: U32, +rate: U32, +seed: U32) -> Array<U32> & Array<U32>:
  uniform.go(U32.to_nat(n), T.pair(Array<U32>, Array<U32>, a, b), 0, rate, seed)

# ----------------------------------------------------------------
# MUTAÇÃO
# ----------------------------------------------------------------

# Substituição com taxa por gene, pulando com o salto geométrico (o
# for_each_poisson do Rust): em vez de sortear em cada gene, sorteia a
# distância até o próximo gene mutado. Custo O(mutações), não O(n).
# `values` é quantos valores diferentes um gene pode ter (2 para bits).
def mut_replace.go(fuel: Nat, stop: Bool, g: Array<U32>, +i: U32, +n: U32,
                   +values: U32, +rate: U32, +lnq: F32, +seed: U32) -> Array<U32>:
  match fuel stop:
    case _ True{}:
      g
    case 0n False{}:
      g
    case 1n+p False{}:
      +jump = U32.inc(R.gap(R.split.fst(seed), rate, lnq))
      +j = (i + jump : U32)
      mut_replace.go(p, U32.is_ge(j, n),
        Array.set(U32, g, i, R.range(R.split.snd(seed), values)),
        j, n, values, rate, lnq, R.step(seed))

def mut_replace(g: Array<U32>, +n: U32, +values: U32, +rate: U32, +seed: U32) -> Array<U32>:
  +lnq = R.ln_miss(rate)
  +first = R.gap(seed, rate, lnq)
  mut_replace.go(U32.to_nat(n), U32.is_ge(first, n), g, first, n, values, rate, lnq, R.step(seed))

# Troca duas posições sorteadas, `count` vezes. Preserva o multiconjunto de
# genes, então serve para genoma-permutação.
def mut_swap.go(k: Nat, g: Array<U32>, +n: U32, +seed: U32) -> Array<U32>:
  match k:
    case 0n:
      g
    case 1n+p:
      mut_swap.go(p, Arr.swap_at(~U32, g, R.range(seed, n), R.range(R.split.fst(seed), n)), n, R.step(seed))

def mut_swap(g: Array<U32>, +n: U32, +count: U32, +seed: U32) -> Array<U32>:
  mut_swap.go(U32.to_nat(count), g, n, seed)

# ----------------------------------------------------------------
# CRUZAMENTO "4 ENTRAM, 4 SAEM"
# ----------------------------------------------------------------
# Lê os dois pais e escreve os dois filhos numa varredura só, sem cópia
# intermediária. O laço NÃO tem desvio por elemento: o corte divide em duas
# faixas e a segunda só troca o papel dos dois pais. (Uma versão que escolhia
# o pai com `Bool.pick` genérico dentro do laço ficou 3× MAIS LENTA: o
# Bool.pick genérico encaixota o valor, ou seja, aloca por elemento.)

def b1.w(~T: Data, ca: Array<T>, cb: Array<T>, +i: U32, r: Array<T> & T, y: T, pb: Array<T>) ->
  (Array<T> & Array<T>) & (Array<T> & Array<T>):
  (pa, x) = r
  ((Array.set(T, ca, i, x), Array.set(T, cb, i, y)), (pa, pb))

def b1.rb(~T: Data, ca: Array<T>, cb: Array<T>, pa: Array<T>, +i: U32, r: Array<T> & T) ->
  (Array<T> & Array<T>) & (Array<T> & Array<T>):
  (pb, y) = r
  b1.w(~T, ca, cb, i, Array.get(T, pa, i), y, pb)

def b1.step(~T: Data, st: (Array<T> & Array<T>) & (Array<T> & Array<T>), +i: U32) ->
  (Array<T> & Array<T>) & (Array<T> & Array<T>):
  (filhos, pais) = st
  (ca, cb) = filhos
  (pa, pb) = pais
  b1.rb(~T, ca, cb, pa, i, Array.get(T, pb, i))

# copia a faixa [i, i+k): filho A recebe do pai A, filho B do pai B
def b1.go(~T: Data, k: Nat, st: (Array<T> & Array<T>) & (Array<T> & Array<T>), +i: U32) ->
  (Array<T> & Array<T>) & (Array<T> & Array<T>):
  match k:
    case 0n:
      st
    case 1n+p:
      b1.go(~T, p, b1.step(~T, st, i), (i + 1 : U32))

# troca o papel dos dois pais (para a segunda faixa)
def b1.troca(~T: Data, st: (Array<T> & Array<T>) & (Array<T> & Array<T>)) ->
  (Array<T> & Array<T>) & (Array<T> & Array<T>):
  (filhos, pais) = st
  (pa, pb) = pais
  (filhos, (pb, pa))

def b1.dois(~T: Data, st: (Array<T> & Array<T>) & (Array<T> & Array<T>), +cut: U32, +n: U32) ->
  (Array<T> & Array<T>) & (Array<T> & Array<T>):
  b1.troca(~T, b1.go(~T, U32.to_nat((n - cut : U32)), b1.troca(~T, st), cut))

def breed_1point(~T: Data, ca: Array<T>, cb: Array<T>, pa: Array<T>, pb: Array<T>,
                 +n: U32, cruza: Bool, +seed: U32) ->
  (Array<T> & Array<T>) & (Array<T> & Array<T>):
  +cut = Bool.pick(U32, cruza, U32.inc(R.range(seed, U32.max((n - 1 : U32), 1))), n)
  b1.dois(~T, b1.go(~T, U32.to_nat(cut), ((ca, cb), (pa, pb)), 0), cut, n)

# ----------------------------------------------------------------
# CRUZAMENTO OX1 (Order Crossover)
# ----------------------------------------------------------------
# Preserva permutação: sorteia dois cortes, copia o miolo [c1, c2] de cada pai
# para o respectivo filho, e completa o resto lendo o OUTRO pai em ordem
# circular a partir de c2+1, pulando as chaves que o miolo já trouxe.
#
# O ponto delicado é o "já trouxe": é preciso um CONJUNTO de chaves presentes.
# A saída óbvia — uma máscara de bits num U32 — limita o operador a 32 chaves.
# Dá para os 9 dígitos do sudoku e NÃO dá para um quadro de horário, onde as
# chaves são dezenas ou centenas de disciplinas.
#
# Aqui o conjunto é uma FAIXA DE RASCUNHO do próprio array do filho, com uma
# posição por chave: `filho[mark_base + chave]`. Não há teto de chaves, não há
# alocação (o rascunho já existe no genoma, como a arena exige) e o teste de
# pertinência é um `Array.get` — 0,55 ns. O rascunho é limpo no fim relendo o
# miolo do pai: `mid_len` escritas, não `n_chaves`, então o custo NÃO cresce
# com o tamanho do alfabeto.
#
# Por que `Array<U32>` e não `Array<T>` genérico: a marca é gravada DENTRO do
# array do filho, então o sentinela tem de ser do tipo do elemento. Todo
# genoma deste motor é `Array<U32>`; `~key` é que dá a genericidade, mapeando
# o gene para o índice da marca.
#
# CONTRATO do chamador:
#   - [mark_base, mark_base + n_chaves) não encosta em [base, base + n) nem em
#     nenhuma outra parte viva do genoma;
#   - `~key(x)` devolve uma chave em [0, n_chaves);
#   - os dois pais são permutações do MESMO multiconjunto de chaves.

# --- copiar o miolo do pai para o filho, marcando as chaves ---

def ox1.mid.w(~key: @+x: U32 -> U32, child: Array<U32>, +idx: U32, +mark_base: U32,
              r: Array<U32> & U32) -> Array<U32> & Array<U32>:
  (parent, +v) = r
  (Array.set(U32, Array.set(U32, child, idx, v), (mark_base + key(v) : U32), 1), parent)

def ox1.mid.go(~key: @+x: U32 -> U32, k: Nat, st: Array<U32> & Array<U32>,
               +idx: U32, +mark_base: U32) -> Array<U32> & Array<U32>:
  match k:
    case 0n:
      st
    case 1n+p:
      (child, parent) = st
      ox1.mid.go(~key, p, ox1.mid.w(~key, child, idx, mark_base, Array.get(U32, parent, idx)),
                 (idx + 1 : U32), mark_base)

# --- apagar as marcas, relendo o mesmo miolo ---

def ox1.clear.w(~key: @+x: U32 -> U32, child: Array<U32>, +mark_base: U32,
                r: Array<U32> & U32) -> Array<U32> & Array<U32>:
  (parent, +v) = r
  (Array.set(U32, child, (mark_base + key(v) : U32), 0), parent)

def ox1.clear.go(~key: @+x: U32 -> U32, k: Nat, st: Array<U32> & Array<U32>,
                 +idx: U32, +mark_base: U32) -> Array<U32> & Array<U32>:
  match k:
    case 0n:
      st
    case 1n+p:
      (child, parent) = st
      ox1.clear.go(~key, p, ox1.clear.w(~key, child, mark_base, Array.get(U32, parent, idx)),
                   (idx + 1 : U32), mark_base)

# --- completar o filho lendo o outro pai em ordem circular ---
# `idx_c` só anda quando o gene é escrito, então viaja no estado; `idx_p` anda
# sempre e é parâmetro comum do laço.

def ox1.fill.put(presente: Bool, child: Array<U32>, parent: Array<U32>,
                 +base: U32, +idx_c: U32, +n: U32, +v: U32) -> (Array<U32> & Array<U32>) & U32:
  match presente:
    case True{}:
      ((child, parent), idx_c)
    case False{}:
      ((Array.set(U32, child, (base + idx_c : U32), v), parent), U32.mod(U32.inc(idx_c), n))

def ox1.fill.test(parent: Array<U32>, +base: U32, +idx_c: U32, +n: U32, +v: U32,
                  r: Array<U32> & U32) -> (Array<U32> & Array<U32>) & U32:
  (child, +marca) = r
  ox1.fill.put(U32.is_ne(marca, 0), child, parent, base, idx_c, n, v)

def ox1.fill.read(~key: @+x: U32 -> U32, child: Array<U32>, +base: U32, +idx_c: U32,
                  +n: U32, +mark_base: U32, r: Array<U32> & U32) -> (Array<U32> & Array<U32>) & U32:
  (parent, +v) = r
  ox1.fill.test(parent, base, idx_c, n, v, Array.get(U32, child, (mark_base + key(v) : U32)))

def ox1.fill.step(~key: @+x: U32 -> U32, st: (Array<U32> & Array<U32>) & U32,
                  +base: U32, +idx_p: U32, +n: U32, +mark_base: U32) -> (Array<U32> & Array<U32>) & U32:
  (cp, +idx_c) = st
  (child, parent) = cp
  ox1.fill.read(~key, child, base, idx_c, n, mark_base,
                Array.get(U32, parent, (base + idx_p : U32)))

def ox1.fill.go(~key: @+x: U32 -> U32, k: Nat, st: (Array<U32> & Array<U32>) & U32,
                +base: U32, +idx_p: U32, +n: U32, +mark_base: U32) -> (Array<U32> & Array<U32>) & U32:
  match k:
    case 0n:
      st
    case 1n+p:
      ox1.fill.go(~key, p, ox1.fill.step(~key, st, base, idx_p, n, mark_base),
                  base, U32.mod(U32.inc(idx_p), n), n, mark_base)

# --- UM filho: miolo de `parent`, resto de `other` ---

def ox1.one.d(st: Array<U32> & Array<U32>, other: Array<U32>) -> (Array<U32> & Array<U32>) & Array<U32>:
  (st, other)

def ox1.one.c(~key: @+x: U32 -> U32, r: (Array<U32> & Array<U32>) & U32, parent: Array<U32>,
              +base: U32, +c1: U32, +mid_len: U32, +mark_base: U32) ->
  (Array<U32> & Array<U32>) & Array<U32>:
  (co, +idx_c) = r
  (child, other) = co
  ox1.one.d(ox1.clear.go(~key, U32.to_nat(mid_len), (child, parent), (base + c1 : U32), mark_base), other)

def ox1.one.b(~key: @+x: U32 -> U32, st: Array<U32> & Array<U32>, other: Array<U32>,
              +base: U32, +c1: U32, +mid_len: U32, +start: U32, +n: U32, +mark_base: U32) ->
  (Array<U32> & Array<U32>) & Array<U32>:
  (child, parent) = st
  ox1.one.c(~key, ox1.fill.go(~key, U32.to_nat(n), ((child, other), start), base, start, n, mark_base),
            parent, base, c1, mid_len, mark_base)

# Devolve ((filho, parent), other)
def ox1.one(~key: @+x: U32 -> U32, child: Array<U32>, parent: Array<U32>, other: Array<U32>,
            +base: U32, +c1: U32, +mid_len: U32, +start: U32, +n: U32, +mark_base: U32) ->
  (Array<U32> & Array<U32>) & Array<U32>:
  ox1.one.b(~key, ox1.mid.go(~key, U32.to_nat(mid_len), (child, parent), (base + c1 : U32), mark_base),
            other, base, c1, mid_len, start, n, mark_base)

# --- os DOIS filhos: A leva o miolo de A e o resto de B; B, o espelho ---

def ox1.two.fin(ca: Array<U32>, r: (Array<U32> & Array<U32>) & Array<U32>) ->
  (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>):
  (cbpb, pa) = r
  (cb, pb) = cbpb
  ((ca, cb), (pa, pb))

def ox1.two.b(~key: @+x: U32 -> U32, cb: Array<U32>, r: (Array<U32> & Array<U32>) & Array<U32>,
              +base: U32, +c1: U32, +mid_len: U32, +start: U32, +n: U32, +mark_base: U32) ->
  (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>):
  (capa, pb) = r
  (ca, pa) = capa
  ox1.two.fin(ca, ox1.one(~key, cb, pb, pa, base, c1, mid_len, start, n, mark_base))

def ox1.two(~key: @+x: U32 -> U32, ca: Array<U32>, cb: Array<U32>, pa: Array<U32>, pb: Array<U32>,
            +base: U32, +c1: U32, +mid_len: U32, +start: U32, +n: U32, +mark_base: U32) ->
  (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>):
  ox1.two.b(~key, cb, ox1.one(~key, ca, pa, pb, base, c1, mid_len, start, n, mark_base),
            base, c1, mid_len, start, n, mark_base)

# --- caminho SEM cruzamento: o filho é a cópia de um dos pais ---

def ox1.copy.w(ca: Array<U32>, cb: Array<U32>, +idx: U32, r: Array<U32> & U32, +vb: U32,
               pb: Array<U32>) -> (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>):
  (pa, +va) = r
  ((Array.set(U32, ca, idx, va), Array.set(U32, cb, idx, vb)), (pa, pb))

def ox1.copy.rb(ca: Array<U32>, cb: Array<U32>, pa: Array<U32>, +idx: U32,
                r: Array<U32> & U32) -> (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>):
  (pb, +vb) = r
  ox1.copy.w(ca, cb, idx, Array.get(U32, pa, idx), vb, pb)

def ox1.copy.step(st: (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>), +idx: U32) ->
  (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>):
  (filhos, pais) = st
  (ca, cb) = filhos
  (pa, pb) = pais
  ox1.copy.rb(ca, cb, pa, idx, Array.get(U32, pb, idx))

def ox1.copy.go(k: Nat, st: (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>), +idx: U32) ->
  (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>):
  match k:
    case 0n:
      st
    case 1n+p:
      ox1.copy.go(p, ox1.copy.step(st, idx), (idx + 1 : U32))

def ox1.copy.troca(st: (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>)) ->
  (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>):
  (filhos, pais) = st
  (pa, pb) = pais
  (filhos, (pb, pa))

def ox1.copy.if(inverte: Bool, ca: Array<U32>, cb: Array<U32>, pa: Array<U32>, pb: Array<U32>,
                +base: U32, +n: U32) -> (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>):
  match inverte:
    case True{}:
      ox1.copy.troca(ox1.copy.go(U32.to_nat(n), ((ca, cb), (pb, pa)), base))
    case False{}:
      ox1.copy.go(U32.to_nat(n), ((ca, cb), (pa, pb)), base)

# --- entrada pública ---

def ox1.cortes(~key: @+x: U32 -> U32, ca: Array<U32>, cb: Array<U32>, pa: Array<U32>, pb: Array<U32>,
               +base: U32, +n: U32, +mark_base: U32, +seed: U32) ->
  (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>):
  +a = R.range(seed, n)
  +b = R.range_except(R.step(seed), n, a)
  +c1 = U32.min(a, b)
  +c2 = U32.max(a, b)
  ox1.two(~key, ca, cb, pa, pb, base, c1, ((c2 - c1 : U32) + 1 : U32),
          U32.mod(U32.inc(c2), n), n, mark_base)

# OX1 na fatia [base, base + n), marcas em [mark_base, mark_base + chaves).
# Com `cruza = False{}` os filhos são cópias dos pais (um sorteio decide quem
# copia quem), que é o caminho "sem cruzamento" do motor.
def breed_ox1_slice(~key: @+x: U32 -> U32,
                    ca: Array<U32>, cb: Array<U32>, pa: Array<U32>, pb: Array<U32>,
                    +base: U32, +n: U32, +mark_base: U32, cruza: Bool, +seed: U32) ->
  (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>):
  match cruza:
    case True{}:
      ox1.cortes(~key, ca, cb, pa, pb, base, n, mark_base, R.split.fst(seed))
    case False{}:
      ox1.copy.if(R.bool(R.split.snd(seed)), ca, cb, pa, pb, base, n)

def breed_ox1(~key: @+x: U32 -> U32,
              ca: Array<U32>, cb: Array<U32>, pa: Array<U32>, pb: Array<U32>,
              +n: U32, +mark_base: U32, cruza: Bool, +seed: U32) ->
  (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>):
  breed_ox1_slice(~key, ca, cb, pa, pb, 0, n, mark_base, cruza, seed)
