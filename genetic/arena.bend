import Base
import ./../utils/arrays.bend as Arr
import ./../utils/tuples.bend as T
import ./../utils/random.bend as R

# ================================================================
# ARENA (arena.bend)
# ================================================================
# A população vive num `Array<Individual<G>>` alocado na largada e nunca
# realocado. Uma geração só faz `Array.swap` sobre o que já existe.
#
# `Individual` é um registro LINEAR: guarda o genoma (que é `Type`, logo tem um
# dono só) ao lado dos metadados. Ler um campo é O(1): desestrutura e
# reconstrói (medido: 3 ns por leitura, contando o empréstimo no array).
#
# `Pop` carrega, junto com o array:
#   - DOIS buracos (`h1`, `h2`): para tirar um indivíduo do array é preciso pôr
#     algo no lugar (`Array.swap` é o `mem::replace` do Rust). Dois buracos
#     permitem ter dois slots fora ao mesmo tempo, que é o que o cruzamento
#     precisa. Eles circulam: saem e voltam em cada operação, sem alocar.
#   - `size`: o número de slots. Guardado na mão porque `Array.size` é O(log n)
#     e a arena não pode ser medida com um slot emprestado (o buraco tem outra
#     profundidade).
#
# PRIMITIVAS (todas com 2 ou 4 swaps, sem alocação):
#   at1    aplica f ao indivíduo do slot i
#   read1  aplica f ao slot i e devolve também um valor
#   at2    aplica f aos slots i e j (i != j)
#   evaluate  uma passada avaliando quem ainda não tem fitness
# ================================================================

type Individual<-G: Type> is Type:
  Individual{gene: G, fit: U32, hash: U32}

# DOIS arranjos: `cur` é a geração atual (só se lê dela) e `nxt` é a próxima
# (só se escreve nela). No fim da geração os dois trocam de papel, o que é uma
# troca de handle — O(1). É o modelo geracional clássico, o mesmo do motor em
# Rust: um filho só vira pai na geração seguinte.
#
# Custo: 2× memória. Em troca, a reprodução nunca lê o que já escreveu, os
# filhos são escritos em slots SEQUENCIAIS (boa localidade) e não é preciso
# escolher vítima nenhuma.
#
# Quatro buracos: dois pais (em `cur`) e dois filhos (em `nxt`) ficam fora dos
# arranjos ao mesmo tempo.
type Pop<-G: Type> is Type:
  Pop{cur: Array<Individual<G>>, nxt: Array<Individual<G>>,
      h1: Individual<G>, h2: Individual<G>, h3: Individual<G>, h4: Individual<G>,
      size: U32}

# ----------------------------------------------------------------
# CONSTRUIR
# ----------------------------------------------------------------

# fit = 0 significa "não avaliado"; hash = 0, "desconhecido"
def fresh(~G: Type, gene: G) -> Individual<G>:
  Individual{gene, 0, 0}

# Esqueleto de um arranjo: 2^d slots, cada um com um genoma criado por `alloc`
# e preenchido por `init` com uma semente própria. Recursão comum (não
# `from_fn`: o `~f` de um template não pode capturar `ctx`, que vem de
# argumento), com chamada paralela nos dois lados.
def pop_build(~G: Type, ~P: Data, ~alloc: @+c: P -> G, ~init: @+c: P -> G -> @+s: U32 -> G,
              d: Nat, +ctx: P, +seed: U32) -> Array<Individual<G>>:
  match d:
    case 0n:
      ALeaf{fresh(~G, init(ctx, alloc(ctx), seed))}
    case 1n+ +p:
      l r = pop_build(~G, ~P, ~alloc, ~init, p, ctx, R.split.fst(seed)) pop_build(~G, ~P, ~alloc, ~init, p, ctx, R.split.snd(seed))
      ANode{l, r}

# A população pronta: os dois arranjos de 2^d indivíduos e os quatro buracos.
# O arranjo `nxt` nasce preenchido (será todo sobrescrito na primeira geração).
def pop_new(~G: Type, ~P: Data, ~alloc: @+c: P -> G, ~init: @+c: P -> G -> @+s: U32 -> G,
            +d: Nat, +ctx: P, +seed: U32) -> Pop<G>:
  Pop{pop_build(~G, ~P, ~alloc, ~init, d, ctx, R.split.trd(seed)),
      pop_build(~G, ~P, ~alloc, ~init, d, ctx, R.split.fth(seed)),
      fresh(~G, alloc(ctx)), fresh(~G, alloc(ctx)),
      fresh(~G, alloc(ctx)), fresh(~G, alloc(ctx)),
      U32.shln(1, d)}

# ----------------------------------------------------------------
# ACESSO A UM SLOT
# ----------------------------------------------------------------
# `slot1` é o núcleo: empresta o slot `i` de UM arranjo usando o buraco dado,
# aplica `f` e devolve (arranjo, buraco) e o valor que `f` produziu. As duas
# versões públicas só dizem de qual arranjo se trata.

def slot1.put(~G: Type, ~S: Type, r: Array<Individual<G>> & Individual<G>, value: S) ->
  (Array<Individual<G>> & Individual<G>) & S:
  (arr, hole) = r
  ((arr, hole), value)

def slot1.split(~G: Type, ~S: Type, arr: Array<Individual<G>>, r: Individual<G> & S, +i: U32) ->
  (Array<Individual<G>> & Individual<G>) & S:
  (ind, value) = r
  slot1.put(~G, ~S, Array.swap(Individual<G>, arr, i, ind), value)

def slot1(~G: Type, ~C: Data, ~S: Type, ~f: Individual<G> -> @+c: C -> @+at: U32 -> (Individual<G> & S),
          r: Array<Individual<G>> & Individual<G>, +i: U32, +ctx: C) ->
  (Array<Individual<G>> & Individual<G>) & S:
  (arr, ind) = r
  slot1.split(~G, ~S, arr, f(ind, ctx, i), i)

# --- no arranjo ATUAL (`cur`), com o buraco h1 ---

def read1.fin(~G: Type, ~S: Type, r: (Array<Individual<G>> & Individual<G>) & S,
              nxt: Array<Individual<G>>, h2: Individual<G>, h3: Individual<G>, h4: Individual<G>,
              +size: U32) -> Pop<G> & S:
  (ah, value) = r
  (arr, h1) = ah
  (Pop{arr, nxt, h1, h2, h3, h4, size}, value)

def read1(~G: Type, ~C: Data, ~S: Type, ~f: Individual<G> -> @+c: C -> @+at: U32 -> (Individual<G> & S),
          p: Pop<G>, +i: U32, +ctx: C) -> Pop<G> & S:
  match p:
    case Pop{cur, nxt, h1, h2, h3, h4, +size}:
      read1.fin(~G, ~S, slot1(~G, ~C, ~S, ~f, Array.swap(Individual<G>, cur, i, h1), i, ctx),
                nxt, h2, h3, h4, size)

# --- no arranjo da PRÓXIMA geração (`nxt`), com o buraco h3 ---

def read1_nxt.fin(~G: Type, ~S: Type, r: (Array<Individual<G>> & Individual<G>) & S,
                  cur: Array<Individual<G>>, h1: Individual<G>, h2: Individual<G>, h4: Individual<G>,
                  +size: U32) -> Pop<G> & S:
  (ah, value) = r
  (arr, h3) = ah
  (Pop{cur, arr, h1, h2, h3, h4, size}, value)

def read1_nxt(~G: Type, ~C: Data, ~S: Type, ~f: Individual<G> -> @+c: C -> @+at: U32 -> (Individual<G> & S),
              p: Pop<G>, +i: U32, +ctx: C) -> Pop<G> & S:
  match p:
    case Pop{cur, nxt, h1, h2, h3, h4, +size}:
      read1_nxt.fin(~G, ~S, slot1(~G, ~C, ~S, ~f, Array.swap(Individual<G>, nxt, i, h3), i, ctx),
                    cur, h1, h2, h4, size)

# aplica f ao slot i de `cur` sem devolver valor (usado pelo reinício)
def at1.drop(~G: Type, r: Pop<G> & U32) -> Pop<G>:
  (p, +v) = r
  p

def at1(~G: Type, ~C: Data, ~f: Individual<G> -> @+c: C -> @+at: U32 -> (Individual<G> & U32),
        p: Pop<G>, +i: U32, +ctx: C) -> Pop<G>:
  at1.drop(~G, read1(~G, ~C, ~U32, ~f, p, i, ctx))

# ----------------------------------------------------------------
# at4: dois pais em `cur`, dois filhos em `nxt` (8 swaps)
# ----------------------------------------------------------------
# É o "4 entram, 4 saem": o operador do problema lê os dois pais e escreve os
# dois filhos numa varredura só. Como pais e filhos vivem em arranjos
# diferentes, a única condição é `pa != pb` (com pa == pb o segundo empréstimo
# tiraria o buraco do slot como se fosse indivíduo).

def at4.p4(~G: Type, r: Array<Individual<G>> & Individual<G>, cur: Array<Individual<G>>,
           h1: Individual<G>, h2: Individual<G>, h3: Individual<G>, +size: U32) -> Pop<G>:
  (nxt, h4) = r
  Pop{cur, nxt, h1, h2, h3, h4, size}

def at4.p3(~G: Type, r: Array<Individual<G>> & Individual<G>, cur: Array<Individual<G>>,
           h1: Individual<G>, h2: Individual<G>, nb: Individual<G>, +jb: U32, +size: U32) -> Pop<G>:
  (nxt, h3) = r
  at4.p4(~G, Array.swap(Individual<G>, nxt, jb, nb), cur, h1, h2, h3, size)

def at4.p2(~G: Type, r: Array<Individual<G>> & Individual<G>, h1: Individual<G>,
           nxt: Array<Individual<G>>, na: Individual<G>, nb: Individual<G>,
           +ja: U32, +jb: U32, +size: U32) -> Pop<G>:
  (cur, h2) = r
  at4.p3(~G, Array.swap(Individual<G>, nxt, ja, na), cur, h1, h2, nb, jb, size)

def at4.p1(~G: Type, r: Array<Individual<G>> & Individual<G>, npb: Individual<G>,
           nxt: Array<Individual<G>>, na: Individual<G>, nb: Individual<G>,
           +pb: U32, +ja: U32, +jb: U32, +size: U32) -> Pop<G>:
  (cur, h1) = r
  at4.p2(~G, Array.swap(Individual<G>, cur, pb, npb), h1, nxt, na, nb, ja, jb, size)

def at4.split(~G: Type, cur: Array<Individual<G>>, nxt: Array<Individual<G>>,
              r: (Individual<G> & Individual<G>) & (Individual<G> & Individual<G>),
              +pa: U32, +pb: U32, +ja: U32, +jb: U32, +size: U32) -> Pop<G>:
  (filhos, pais) = r
  (na, nb) = filhos
  (npa, npb) = pais
  at4.p1(~G, Array.swap(Individual<G>, cur, pa, npa), npb, nxt, na, nb, pb, ja, jb, size)

def at4.call(~G: Type, ~C: Data,
             ~f: Individual<G> -> Individual<G> -> Individual<G> -> Individual<G> -> @+c: C -> ((Individual<G> & Individual<G>) & (Individual<G> & Individual<G>)),
             r: Array<Individual<G>> & Individual<G>, cur: Array<Individual<G>>,
             ipa: Individual<G>, ipb: Individual<G>, ija: Individual<G>,
             +pa: U32, +pb: U32, +ja: U32, +jb: U32, +ctx: C, +size: U32) -> Pop<G>:
  (nxt, ijb) = r
  at4.split(~G, cur, nxt, f(ija, ijb, ipa, ipb, ctx), pa, pb, ja, jb, size)

def at4.take_jb(~G: Type, ~C: Data,
                ~f: Individual<G> -> Individual<G> -> Individual<G> -> Individual<G> -> @+c: C -> ((Individual<G> & Individual<G>) & (Individual<G> & Individual<G>)),
                r: Array<Individual<G>> & Individual<G>, cur: Array<Individual<G>>,
                ipa: Individual<G>, ipb: Individual<G>, h4: Individual<G>,
                +pa: U32, +pb: U32, +ja: U32, +jb: U32, +ctx: C, +size: U32) -> Pop<G>:
  (nxt, ija) = r
  at4.call(~G, ~C, ~f, Array.swap(Individual<G>, nxt, jb, h4), cur, ipa, ipb, ija, pa, pb, ja, jb, ctx, size)

def at4.take_ja(~G: Type, ~C: Data,
                ~f: Individual<G> -> Individual<G> -> Individual<G> -> Individual<G> -> @+c: C -> ((Individual<G> & Individual<G>) & (Individual<G> & Individual<G>)),
                r: Array<Individual<G>> & Individual<G>, nxt: Array<Individual<G>>,
                ipa: Individual<G>, h3: Individual<G>, h4: Individual<G>,
                +pa: U32, +pb: U32, +ja: U32, +jb: U32, +ctx: C, +size: U32) -> Pop<G>:
  (cur, ipb) = r
  at4.take_jb(~G, ~C, ~f, Array.swap(Individual<G>, nxt, ja, h3), cur, ipa, ipb, h4, pa, pb, ja, jb, ctx, size)

def at4.take_pb(~G: Type, ~C: Data,
                ~f: Individual<G> -> Individual<G> -> Individual<G> -> Individual<G> -> @+c: C -> ((Individual<G> & Individual<G>) & (Individual<G> & Individual<G>)),
                r: Array<Individual<G>> & Individual<G>, nxt: Array<Individual<G>>,
                h2: Individual<G>, h3: Individual<G>, h4: Individual<G>,
                +pa: U32, +pb: U32, +ja: U32, +jb: U32, +ctx: C, +size: U32) -> Pop<G>:
  (cur, ipa) = r
  at4.take_ja(~G, ~C, ~f, Array.swap(Individual<G>, cur, pb, h2), nxt, ipa, h3, h4, pa, pb, ja, jb, ctx, size)

def at4.open(~G: Type, ~C: Data,
             ~f: Individual<G> -> Individual<G> -> Individual<G> -> Individual<G> -> @+c: C -> ((Individual<G> & Individual<G>) & (Individual<G> & Individual<G>)),
             p: Pop<G>, +pa: U32, +pb: U32, +ja: U32, +jb: U32, +ctx: C) -> Pop<G>:
  match p:
    case Pop{cur, nxt, h1, h2, h3, h4, +size}:
      at4.take_pb(~G, ~C, ~f, Array.swap(Individual<G>, cur, pa, h1), nxt, h2, h3, h4, pa, pb, ja, jb, ctx, size)

def at4.if(~G: Type, ~C: Data,
           ~f: Individual<G> -> Individual<G> -> Individual<G> -> Individual<G> -> @+c: C -> ((Individual<G> & Individual<G>) & (Individual<G> & Individual<G>)),
           distintos: Bool, p: Pop<G>, +pa: U32, +pb: U32, +ja: U32, +jb: U32, +ctx: C) -> Pop<G>:
  match distintos:
    case True{}:
      at4.open(~G, ~C, ~f, p, pa, pb, ja, jb, ctx)
    case False{}:
      p

def at4(~G: Type, ~C: Data,
        ~f: Individual<G> -> Individual<G> -> Individual<G> -> Individual<G> -> @+c: C -> ((Individual<G> & Individual<G>) & (Individual<G> & Individual<G>)),
        p: Pop<G>, +pa: U32, +pb: U32, +ja: U32, +jb: U32, +ctx: C) -> Pop<G>:
  at4.if(~G, ~C, ~f, U32.is_ne(pa, pb), p, pa, pb, ja, jb, ctx)

# ----------------------------------------------------------------
# TROCA DE GERAÇÃO E ELITISMO
# ----------------------------------------------------------------

# O que era `nxt` vira `cur`: troca de handle, O(1)
def swap_gen(~G: Type, p: Pop<G>) -> Pop<G>:
  match p:
    case Pop{cur, nxt, h1, h2, h3, h4, +size}:
      Pop{nxt, cur, h1, h2, h3, h4, size}

# O elite ANDA para a próxima geração: troca o slot `best` de `cur` com o slot
# 0 de `nxt`. Nenhum gene copiado — o registro inteiro muda de lugar, com o
# fitness junto.
def elite.fin(~G: Type, r: Array<Individual<G>> & Individual<G>,
              nxt: Array<Individual<G>>, h2: Individual<G>, h3: Individual<G>, h4: Individual<G>,
              +size: U32) -> Pop<G>:
  (cur, h1) = r
  Pop{cur, nxt, h1, h2, h3, h4, size}

def elite.put(~G: Type, r: Array<Individual<G>> & Individual<G>, cur: Array<Individual<G>>,
              h2: Individual<G>, h3: Individual<G>, h4: Individual<G>, +best: U32, +size: U32) -> Pop<G>:
  (nxt, velho) = r
  elite.fin(~G, Array.swap(Individual<G>, cur, best, velho), nxt, h2, h3, h4, size)

def elite.take(~G: Type, r: Array<Individual<G>> & Individual<G>, nxt: Array<Individual<G>>,
               h2: Individual<G>, h3: Individual<G>, h4: Individual<G>, +best: U32, +size: U32) -> Pop<G>:
  (cur, campeao) = r
  elite.put(~G, Array.swap(Individual<G>, nxt, 0, campeao), cur, h2, h3, h4, best, size)

def elite_to_nxt(~G: Type, p: Pop<G>, +best: U32) -> Pop<G>:
  match p:
    case Pop{cur, nxt, h1, h2, h3, h4, +size}:
      elite.take(~G, Array.swap(Individual<G>, cur, best, h1), nxt, h2, h3, h4, best, size)

# ----------------------------------------------------------------
# LER O FITNESS (a primitiva do torneio)
# ----------------------------------------------------------------

def peek_fit(~G: Type, ind: Individual<G>, +ctx: U32, +at: U32) -> Individual<G> & U32:
  match ind:
    case Individual{gene, +fit, hash}:
      (Individual{gene, fit, hash}, fit)

def fit_at(~G: Type, p: Pop<G>, +i: U32) -> Pop<G> & U32:
  read1(~G, ~U32, ~U32, ~peek_fit(~G), p, i, 0)

# ----------------------------------------------------------------
# ACESSO AO TAMANHO
# ----------------------------------------------------------------

def size_of(~G: Type, p: Pop<G>) -> Pop<G> & U32:
  match p:
    case Pop{cur, nxt, h1, h2, h3, h4, +size}:
      (Pop{cur, nxt, h1, h2, h3, h4, size}, size)

def peek_hash(~G: Type, ind: Individual<G>, +ctx: U32, +at: U32) -> Individual<G> & U32:
  match ind:
    case Individual{gene, fit, +hash}:
      (Individual{gene, fit, hash}, hash)

# o hash guardado do slot i (0 = desconhecido). É a leitura da passada de
# diversidade, do mesmo custo da leitura de fitness do torneio.
def hash_at(~G: Type, p: Pop<G>, +i: U32) -> Pop<G> & U32:
  read1(~G, ~U32, ~U32, ~peek_hash(~G), p, i, 0)

# ----------------------------------------------------------------
# AVALIAÇÃO
# ----------------------------------------------------------------
# Uma passada pelos slots: quem tem fit = 0 é avaliado. Preserva a ordem (2
# swaps por slot). O custo da passada é dominado pelo fitness do problema, que
# é O(genoma) — a travessia em si é ~1 ns por indivíduo.

def eval_one.put(~G: Type, r: G & U32, +hash: U32) -> Individual<G> & U32:
  (gene, +f) = r
  (Individual{gene, f, hash}, f)

def eval_one.if(~G: Type, ~P: Data, ~fitness: @+c: P -> G -> (G & U32),
                unevaluated: Bool, gene: G, +fit: U32, +hash: U32, +ctx: P) -> Individual<G> & U32:
  match unevaluated:
    case True{}:
      eval_one.put(~G, fitness(ctx, gene), hash)
    case False{}:
      (Individual{gene, fit, hash}, fit)

# Avalia se ainda não foi avaliado, e devolve o indivíduo com a aptidão
def eval_one(~G: Type, ~P: Data, ~fitness: @+c: P -> G -> (G & U32),
             ind: Individual<G>, +ctx: P, +at: U32) -> Individual<G> & U32:
  match ind:
    case Individual{gene, +fit, hash}:
      eval_one.if(~G, ~P, ~fitness, U32.is_zero(fit), gene, fit, hash, ctx)

# melhor entre o acumulado e o slot i. Uma tupla é `Type`, então não aceita `+`:
# os escalares são escolhidos separadamente, sem montar tupla descartada.
def eval.best(best: U32 & U32, +i: U32, +fit: U32) -> U32 & U32:
  (+bi, +bf) = best
  +better = U32.is_gt(fit, bf)
  (Bool.pick(U32, better, i, bi), Bool.pick(U32, better, fit, bf))

def eval.step(~G: Type, st: Pop<G> & U32, best: U32 & U32, +i: U32) -> Pop<G> & (U32 & U32):
  (p, +fit) = st
  (p, eval.best(best, i, fit))

def eval.go(~G: Type, ~P: Data, ~fitness: @+c: P -> G -> (G & U32),
            k: Nat, st: Pop<G> & (U32 & U32), +ctx: P, +i: U32) -> Pop<G> & (U32 & U32):
  match k:
    case 0n:
      st
    case 1n+p:
      (pop, best) = st
      eval.go(~G, ~P, ~fitness, p,
        eval.step(~G, read1(~G, ~P, ~U32, ~eval_one(~G, ~P, ~fitness), pop, i, ctx), best, i),
        ctx, (i + 1 : U32))

def evaluate.start(~G: Type, ~P: Data, ~fitness: @+c: P -> G -> (G & U32),
                   r: Pop<G> & U32, +ctx: P) -> Pop<G> & (U32 & U32):
  (p, +n) = r
  eval.go(~G, ~P, ~fitness, U32.to_nat(n), (p, T.pair(U32, U32, 0, 0)), ctx, 0)

# Avalia a população inteira e devolve (população, (índice do melhor, aptidão do
# melhor)). O tamanho sai do próprio `Pop`.
#
# ⚠️ O fitness do problema NUNCA pode devolver 0: 0 é a marca de "não
# avaliado". Some 1 se o mínimo real for zero.
def evaluate(~G: Type, ~P: Data, ~fitness: @+c: P -> G -> (G & U32),
             p: Pop<G>, +ctx: P) -> Pop<G> & (U32 & U32):
  evaluate.start(~G, ~P, ~fitness, size_of(~G, p), ctx)

