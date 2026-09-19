import Base
import ./../utils/random.bend as R
import ./ga.bend as GA
import ./utils/genes.bend as V

# ================================================================
# TESTE DO MOTOR (ga.bend): elitismo, estagnação, parada
# ================================================================
# Problema de brinquedo: o genoma é um U32 e o contexto diz qual aptidão usar.
#   ctx = 0 : aptidão = o próprio gene módulo 1000 (paisagem aleatória)
#   ctx = 1 : aptidão constante 5 (nunca melhora: força a estagnação)

def init(ctx: U32, seed: U32) -> U32:
  R.mix(seed)

def fit(ctx: U32, g: U32) -> U32:
  Bool.pick(U32, U32.is_zero(ctx), U32.mod(g, 1000), 5)

def hash(ctx: U32, g: U32) -> U32:
  g

def cross(ctx: U32, a: U32, b: U32, seed: U32) -> U32 & U32:
  +a = a
  +b = b
  +m = R.mix(seed)
  (U32.xor(a, U32.and(b, m)), U32.xor(b, U32.and(a, m)))

def mutate(ctx: U32, g: U32, rate: U32, seed: U32) -> U32:
  U32.xor(g, R.mix(seed))

def ok(b: Bool) -> U32:
  Bool.to_u32(b)

def verdict(+name: String, +got: U32, +want: U32) -> String:
  "  " ++ Bool.pick(String, U32.is_eq(got, want), "[OK]     ", "[FALHOU] ") ++
  name ++ ": " ++ U32.show(got) ++ " / " ++ U32.show(want) ++ "\n"

def cfg(+max_stag: U32, +max_fit: U32) -> GA.Config:
  GA.config(R.per(9, 10), R.per(9, 10), R.per(1, 10), 3, max_stag, max_fit, 4, 0)

def run(k: Nat, +ctx: U32, +c: GA.Config, +seed: U32) -> GA.Island<U32>:
  GA.run_island(~U32, ~U32, ~init, ~fit, ~hash, ~cross, ~mutate, k,
    GA.new_island(~U32, ~U32, ~init, ~fit, ctx, c, seed), ctx, c, R.step(seed))

def gen_of(isl: GA.Island<U32>) -> GA.Gen<U32>:
  GA.Island{g, _, _, _, _, _} = isl
  g

# Elitismo: o campeão da POPULAÇÃO nunca piora de uma geração para a outra
def elitism.go(k: Nat, +isl: GA.Island<U32>, +prev: U32, +c: GA.Config, +seed: U32, +acc: U32) -> U32:
  match k:
    case 0n:
      acc
    case 1n+p:
      +next = GA.run_island(~U32, ~U32, ~init, ~fit, ~hash, ~cross, ~mutate, 1n, isl, 0, c, seed)
      +cur = GA.Gen.bfit(U32, gen_of(next))
      elitism.go(p, next, cur, c, R.split.trd(seed), (acc + ok(U32.is_ge(cur, prev)) : U32))

def elitism(+seed: U32) -> U32:
  +c = cfg(0, 0)
  +isl = GA.new_island(~U32, ~U32, ~init, ~fit, 0, c, seed)
  elitism.go(50n, isl, GA.Gen.bfit(U32, gen_of(isl)), c, R.step(seed), 0)

# Taxas efetivas: com max_stag = 100 e 75 gerações paradas, excesso = 25 de
# 50 → mutação x1,5 e torneio x0,5
def eff_ok(e: GA.Eff) -> U32:
  GA.Eff{ts, cr, mr, gr, np} = e
  (ok(U32.is_eq(U32.from_nat(ts), 5)) + ok(U32.is_eq(gr, 1500)) + ok(U32.is_eq(mr, 3000)) + ok(U32.is_eq(cr, 7)) : U32)

def eff_base(e: GA.Eff) -> U32:
  GA.Eff{ts, cr, mr, gr, np} = e
  (ok(U32.is_eq(U32.from_nat(ts), 10)) + ok(U32.is_eq(gr, 1000)) + ok(U32.is_eq(mr, 2000)) : U32)

def eff_ts(e: GA.Eff) -> Nat:
  GA.Eff{ts, _, _, _, _} = e
  ts

# Diversidade: uma população de 16 cópias do mesmo indivíduo. Com a checagem
# ligada, o primeiro (o elite) fica intacto e os 15 repetidos são remutados.
def clones(k: Nat) -> List<&2, GA.Ind<U32>>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      Con{GA.Ind{777, 5, 0}, clones(p)}

def genes_of(l: List<&2, GA.Ind<U32>>) -> List<&2, U32>:
  match l:
    case Nil{}:
      Nil{}
    case Con{i, t}:
      Con{GA.Ind.gene(U32, i), genes_of(t)}

def le(a: U32, b: U32) -> Bool:
  U32.is_le(a, b)

# Quantos valores distintos há na lista (ordena e conta as trocas de valor)
def distinct.go(l: List<&2, U32>, +prev: U32, +acc: U32) -> U32:
  match l:
    case Nil{}:
      acc
    case Con{+h, t}:
      distinct.go(t, h, (acc + Bool.to_u32(U32.is_ne(h, prev)) : U32))

def distinct.sorted(l: List<&2, U32>) -> U32:
  match l:
    case Nil{}:
      0
    case Con{+h, t}:
      distinct.go(t, h, 1)

def distinct(l: List<&2, U32>) -> U32:
  distinct.sorted(List.sort(~U32, ~le, l))

def diversified(on: Bool) -> List<&2, U32>:
  +g = GA.rebuild(U32, 4n, clones(16n), GA.Ind{0, 0, 0})
  genes_of(GA.flatten(U32, GA.Gen.pop(U32,
    GA.diversify(~U32, ~U32, ~fit, ~mutate, ~hash, on, g, 4n, 0, R.per(1, 2), 99))))

# Hash guardado: depois da passada, todo indivíduo tem o hash do SEU genoma
# (aqui `hash` é a identidade, então o guardado é max(mix(g), 1))
def hash_ok(l: List<&2, GA.Ind<U32>>) -> U32:
  match l:
    case Nil{}:
      0
    case Con{+i, t}:
      (ok(U32.is_eq(GA.Ind.hash(U32, i), U32.max(R.mix(GA.Ind.gene(U32, i)), 1))) + hash_ok(t) : U32)

def div_inds(+l: List<&2, GA.Ind<U32>>, +d: Nat) -> List<&2, GA.Ind<U32>>:
  GA.flatten(U32, GA.Gen.pop(U32,
    GA.diversify(~U32, ~U32, ~fit, ~mutate, ~hash, True{}, GA.rebuild(U32, d, l, GA.Ind{0, 0, 0}), d, 0, R.per(1, 2), 99)))

# Hash já conhecido não é recalculado: genes distintos com hashes guardados
# fictícios (k+1) saem com os mesmos hashes fictícios
def fake(k: Nat) -> List<&2, GA.Ind<U32>>:
  match k:
    case 0n:
      Nil{}
    case 1n+ +p:
      Con{GA.Ind{U32.from_nat(p), 5, U32.inc(U32.from_nat(p))}, fake(p)}

def kept_fake(l: List<&2, GA.Ind<U32>>, +k: U32) -> U32:
  match l:
    case Nil{}:
      0
    case Con{i, t}:
      (ok(U32.is_eq(GA.Ind.hash(U32, i), k)) + kept_fake(t, (k - 1 : U32)) : U32)

# Re-hash depois de remutar: com a mutação g -> g+1, [777, 777, 778] vira
# [777, 778, 779] — o terceiro repete o hash NOVO do segundo. Sem marcar o
# hash novo ficaria [777, 778, 778].
def plus1(ctx: U32, g: U32, rate: U32, seed: U32) -> U32:
  U32.inc(g)

def rh_list() -> List<&2, GA.Ind<U32>>:
  Con{GA.Ind{777, 5, 0}, Con{GA.Ind{777, 5, 0}, Con{GA.Ind{778, 5, 0}, Con{GA.Ind{1, 5, 0}, Nil{}}}}}

def rehashed() -> U32:
  +l = rh_list()
  distinct(genes_of(GA.flatten(U32, GA.Gen.pop(U32,
    GA.diversify(~U32, ~U32, ~fit, ~plus1, ~hash, True{}, GA.rebuild(U32, 2n, l, GA.Ind{0, 0, 0}), 2n, 0, 1, 7)))))

# Seleção (torneios sobre o retrato da população): as três primeiras folhas
# têm hash h (aptidões 50, 40, 30), a última tem hash h3 e aptidão 1. O índice
# desce a árvore pelo bit MENOS significativo primeiro, então as folhas em
# ordem são os índices 0, 2, 1, 3. Com torneios de 20 entre 4, o primeiro pai
# de cada par é na prática o índice 0.
def tpop(h: U32, h3: U32) -> GA.Gen<U32>:
  +h = h
  GA.rebuild(U32, 2n, Con{GA.Ind{0, 50, h}, Con{GA.Ind{1, 40, h}, Con{GA.Ind{2, 30, h}, Con{GA.Ind{3, 1, h3}, Nil{}}}}}, GA.Ind{0, 0, 0})

# Os índices dos pais de 2 pares: [a0, b0, a1, b1]
def picks(+h: U32, +h3: U32, +seed: U32) -> List<&2, U32>:
  GA.select(U32, GA.Gen.pop(U32, tpop(h, h3)), 2n, 2, 20, seed)

def at(+l: List<&2, U32>, +i: U32) -> U32:
  V.nth(U32, l, i, 99)

# Em quantos pares o segundo pai é `want` / difere do primeiro
def second_is(+l: List<&2, U32>, +want: U32) -> U32:
  (ok(U32.is_eq(at(l, 1), want)) + ok(U32.is_eq(at(l, 3), want)) : U32)

def distinct_pair(+l: List<&2, U32>) -> U32:
  (ok(U32.is_ne(at(l, 0), at(l, 1))) + ok(U32.is_ne(at(l, 2), at(l, 3))) : U32)

# Hash vindo da reprodução: depois de 3 gerações com diversity_check, todo
# indivíduo da população tem o hash do próprio genoma; sem ele, nenhum tem
# hash (0 = desconhecido)
def cfg_div(+div: U32) -> GA.Config:
  GA.config(R.per(9, 10), R.per(9, 10), R.per(1, 10), 3, 0, 0, 4, div)

def pop_after(+div: U32) -> List<&2, GA.Ind<U32>>:
  GA.flatten(U32, GA.Island.pop(U32, run(3n, 0, cfg_div(div), 17)))

def zero_hashes(l: List<&2, GA.Ind<U32>>) -> U32:
  match l:
    case Nil{}:
      0
    case Con{i, t}:
      (ok(U32.is_zero(GA.Ind.hash(U32, i))) + zero_hashes(t) : U32)

def main() -> IO(Unit):
  +c75 = GA.config(7, 2000, 1000, 10, 100, 0, 4, 0)
  IO.print(
    "=== TESTE DO MOTOR (ga.bend) ===\n" ++
    verdict("elitismo: campeão da população não piora (50 gerações x 3 sementes)",
      (elitism(11) + elitism(22) + elitism(33) : U32), 150) ++
    verdict("taxas efetivas sem estagnação", eff_base(GA.effective(c75, 10)), 3) ++
    verdict("taxas efetivas com 75 de 100 gerações paradas", eff_ok(GA.effective(c75, 75)), 4) ++
    verdict("torneio nunca abaixo de 2 (200 de 100 paradas)", U32.from_nat(eff_ts(GA.effective(c75, 200))), 2) ++
    verdict("sem controle (max_stag 0): nunca reinicia em 100 gerações",
      GA.Island.stag_start(U32, run(100n, 1, cfg(0, 0), 5)), 0) ++
    verdict("aptidão constante com max_stag 10: reinicia (stag_start > 0)",
      ok(U32.is_gt(GA.Island.stag_start(U32, run(40n, 1, cfg(10, 0), 5)), 0)), 1) ++
    verdict("o melhor sobrevive ao reinício",
      GA.Island.best_f(U32, run(40n, 1, cfg(10, 0), 5)), 5) ++
    verdict("para ao atingir max_fit (<= 900 em até 10000 gerações)",
      ok(U32.is_lt(GA.Island.generation(U32, run(10000n, 0, cfg(0, 900), 7)), 10000)), 1) ++
    verdict("diversidade desligada: 16 clones continuam 1 valor distinto", distinct(diversified(False{})), 1) ++
    verdict("diversidade ligada: 16 clones viram 16 valores distintos", distinct(diversified(True{})), 16) ++
    verdict("diversidade ligada: o elite (primeiro) fica intacto", V.nth(U32, diversified(True{}), 0, 0), 777) ++
    verdict("diversidade: todo hash guardado é o do próprio genoma (16 clones)", hash_ok(div_inds(clones(16n), 4n)), 16) ++
    verdict("diversidade: hash já guardado não é recalculado", kept_fake(div_inds(fake(16n), 4n), 16), 16) ++
    verdict("diversidade: o hash do remutado é marcado", rehashed(), 4) ++
    verdict("reprodução com diversidade: 16 filhos saem com o hash do genoma", hash_ok(pop_after(1)), 16) ++
    verdict("reprodução sem diversidade: nenhum hash calculado", zero_hashes(pop_after(0)), 16) ++
    verdict("seleção: 2 pares dão 4 índices", U32.from_nat(List.length(&2, U32, picks(9, 8, 1))), 4) ++
    verdict("seleção: o primeiro pai é o melhor (índice 0)",
      (ok(U32.is_eq(at(picks(9, 8, 1), 0), 0)) + ok(U32.is_eq(at(picks(9, 8, 2), 2), 0)) : U32), 2) ++
    verdict("seleção: o segundo pai exclui o hash do primeiro (só o 3 serve)",
      (second_is(picks(9, 8, 1), 3) + second_is(picks(9, 8, 2), 3) + second_is(picks(9, 8, 3), 3) : U32), 6) ++
    verdict("seleção: sem hash (0) exclui só o índice (vence o 2)",
      (second_is(picks(0, 0, 1), 2) + second_is(picks(0, 0, 2), 2) : U32), 4) ++
    verdict("seleção: todos com o hash excluído caem no sorteio sem o índice",
      (distinct_pair(picks(9, 9, 1)) + distinct_pair(picks(9, 9, 2)) + distinct_pair(picks(9, 9, 3)) : U32), 6) ++
    verdict("... e o melhor de fato atinge max_fit",
      ok(U32.is_ge(GA.Island.best_f(U32, run(10000n, 0, cfg(0, 900), 7)), 900)), 1)
  )

