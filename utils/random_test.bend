import Base
import ./random.bend as R

# ================================================================
# TESTE DO GERADOR (random.bend)
# ================================================================
# Estatísticas com 1 milhão de amostras; as faixas aceitas são ~5 desvios-
# padrão, então uma falha indica viés real, não azar.

def ok(b: Bool) -> U32:
  Bool.to_u32(b)

def verdict(+name: String, +got: U32, +want: U32) -> String:
  "  " ++ Bool.pick(String, U32.is_eq(got, want), "[OK]     ", "[FALHOU] ") ++
  name ++ ": " ++ U32.show(got) ++ " / " ++ U32.show(want) ++ "\n"

def between(+x: U32, +lo: U32, +hi: U32) -> U32:
  ok(Bool.and(U32.is_ge(x, lo), U32.is_le(x, hi)))

# Quantos acertos em `k` sorteios encadeados a partir de `s`
def hits(k: Nat, +thr: U32, +s: U32, +acc: U32) -> U32:
  match k:
    case 0n:
      acc
    case 1n+p:
      hits(p, thr, R.step(s), (acc + Bool.to_u32(R.hit(s, thr)) : U32))

# Quantas vezes `range(s, 10)` cai no balde `b`
def bucket(k: Nat, +b: U32, +s: U32, +acc: U32) -> U32:
  match k:
    case 0n:
      acc
    case 1n+p:
      bucket(p, b, R.step(s), (acc + Bool.to_u32(U32.is_eq(R.range(s, 10), b)) : U32))

# Quantas vezes `range_except(s, 10, 3)` devolve `b`
def except_bucket(k: Nat, +b: U32, +s: U32, +acc: U32) -> U32:
  match k:
    case 0n:
      acc
    case 1n+p:
      except_bucket(p, b, R.step(s), (acc + Bool.to_u32(U32.is_eq(R.range_except(s, 10, 3), b)) : U32))

def sum_gap(k: Nat, +thr: U32, +lnq: F32, +s: U32, +acc: F32) -> F32:
  match k:
    case 0n:
      acc
    case 1n+p:
      sum_gap(p, thr, lnq, R.step(s), (acc + U32.to_f32(R.gap(s, thr, lnq)) : F32))

# Média do salto geométrico x 100 (esperado: (1 - p) / p)
def mean_gap100(+thr: U32) -> U32:
  F32.to_u32(((sum_gap(1000000n, thr, R.ln_miss(thr), 99, {0.0 : F32}) / {1000000.0 : F32}) * {100.0 : F32} : F32))

def sum_poisson(k: Nat, +lambda: F32, +s: U32, +acc: U32) -> U32:
  match k:
    case 0n:
      acc
    case 1n+p:
      # split.trd, não step: o Poisson já avança o fluxo com step por dentro, e
      # amostras encadeadas por step se sobreporiam (Armadilha 9)
      sum_poisson(p, lambda, R.split.trd(s), (acc + R.poisson(s, lambda) : U32))

# Todos os `unit` em (0, 1]
def units_ok(k: Nat, +s: U32, +acc: U32) -> U32:
  match k:
    case 0n:
      acc
    case 1n+p:
      +u = R.unit(s)
      units_ok(p, R.step(s), (acc + ok(Bool.and(F32.is_gt(u, {0.0 : F32}), F32.is_le(u, {1.0 : F32}))) : U32))

# Nenhum estado absorvente: 1 milhão de passos a partir de 0 sem voltar a 0
def nonzero(k: Nat, +s: U32, +acc: U32) -> U32:
  match k:
    case 0n:
      acc
    case 1n+p:
      +n = R.step(s)
      nonzero(p, n, (acc + ok(Bool.not(U32.is_zero(n))) : U32))

def main() -> IO(Unit):
  IO.print(
    "=== TESTE DO GERADOR (random.bend) ===\n" ++
    verdict("hash32 (lowbias32) nos valores de referência",
      (ok(U32.is_eq(R.hash32(1), 1753845952)) + ok(U32.is_eq(R.hash32(42), 388445122)) +
       ok(U32.is_eq(R.hash32(4294967295), 1734902346)) + ok(U32.is_zero(R.hash32(0))) : U32), 4) ++
    verdict("sem estado absorvente: step a partir de 0, 1M passos", nonzero(1000000n, 0, 0), 1000000) ++
    verdict("step(0) sai do 0", ok(Bool.not(U32.is_zero(R.step(0)))), 1) ++
    verdict("a semente que zerava o split.snd antigo agora não zera", ok(Bool.not(U32.is_zero(R.split.snd(3783986154)))), 1) ++
    verdict("limiar 0 nunca acerta (1M, começando da semente 0)", hits(1000000n, 0, 0, 0), 0) ++
    verdict("limiar máximo sempre acerta (1M)", hits(1000000n, R.MAX(), 0, 0), 1000000) ++
    verdict("per(1,2): 50% em [497500, 502500]", between(hits(1000000n, R.per(1, 2), 7, 0), 497500, 502500), 1) ++
    verdict("per(1,1000): 0,1% em [850, 1150]", between(hits(1000000n, R.per(1, 1000), 8, 0), 850, 1150), 1) ++
    verdict("range(s,10): baldes 0 e 9 com ~100000 cada",
      (between(bucket(1000000n, 0, 9, 0), 98500, 101500) + between(bucket(1000000n, 9, 9, 0), 98500, 101500) : U32), 2) ++
    verdict("range_except(s,10,3): nunca 3", except_bucket(1000000n, 3, 10, 0), 0) ++
    verdict("range_except(s,10,3): 0 e 9 com ~111111 cada",
      (between(except_bucket(1000000n, 0, 10, 0), 109500, 112700) + between(except_bucket(1000000n, 9, 10, 0), 109500, 112700) : U32), 2) ++
    verdict("unit sempre em (0, 1] (1M)", units_ok(1000000n, 0, 0), 1000000) ++
    verdict("salto p=1/100: média x100 em [9850, 9950] (esperado 9900)", between(mean_gap100(R.per(1, 100)), 9850, 9950), 1) ++
    verdict("salto p=1/2: média x100 em [97, 103] (esperado 100)", between(mean_gap100(R.per(1, 2)), 97, 103), 1) ++
    verdict("poisson lambda=1: soma de 100k em [98500, 101500]", between(sum_poisson(100000n, {1.0 : F32}, 11, 0), 98500, 101500), 1) ++
    verdict("poisson lambda=10: soma de 100k em [995000, 1005000]", between(sum_poisson(100000n, {10.0 : F32}, 12, 0), 995000, 1005000), 1) ++
    verdict("poisson lambda=0: sempre 0", sum_poisson(10000n, {0.0 : F32}, 13, 0), 0)
  )
