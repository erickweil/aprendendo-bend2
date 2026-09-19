import Base
import ./../../utils/random.bend as R
import ./../../utils/io.bend as IOHelper
import ./../utils/genes.bend as V
import ./../operators.bend as Op
import ./../mutations.bend as M
import ./../ga.bend as GA

# ================================================================
# CENÁRIO 3: CAIXEIRO VIAJANTE / TSP (tsp.bend)
# ================================================================
# Problema: visitar N cidades uma única vez e voltar à primeira, percorrendo
# a menor distância possível. Porte do `problem_tsp.rs`.
#
# Contexto...: as cidades (coordenadas empacotadas x << 16 | y) e N
# Genoma.....: permutação de [0, N-1] — a ordem de visita
# Aptidão....: BASE - distância*10 (o motor MAXIMIZA; o fator 10 dá um degrau
#              mais fino que o inteiro puro)
# Cruzamento.: Order Crossover (OX1)
# Mutação....: troca aleatória + troca de vizinhos (mutation_combine)
# Seleção....: torneio de 5, em 4 ilhas de 32 com migração a cada 10 gerações
#
# Sem argumentos, a instância é VERIFICÁVEL: 12 cidades sobre uma
# circunferência de raio 500, fora de ordem. A rota ótima de pontos sobre um
# círculo é o polígono convexo, de comprimento 12·2·500·sen(15°) ≈ 3106, e a
# busca para ao encontrá-la. Com N, são N cidades aleatórias em 1000 x 1000.
#
# Uso: bend tsp.bend [SEMENTE] [N]
# ================================================================

type Cities is Data:
  Cities{pts: List<&2, U32>, n: U32, optimal: U32}

def Cities.pts(c: Cities) -> List<&2, U32>:
  Cities{p, _, _} = c
  p

def Cities.n(c: Cities) -> U32:
  Cities{_, n, _} = c
  n

def Cities.optimal(c: Cities) -> U32:
  Cities{_, _, o} = c
  o

def pack(+x: U32, +y: U32) -> U32:
  U32.or(U32.shln(x, 16n), y)

def circle() -> Cities:
  Cities{[pack(0, 500), pack(933, 750), pack(250, 67), pack(500, 1000),
          pack(933, 250), pack(67, 250), pack(1000, 500), pack(250, 933),
          pack(750, 67), pack(67, 750), pack(500, 0), pack(750, 933)], 12, 3106}

def random_pts(k: Nat, +seed: U32) -> List<&2, U32>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      +s = R.step(seed)
      Con{pack(U32.mod(R.mix(seed), 1001), U32.mod(R.mix(s), 1001)), random_pts(p, R.step(s))}

# ----------------------------------------------------------------
# DISTÂNCIA
# ----------------------------------------------------------------

def dist(+p: U32, +q: U32) -> F32:
  +dx = (U32.to_f32(U32.shrn(p, 16n)) - U32.to_f32(U32.shrn(q, 16n)) : F32)
  +dy = (U32.to_f32(U32.and(p, 65535)) - U32.to_f32(U32.and(q, 65535)) : F32)
  F32.hypot(dx, dy)

# As coordenadas viram um `Array` local, então cada cidade é lida em O(1) e a
# rota custa O(N). O par (array, cidade lida) é o estado do laço.
def route.go(perm: List<&2, U32>, r: Array<U32> & U32, +first: U32, +prev: U32, +acc: F32) -> F32:
  match perm:
    case Nil{}:
      (a, p) = r
      +p = p
      (acc + dist(prev, p) + dist(p, first) : F32)
    case Con{i, t}:
      (a, p) = r
      +p = p
      route.go(t, Array.get(U32, a, i), first, p, (acc + dist(prev, p) : F32))

def route.first(perm: List<&2, U32>, r: Array<U32> & U32) -> F32:
  match perm:
    case Nil{}:
      {0.0 : F32}
    case Con{i, t}:
      (a, p0) = r
      +p0 = p0
      route.go(t, Array.get(U32, a, i), p0, p0, {0.0 : F32})

# Comprimento do ciclo fechado descrito pela permutação
def route_len(+ctx: Cities, perm: List<&2, U32>) -> F32:
  match perm:
    case Nil{}:
      {0.0 : F32}
    case Con{i, t}:
      route.first(t, Array.get(U32, V.to_array(~U32, Cities.pts(ctx), Cities.n(ctx), 0), i))

# ----------------------------------------------------------------
# PROBLEMA
# ----------------------------------------------------------------

def BASE() -> U32:
  100000000

def init_gene(ctx: Cities, seed: U32) -> List<&2, U32>:
  V.perm_random(Cities.n(ctx), seed)

def fitness(ctx: Cities, gene: List<&2, U32>) -> U32:
  (BASE() - F32.to_u32((route_len(ctx, gene) * {10.0 : F32} : F32)) : U32)

def fit_to_dist(+f: U32) -> U32:
  U32.div((BASE() - f : U32), 10)

def key(g: U32) -> U32:
  g

def hash(ctx: Cities, g: List<&2, U32>) -> U32:
  V.hash_list(~U32, ~key, g, 7)

def cross(ctx: Cities, a: List<&2, U32>, b: List<&2, U32>, seed: U32) -> List<&2, U32> & List<&2, U32>:
  +ctx = ctx
  +n = Cities.n(ctx)
  Op.cross_ox1(~U32, ~key, a, b, n, n, seed)

# mutation_combine do Rust: cada operador recebe metade da taxa por gene
def mutate(ctx: Cities, g: List<&2, U32>, rate: U32, seed: U32) -> List<&2, U32>:
  M.combine(~U32, ~M.mut_swap(~U32), ~M.mut_neighbor(~U32), {0.5 : F32}, {0.5 : F32}, g, Cities.n(ctx), rate, seed)

# ----------------------------------------------------------------
# EXECUÇÃO
# ----------------------------------------------------------------

def show_list(l: List<&2, U32>) -> String:
  match l:
    case Nil{}:
      ""
    case Con{h, t}:
      U32.show(h) ++ " " ++ show_list(t)

def best(arch: GA.ArchTree<List<&2, U32>>) -> GA.Ind<List<&2, U32>>:
  GA.best_archipelago(List<&2, U32>, arch)

def dist_of(arch: GA.ArchTree<List<&2, U32>>) -> U32:
  fit_to_dist(GA.Ind.fit(List<&2, U32>, best(arch)))

def finish(+ctx: Cities, arch: GA.ArchTree<List<&2, U32>>, +gens: U32) -> IO(Unit):
  +b = best(arch)
  +d = F32.to_u32(route_len(ctx, GA.Ind.gene(List<&2, U32>, b)))
  +opt = Cities.optimal(ctx)
  IO.print(
    "Rota final.......: " ++ show_list(GA.Ind.gene(List<&2, U32>, b)) ++ "\n" ++
    "Distância final..: " ++ U32.show(d) ++ " (até a geração " ++ U32.show(gens) ++ ")\n" ++
    Bool.pick(String, U32.is_zero(opt), "",
      "Ótimo conhecido..: " ++ U32.show(opt) ++ " (o polígono convexo)\n" ++
      "Encontrou o ótimo: " ++ Bool.show(U32.is_le(d, opt)) ++ "\n"))

# Uma época por linha de relatório, até atingir o ótimo ou esgotar as épocas
def report(k: Nat, arch: GA.ArchTree<List<&2, U32>>, done: Bool, +gens: U32,
           +ctx: Cities, +cfg: GA.Config, +seed: U32) -> IO(Unit):
  match k done:
    case 0n True{}:
      finish(ctx, arch, gens)
    case 0n False{}:
      finish(ctx, arch, gens)
    case 1n+p True{}:
      finish(ctx, arch, gens)
    case 1n+p False{}:
      +next = GA.run_archipelago(~Cities, ~List<&2, U32>, ~init_gene, ~fitness, ~hash, ~cross, ~mutate, 1n, arch, 10n, ctx, cfg, seed)
      +now = (gens + 10 : U32)
      IO.bind(Unit, Unit,
        IO.print("  geração " ++ U32.show(now) ++ ": distância " ++ U32.show(dist_of(next))),
        u => report(p, next, GA.arch_done(List<&2, U32>, cfg, next), now, ctx, cfg, R.split.trd(seed)))

def make_ctx(+n: U32, +seed: U32) -> Cities:
  Bool.pick(Cities, U32.is_zero(n), circle(), Cities{random_pts(U32.to_nat(n), seed), n, 0})

def run(args: List<String>) -> IO(Unit):
  +nums = IOHelper.numbers(args)
  +s0 = IOHelper.num_at(nums, 0n, 20260918)
  +ctx = make_ctx(IOHelper.num_at(nums, 1n, 0), R.split.fth(s0))
  +n = Cities.n(ctx)
  +opt = Cities.optimal(ctx)
  # para ao atingir o ótimo (se conhecido); 4 ilhas x 32 indivíduos
  +max_fit = Bool.pick(U32, U32.is_zero(opt), 0, (BASE() - (opt * 10 : U32) : U32))
  +cfg = GA.config(R.per(9, 10), R.per(9, 10), R.per(1, n), 5, 300, max_fit, 5, 0)
  +a0 = GA.gen_archipelago(~Cities, ~List<&2, U32>, ~init_gene, ~fitness, 2n, ctx, cfg, s0)
  IO.bind(Unit, Unit,
    IO.print(
      "=== CENÁRIO 3: CAIXEIRO VIAJANTE (" ++ U32.show(n) ++ " cidades) ===\n" ++
      "População........: 4 ilhas x 32 indivíduos, torneio de 5\n" ++
      "  geração 0: distância " ++ U32.show(dist_of(a0))),
    u => report(100n, a0, GA.arch_done(List<&2, U32>, cfg, a0), 0, ctx, cfg, R.step(s0)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
