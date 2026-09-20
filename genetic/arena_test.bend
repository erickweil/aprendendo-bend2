import Base
import ./arena.bend as A
import ./operators.bend as Op
import ./../utils/arrays.bend as Arr
import ./../utils/tuples.bend as T
import ./../utils/random.bend as R

# Testes da arena e dos operadores de gene.
#   bend genetic/arena_test.bend --check-only
#   bend genetic/arena_test.bend -o bin/arena_test && ./bin/arena_test

# ----------------------------------------------------------------
# problema de brinquedo: genoma de 8 bits, fitness = quantos bits 1
# contexto P = número de genes
# ----------------------------------------------------------------

def GENES() -> U32:
  8

def alloc(+ctx: U32) -> Array<U32>:
  Array.new(U32, U32.to_nat(3), 0)          # 2^3 = 8 genes

# preenche com bits aleatórios
def init_gene(v: U32, +seed: U32, i: U32) -> U32:
  R.range(R.split.fst((seed + (i * 2654435761 : U32) : U32)), 2)

def init(+ctx: U32, g: Array<U32>, +seed: U32) -> Array<U32>:
  Arr.for_each(~U32, ~U32, ~init_gene, g, seed)

def count_bit(+x: U32, acc: U32, i: U32) -> U32:
  (acc + x : U32)

# fitness: +1 para nunca ser 0 (0 significa "não avaliado")
def fitness.fin(r: Array<U32> & U32) -> Array<U32> & U32:
  (g, +s) = r
  (g, U32.inc(s))

def fitness(+ctx: U32, g: Array<U32>) -> Array<U32> & U32:
  fitness.fin(Arr.reduce(~U32, ~U32, ~count_bit, g, 0))

# ----------------------------------------------------------------
# mostrar
# ----------------------------------------------------------------

def show_ind.fin(s: String, +fit: U32, +hash: U32) -> A.Individual<Array<U32>> & String:
  (A.Individual{[0 : U32*1n], fit, hash}, s ++ " fit=" ++ U32.show(fit))

# ATENÇÃO: esta callback devolve um indivíduo de MENTIRA (genoma de 1 gene) no
# lugar do original, para poder mostrá-lo. Serve só para teste, e cada slot só
# pode ser mostrado uma vez.
def show_ind(ind: A.Individual<Array<U32>>, +ctx: U32, +at: U32) -> A.Individual<Array<U32>> & String:
  match ind:
    case A.Individual{gene, +fit, +hash}:
      show_ind.fin(Arr.show(~U32, ~U32.show, gene), fit, hash)

def show_slot(p: A.Pop<Array<U32>>, +i: U32) -> A.Pop<Array<U32>> & String:
  A.read1(~Array<U32>, ~U32, ~String, ~show_ind, p, i, 0)

# o mesmo, no arranjo da PRÓXIMA geração
def show_slot_nxt(p: A.Pop<Array<U32>>, +i: U32) -> A.Pop<Array<U32>> & String:
  A.read1_nxt(~Array<U32>, ~U32, ~String, ~show_ind, p, i, 0)

# ----------------------------------------------------------------
# testes
# ----------------------------------------------------------------

# soma dos fitness de todos os slots, lendo com fit_at (a primitiva do torneio)
def soma_fits.go(k: Nat, st: A.Pop<Array<U32>> & U32, +i: U32, +acc: U32) -> A.Pop<Array<U32>> & U32:
  match k:
    case 0n:
      (p, +f) = st
      (p, (acc + f : U32))
    case 1n+q:
      (p, +f) = st
      soma_fits.go(q, A.fit_at(~Array<U32>, p, (i + 1 : U32)), (i + 1 : U32), (acc + f : U32))

def soma_fits(p: A.Pop<Array<U32>>, +n: U32) -> A.Pop<Array<U32>> & U32:
  soma_fits.go(U32.to_nat((n - 1 : U32)), A.fit_at(~Array<U32>, p, 0), 0, 0)

# a população avaliada: 4 slots de 8 bits
def pop_avaliada() -> A.Pop<Array<U32>> & (U32 & U32):
  A.evaluate(~Array<U32>, ~U32, ~fitness,
    A.pop_new(~Array<U32>, ~U32, ~alloc, ~init, 2n, GENES(), 12345), GENES())

# 1) a soma dos fitness lidos por fit_at bate com o melhor acumulado na avaliação
def teste_avaliacao.fin(r: A.Pop<Array<U32>> & U32, best: U32 & U32) -> String:
  (p, +soma) = r
  (+bi, +bf) = best
  "soma_fits=" ++ U32.show(soma) ++ " melhor=slot" ++ U32.show(bi) ++ " fit=" ++ U32.show(bf)

def teste_avaliacao.go(r: A.Pop<Array<U32>> & (U32 & U32)) -> String:
  (p, best) = r
  teste_avaliacao.fin(soma_fits(p, 4), best)

def teste_avaliacao() -> String:
  teste_avaliacao.go(pop_avaliada())

# 2) at4 "4 entram, 4 saem": dois pais em `cur`, dois filhos em `nxt`,
#    com corte fixo em 4 num genoma de 8
def cruza.fin(r: (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>)) ->
  (A.Individual<Array<U32>> & A.Individual<Array<U32>>) & (A.Individual<Array<U32>> & A.Individual<Array<U32>>):
  (filhos, pais) = r
  (ga, gb) = filhos
  (gpa, gpb) = pais
  ((A.Individual{ga, 0, 0}, A.Individual{gb, 0, 0}),
   (A.Individual{gpa, 1, 0}, A.Individual{gpb, 1, 0}))

def cruza(ija: A.Individual<Array<U32>>, ijb: A.Individual<Array<U32>>,
          ipa: A.Individual<Array<U32>>, ipb: A.Individual<Array<U32>>, +ctx: U32) ->
  (A.Individual<Array<U32>> & A.Individual<Array<U32>>) & (A.Individual<Array<U32>> & A.Individual<Array<U32>>):
  match ija ijb ipa ipb:
    case A.Individual{ga, fa, ha} A.Individual{gb, fb, hb} A.Individual{gpa, fpa, hpa} A.Individual{gpb, fpb, hpb}:
      cruza.fin(Op.breed_1point(~U32, ga, gb, gpa, gpb, 8, True{}, 42))

def teste_at4.mostra(p: A.Pop<Array<U32>>) -> String:
  T.with(A.Pop<Array<U32>>, String, String, show_slot_nxt(p, 0), p2 => s0 =>
  T.with(A.Pop<Array<U32>>, String, String, show_slot_nxt(p2, 1), p3 => s1 =>
    "filho0=" ++ s0 ++ "  filho1=" ++ s1))

def teste_at4.go(r: A.Pop<Array<U32>> & (U32 & U32)) -> String:
  (p, best) = r
  teste_at4.mostra(A.at4(~Array<U32>, ~U32, ~cruza, p, 0, 1, 0, 1, 0))

def teste_at4() -> String:
  teste_at4.go(pop_avaliada())

# 3) os slots como saíram do pop_new, antes de qualquer cruzamento
def teste_slots.mostra(p: A.Pop<Array<U32>>) -> String:
  T.with(A.Pop<Array<U32>>, String, String, show_slot(p, 0), p2 => s0 =>
  T.with(A.Pop<Array<U32>>, String, String, show_slot(p2, 1), p3 => s1 =>
    "slot0=" ++ s0 ++ "  slot1=" ++ s1))

def teste_slots.go(r: A.Pop<Array<U32>> & (U32 & U32)) -> String:
  (p, best) = r
  teste_slots.mostra(p)

def teste_slots() -> String:
  teste_slots.go(pop_avaliada())

def um(v: U32, +c: U32, i: U32) -> U32:
  1

def idx(v: U32, +c: U32, i: U32) -> U32:
  i

# 4) operadores de gene isolados
def genoma_a() -> Array<U32>:
  Arr.for_each(~U32, ~U32, ~um, [0 : U32*8n], 0)

def genoma_b() -> Array<U32>:
  [0 : U32*8n]

def mostra2(r: Array<U32> & Array<U32>) -> String:
  (a, b) = r
  "a=" ++ Arr.show(~U32, ~U32.show, a) ++ " b=" ++ Arr.show(~U32, ~U32.show, b)

def teste_uniforme() -> String:
  mostra2(Op.cross_uniform(genoma_a(), genoma_b(), 8, R.per(1, 2), 987654321))

def teste_2pontos() -> String:
  mostra2(Op.cross_2point(genoma_a(), genoma_b(), 8, 987654321))

def teste_1ponto() -> String:
  mostra2(Op.cross_1point(genoma_a(), genoma_b(), 8, 42))

def teste_mut() -> String:
  Arr.show(~U32, ~U32.show, Op.mut_replace(genoma_b(), 8, 2, R.per(1, 4), 555))

def teste_mut_swap() -> String:
  Arr.show(~U32, ~U32.show, Op.mut_swap(Arr.for_each(~U32, ~U32, ~idx, [0 : U32*8n], 0), 8, 3, 777))

def key_u32(+x: U32) -> U32:
  x

def rev_idx(v: U32, +c: U32, i: U32) -> U32:
  (7 - i : U32)

def teste_ox1.fin(r: (Array<U32> & Array<U32>) & (Array<U32> & Array<U32>)) -> String:
  (filhos, _) = r
  (ca, cb) = filhos
  "ca=" ++ Arr.show(~U32, ~U32.show, ca) ++ " cb=" ++ Arr.show(~U32, ~U32.show, cb)

def teste_ox1() -> String:
  pa = Arr.for_each(~U32, ~U32, ~idx, [0 : U32*8n], 0)
  pb = Arr.for_each(~U32, ~U32, ~rev_idx, [0 : U32*8n], 0)
  ca = [0 : U32*8n]
  cb = [0 : U32*8n]
  teste_ox1.fin(Op.breed_ox1(~U32, ~key_u32, ca, cb, pa, pb, 8, True{}, 12345))

def check(rot: String, +obtido: String, +esperado: String) -> String:
  +ok = String.eq(obtido, esperado)
  Bool.pick(String, ok, "  ok    ", "  FALHA ") ++ rot ++ ": " ++ obtido ++
    Bool.pick(String, ok, "", "\n          esperado: " ++ esperado)

def main() -> IO(Unit):
  do IO<Unit>:
    u : Unit <- IO.print("== arena ==")
    u : Unit <- IO.print(check("pop_new + init (4 slots de 8 bits)", teste_slots(),
      "slot0=[1, 1, 1, 1, 0, 1, 1, 0] fit=7  slot1=[1, 0, 1, 1, 1, 0, 1, 0] fit=6"))
    u : Unit <- IO.print(check("evaluate: soma por fit_at e melhor acumulado", teste_avaliacao(),
      "soma_fits=21 melhor=slot0 fit=7"))
    u : Unit <- IO.print(check("at4: 2 pais em cur -> 2 filhos em nxt (corte 1)", teste_at4(),
      "filho0=[1, 0, 1, 1, 1, 0, 1, 0] fit=0  filho1=[1, 1, 1, 1, 0, 1, 1, 0] fit=0"))
    u : Unit <- IO.print("== operadores de gene ==")
    u : Unit <- IO.print(check("cross_1point (corte sorteado = 1)", teste_1ponto(),
      "a=[1, 0, 0, 0, 0, 0, 0, 0] b=[0, 1, 1, 1, 1, 1, 1, 1]"))
    u : Unit <- IO.print("  (informativo) cross_2point:  " ++ teste_2pontos())
    u : Unit <- IO.print(check("cross_uniform (metade a metade)", teste_uniforme(),
      "a=[0, 1, 0, 1, 1, 1, 1, 1] b=[1, 0, 1, 0, 0, 0, 0, 0]"))
    u : Unit <- IO.print(check("mut_replace (taxa 1/4, 8 genes)", teste_mut(),
      "[0, 0, 0, 1, 0, 0, 0, 0]"))
    u : Unit <- IO.print(check("mut_swap (3 trocas, preserva o multiconjunto)", teste_mut_swap(),
      "[1, 3, 2, 5, 4, 0, 6, 7]"))
    IO.print("  (informativo) breed_ox1:     " ++ teste_ox1())
