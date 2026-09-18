import Base
import ./../ga.bend as GA
import ./../utils/random.bend as R
import ./../utils/poptree.bend as T

# ================================================================
# CENÁRIO 12: CO-EVOLUÇÃO COMPETITIVA (HOST VS PARASITA)
# ================================================================
# Conceito: Corrida Armamentista Co-Evolutiva (Hillis 1990)
#   Hospedeiros (População 1): Redes de 6 comparadores CAS
#   Parasitas   (População 2): Vetores de teste que buscam quebrar as redes
# Validação: Lema 0-1 (todas as 16 entradas binárias)
# ================================================================

# Vetor de 4 elementos (Parasita / Caso de Teste)
type Arr4 is Data:
  Arr4{x0: U32, x1: U32, x2: U32, x3: U32}

def make_arr4(+a: U32, +b: U32, +c: U32, +d: U32) -> Arr4:
  Arr4{a, b, c, d}

# Comparador Compare-and-Swap (CAS)
def cas(+a: Arr4, +i: U32, +j: U32) -> Arr4:
  Arr4{x0, x1, x2, x3} = a
  +x0 = x0; +x1 = x1; +x2 = x2; +x3 = x3
  +vi = Bool.pick(U32, U32.is_eq(i, 0), x0,
          Bool.pick(U32, U32.is_eq(i, 1), x1,
            Bool.pick(U32, U32.is_eq(i, 2), x2, x3)))
  +vj = Bool.pick(U32, U32.is_eq(j, 0), x0,
          Bool.pick(U32, U32.is_eq(j, 1), x1,
            Bool.pick(U32, U32.is_eq(j, 2), x2, x3)))
  +need_swap = U32.is_gt(vi, vj)
  +new_i = Bool.pick(U32, need_swap, vj, vi)
  +new_j = Bool.pick(U32, need_swap, vi, vj)
  Arr4{
    Bool.pick(U32, U32.is_eq(i, 0), new_i, Bool.pick(U32, U32.is_eq(j, 0), new_j, x0)),
    Bool.pick(U32, U32.is_eq(i, 1), new_i, Bool.pick(U32, U32.is_eq(j, 1), new_j, x1)),
    Bool.pick(U32, U32.is_eq(i, 2), new_i, Bool.pick(U32, U32.is_eq(j, 2), new_j, x2)),
    Bool.pick(U32, U32.is_eq(i, 3), new_i, Bool.pick(U32, U32.is_eq(j, 3), new_j, x3))
  }

# 6 pares possíveis entre 4 fios:
# 0: (0,1), 1: (2,3), 2: (0,2), 3: (1,3), 4: (1,2), 5: (0,3)
def apply_pair.step4(c4: Bool, +a: Arr4) -> Arr4:
  match c4:
    case True{}:  cas(a, 1, 2)
    case False{}: cas(a, 0, 3)

def apply_pair.step3(c3: Bool, +a: Arr4, +p: U32) -> Arr4:
  match c3:
    case True{}:  cas(a, 1, 3)
    case False{}: apply_pair.step4(U32.is_eq(p, 4), a)

def apply_pair.step2(c2: Bool, +a: Arr4, +p: U32) -> Arr4:
  match c2:
    case True{}:  cas(a, 0, 2)
    case False{}: apply_pair.step3(U32.is_eq(p, 3), a, p)

def apply_pair.step1(c1: Bool, +a: Arr4, +p: U32) -> Arr4:
  match c1:
    case True{}:  cas(a, 2, 3)
    case False{}: apply_pair.step2(U32.is_eq(p, 2), a, p)

def apply_pair.go(c0: Bool, +a: Arr4, +p: U32) -> Arr4:
  match c0:
    case True{}:  cas(a, 0, 1)
    case False{}: apply_pair.step1(U32.is_eq(p, 1), a, p)

def apply_pair(+a: Arr4, +p: U32) -> Arr4:
  apply_pair.go(U32.is_eq(p, 0), a, p)

def is_sorted(a: Arr4) -> Bool:
  Arr4{x0, x1, x2, x3} = a
  +x1 = x1; +x2 = x2
  Bool.and(U32.is_le(x0, x1), Bool.and(U32.is_le(x1, x2), U32.is_le(x2, x3)))

# Rede de Ordenação (Hospedeiro / 6 comparadores)
type Net is Data:
  Net{c0: U32, c1: U32, c2: U32, c3: U32, c4: U32, c5: U32}

def make_net(+c0: U32, +c1: U32, +c2: U32, +c3: U32, +c4: U32, +c5: U32) -> Net:
  Net{c0, c1, c2, c3, c4, c5}

def run_network(net: Net, +input: Arr4) -> Arr4:
  Net{c0, c1, c2, c3, c4, c5} = net
  +a1 = apply_pair(input, c0)
  +a2 = apply_pair(a1, c1)
  +a3 = apply_pair(a2, c2)
  +a4 = apply_pair(a3, c3)
  +a5 = apply_pair(a4, c4)
  apply_pair(a5, c5)

# Teste contra 1 parasita: 1 se ordenou, 0 se falhou
def test_host(+net: Net, +parasite: Arr4) -> U32:
  +res = run_network(net, parasite)
  Bool.pick(U32, is_sorted(res), 1, 0)

# População de Parasitas (8 vetores adversariais)
type ParasiteBank is Data:
  PBank{p0: Arr4, p1: Arr4, p2: Arr4, p3: Arr4, p4: Arr4, p5: Arr4, p6: Arr4, p7: Arr4}

# Avalia a rede contra todo o banco de parasitas
def eval_net(+net: Net, bank: ParasiteBank) -> U32:
  PBank{p0, p1, p2, p3, p4, p5, p6, p7} = bank
  +s0 = test_host(net, p0); +s1 = test_host(net, p1); +s2 = test_host(net, p2); +s3 = test_host(net, p3)
  +s4 = test_host(net, p4); +s5 = test_host(net, p5); +s6 = test_host(net, p6); +s7 = test_host(net, p7)
  (s0 + s1 + s2 + s3 + s4 + s5 + s6 + s7 : U32)

def gen_net(+seed: U32) -> Net:
  +s1 = R.step(seed); +s2 = R.step(s1); +s3 = R.step(s2)
  +s4 = R.step(s3);   +s5 = R.step(s4); +s6 = R.step(s5)
  make_net(
    U32.mod(s1, 6), U32.mod(s2, 6), U32.mod(s3, 6),
    U32.mod(s4, 6), U32.mod(s5, 6), U32.mod(s6, 6)
  )

def gen_host_pop(d: Nat, +seed: U32, +bank: ParasiteBank) -> T.PopTree<GA.Ind<Net>>:
  match d:
    case 0n:
      +net = gen_net(seed)
      T.Leaf{GA.Ind{net, eval_net(net, bank)}}
    case 1n+p:
      +p = p; +seed = seed; +bank = bank
      l r = gen_host_pop(p, R.split.fst(seed), bank) gen_host_pop(p, R.split.snd(seed), bank)
      T.Node{l, r}

def mutate_net(net: Net, +rnd: U32) -> Net:
  Net{c0, c1, c2, c3, c4, c5} = net
  +idx = U32.mod(rnd, 6)
  +val = U32.mod(R.step(rnd), 6)
  make_net(
    Bool.pick(U32, U32.is_eq(idx, 0), val, c0),
    Bool.pick(U32, U32.is_eq(idx, 1), val, c1),
    Bool.pick(U32, U32.is_eq(idx, 2), val, c2),
    Bool.pick(U32, U32.is_eq(idx, 3), val, c3),
    Bool.pick(U32, U32.is_eq(idx, 4), val, c4),
    Bool.pick(U32, U32.is_eq(idx, 5), val, c5)
  )

def crossover_net(a: Net, b: Net, +mask: U32) -> Net:
  Net{a0, a1, a2, a3, a4, a5} = a
  Net{b0, b1, b2, b3, b4, b5} = b
  make_net(
    Bool.pick(U32, U32.is_ne(U32.and(mask, 1), 0), a0, b0),
    Bool.pick(U32, U32.is_ne(U32.and(mask, 2), 0), a1, b1),
    Bool.pick(U32, U32.is_ne(U32.and(mask, 4), 0), a2, b2),
    Bool.pick(U32, U32.is_ne(U32.and(mask, 8), 0), a3, b3),
    Bool.pick(U32, U32.is_ne(U32.and(mask, 16), 0), a4, b4),
    Bool.pick(U32, U32.is_ne(U32.and(mask, 32), 0), a5, b5)
  )

def reproduce_hosts(tree: T.PopTree<GA.Ind<Net>>, +seed: U32, +elite: GA.Ind<Net>, +bank: ParasiteBank) -> T.PopTree<GA.Ind<Net>>:
  match tree:
    case T.Leaf{ind}:
      +g = GA.Ind.gene(Net, ind)
      +ge = GA.Ind.gene(Net, elite)
      +s1 = R.step(seed); +s2 = R.step(s1)
      +crossed = crossover_net(g, ge, s1)
      +child_net = mutate_net(crossed, s2)
      +f_child = eval_net(child_net, bank)
      +f_cross = eval_net(crossed, bank)
      +best_n = Bool.pick(Net, U32.is_ge(f_child, f_cross), child_net, crossed)
      +best_f = Bool.pick(U32, U32.is_ge(f_child, f_cross), f_child, f_cross)
      T.Leaf{GA.Ind{best_n, best_f}}
    case T.Node{left, right}:
      +seed = seed; +elite = elite; +bank = bank
      l r = reproduce_hosts(left, R.split.fst(seed), elite, bank) reproduce_hosts(right, R.split.snd(seed), elite, bank)
      T.Node{l, r}

def mutate_arr4(a: Arr4, +rnd: U32) -> Arr4:
  Arr4{x0, x1, x2, x3} = a
  +x0 = x0; +x1 = x1; +x2 = x2; +x3 = x3
  +s1 = R.step(rnd); +s2 = R.step(s1)
  +i = U32.mod(s1, 4); +j = U32.mod(s2, 4)
  +vi = Bool.pick(U32, U32.is_eq(i, 0), x0, Bool.pick(U32, U32.is_eq(i, 1), x1, Bool.pick(U32, U32.is_eq(i, 2), x2, x3)))
  +vj = Bool.pick(U32, U32.is_eq(j, 0), x0, Bool.pick(U32, U32.is_eq(j, 1), x1, Bool.pick(U32, U32.is_eq(j, 2), x2, x3)))
  Arr4{
    Bool.pick(U32, U32.is_eq(i, 0), vj, Bool.pick(U32, U32.is_eq(j, 0), vi, x0)),
    Bool.pick(U32, U32.is_eq(i, 1), vj, Bool.pick(U32, U32.is_eq(j, 1), vi, x1)),
    Bool.pick(U32, U32.is_eq(i, 2), vj, Bool.pick(U32, U32.is_eq(j, 2), vi, x2)),
    Bool.pick(U32, U32.is_eq(i, 3), vj, Bool.pick(U32, U32.is_eq(j, 3), vi, x3))
  }

def evolve_parasite(+champ: Net, +p: Arr4, +rnd: U32) -> Arr4:
  +p_mut = mutate_arr4(p, rnd)
  +broken = U32.is_zero(test_host(champ, p_mut))
  Bool.pick(Arr4, broken, p_mut, p)

def evolve_bank(+champ: Net, bank: ParasiteBank, +seed: U32) -> ParasiteBank:
  PBank{p0, p1, p2, p3, p4, p5, p6, p7} = bank
  +s0 = R.step(seed); +s1 = R.step(s0); +s2 = R.step(s1); +s3 = R.step(s2)
  +s4 = R.step(s3);   +s5 = R.step(s4); +s6 = R.step(s5); +s7 = R.step(s6)
  PBank{
    evolve_parasite(champ, p0, s0), evolve_parasite(champ, p1, s1),
    evolve_parasite(champ, p2, s2), evolve_parasite(champ, p3, s3),
    evolve_parasite(champ, p4, s4), evolve_parasite(champ, p5, s5),
    evolve_parasite(champ, p6, s6), evolve_parasite(champ, p7, s7)
  }

type CoResult is Data:
  CoResult{hosts: T.PopTree<GA.Ind<Net>>, bank: ParasiteBank}

# Ciclo Co-Evolutivo (Hospedeiros vs Parasitas)
def coevolve(g: Nat, hosts: T.PopTree<GA.Ind<Net>>, bank: ParasiteBank, +seed: U32) -> CoResult:
  match g:
    case 0n:
      CoResult{hosts, bank}
    case 1n+p:
      +next_seed = R.step(seed)
      +hosts = hosts
      +champ = GA.best_ind(Net, hosts)
      +champ_net = GA.Ind.gene(Net, champ)
      +new_bank = evolve_bank(champ_net, bank, seed)
      +new_hosts = reproduce_hosts(hosts, next_seed, champ, new_bank)
      coevolve(p, new_hosts, new_bank, next_seed)

def initial_bank() -> ParasiteBank:
  PBank{
    make_arr4(4, 3, 2, 1), make_arr4(3, 4, 1, 2),
    make_arr4(2, 4, 1, 3), make_arr4(4, 1, 3, 2),
    make_arr4(3, 1, 4, 2), make_arr4(2, 3, 4, 1),
    make_arr4(4, 2, 1, 3), make_arr4(1, 4, 3, 2)
  }

def test_all_16(+net: Net) -> U32:
  +t00 = test_host(net, make_arr4(0, 0, 0, 0)); +t01 = test_host(net, make_arr4(0, 0, 0, 1))
  +t02 = test_host(net, make_arr4(0, 0, 1, 0)); +t03 = test_host(net, make_arr4(0, 0, 1, 1))
  +t04 = test_host(net, make_arr4(0, 1, 0, 0)); +t05 = test_host(net, make_arr4(0, 1, 0, 1))
  +t06 = test_host(net, make_arr4(0, 1, 1, 0)); +t07 = test_host(net, make_arr4(0, 1, 1, 1))
  +t08 = test_host(net, make_arr4(1, 0, 0, 0)); +t09 = test_host(net, make_arr4(1, 0, 0, 1))
  +t10 = test_host(net, make_arr4(1, 0, 1, 0)); +t11 = test_host(net, make_arr4(1, 0, 1, 1))
  +t12 = test_host(net, make_arr4(1, 1, 0, 0)); +t13 = test_host(net, make_arr4(1, 1, 0, 1))
  +t14 = test_host(net, make_arr4(1, 1, 1, 0)); +t15 = test_host(net, make_arr4(1, 1, 1, 1))
  (t00 + t01 + t02 + t03 + t04 + t05 + t06 + t07 + t08 + t09 + t10 + t11 + t12 + t13 + t14 + t15 : U32)

def Net.show(n: Net) -> String:
  Net{c0, c1, c2, c3, c4, c5} = n
  "[" ++ U32.show(c0) ++ " " ++ U32.show(c1) ++ " " ++ U32.show(c2) ++ " " ++
         U32.show(c3) ++ " " ++ U32.show(c4) ++ " " ++ U32.show(c5) ++ "]"

def main_seed() -> U32:
  6543210

def main.report(result: CoResult, +f0: U32) -> IO(Unit):
  CoResult{hosts, bank} = result
  +best_fin = GA.best_ind(Net, hosts)
  +n_fin = GA.Ind.gene(Net, best_fin)
  +f_fin = GA.Ind.fit(Net, best_fin)
  +lemma_16 = test_all_16(n_fin)

  IO.print(
    "=== CENÁRIO 12: CO-EVOLUÇÃO COMPETITIVA (HOST VS PARASITA / REDES DE ORDENAÇÃO) ===\n" ++
    "Conceito: Corrida Armamentista Co-Evolutiva (Hillis 1990)\n" ++
    "  Hospedeiros (População 1): Redes de 6 comparadores Compare-and-Swap (CAS)\n" ++
    "  Parasitas   (População 2): Vetores de teste que evoluem para quebrar as redes\n" ++
    "Geração 0  - Sucesso contra Parasitas: " ++ U32.show(f0) ++ " / 8\n" ++
    "Geração 60 - Sucesso contra Parasitas: " ++ U32.show(f_fin) ++ " / 8\n" ++
    "  Rede Campeã (Comparadores): " ++ Net.show(n_fin) ++ "\n" ++
    "Lema 0-1 (Ordena todas as 16 permutações binárias possíveis)? " ++
    U32.show(lemma_16) ++ " / 16 (" ++ Bool.show(U32.is_eq(lemma_16, 16)) ++ ")\n"
  )

def main() -> IO(Unit):
  +s0 = main_seed()
  +bank0 = initial_bank()
  +hosts0 = gen_host_pop(5n, s0, bank0)
  +best0 = GA.best_ind(Net, hosts0)
  +f0 = GA.Ind.fit(Net, best0)

  +res = coevolve(60n, hosts0, bank0, R.step(s0))
  main.report(res, f0)
