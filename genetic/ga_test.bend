import Base
import ./../utils/random.bend as R
import ./ga.bend as GA

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

def cross(ctx: U32, a: U32, b: U32, seed: U32) -> U32:
  U32.xor(a, U32.and(b, R.mix(seed)))

def mutate(ctx: U32, g: U32, rate: U32, seed: U32) -> U32:
  U32.xor(g, R.mix(seed))

def ok(b: Bool) -> U32:
  Bool.to_u32(b)

def verdict(+name: String, +got: U32, +want: U32) -> String:
  "  " ++ Bool.pick(String, U32.is_eq(got, want), "[OK]     ", "[FALHOU] ") ++
  name ++ ": " ++ U32.show(got) ++ " / " ++ U32.show(want) ++ "\n"

def cfg(+max_stag: U32, +max_fit: U32) -> GA.Config:
  GA.config(R.per(9, 10), R.per(9, 10), R.per(1, 10), 3, max_stag, max_fit, 4)

def run(k: Nat, +ctx: U32, +c: GA.Config, +seed: U32) -> GA.Island<U32>:
  GA.run_island(~U32, ~U32, ~init, ~fit, ~cross, ~mutate, k,
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
      +next = GA.run_island(~U32, ~U32, ~init, ~fit, ~cross, ~mutate, 1n, isl, 0, c, seed)
      +cur = GA.Gen.bfit(U32, gen_of(next))
      elitism.go(p, next, cur, c, R.split.trd(seed), (acc + ok(U32.is_ge(cur, prev)) : U32))

def elitism(+seed: U32) -> U32:
  +c = cfg(0, 0)
  +isl = GA.new_island(~U32, ~U32, ~init, ~fit, 0, c, seed)
  elitism.go(50n, isl, GA.Gen.bfit(U32, gen_of(isl)), c, R.step(seed), 0)

# Taxas efetivas: com max_stag = 100 e 75 gerações paradas, excesso = 25 de
# 50 → mutação x1,5 e torneio x0,5
def eff_ok(e: GA.Eff) -> U32:
  GA.Eff{ts, cr, mr, gr} = e
  (ok(U32.is_eq(U32.from_nat(ts), 5)) + ok(U32.is_eq(gr, 1500)) + ok(U32.is_eq(mr, 3000)) + ok(U32.is_eq(cr, 7)) : U32)

def eff_base(e: GA.Eff) -> U32:
  GA.Eff{ts, cr, mr, gr} = e
  (ok(U32.is_eq(U32.from_nat(ts), 10)) + ok(U32.is_eq(gr, 1000)) + ok(U32.is_eq(mr, 2000)) : U32)

def eff_ts(e: GA.Eff) -> Nat:
  GA.Eff{ts, _, _, _} = e
  ts

def main() -> IO(Unit):
  +c75 = GA.config(7, 2000, 1000, 10, 100, 0, 4)
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
    verdict("... e o melhor de fato atinge max_fit",
      ok(U32.is_ge(GA.Island.best_f(U32, run(10000n, 0, cfg(0, 900), 7)), 900)), 1)
  )

