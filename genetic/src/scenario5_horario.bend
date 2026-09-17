import Base

type Schedule8 is Data:
  S8{x0: U32, x1: U32, x2: U32, x3: U32, x4: U32, x5: U32, x6: U32, x7: U32}

type Timetable is Data:
  TT{t1: Schedule8, t2: Schedule8}

# Xorshift32 PRNG
def step(+x: U32) -> U32:
  +b = U32.xor(x, U32.shln(x, 13n))
  +d = U32.xor(b, U32.shrn(b, 17n))
  U32.xor(d, U32.shln(d, 5n))

def split.fst(+seed: U32) -> U32:
  step(seed)

def split.snd(+seed: U32) -> U32:
  step(U32.xor(step(seed), 2654435761))

def Schedule8.get(s: Schedule8, +idx: U32) -> U32:
  S8{x0, x1, x2, x3, x4, x5, x6, x7} = s
  Bool.pick(U32, U32.is_lt(idx, 4),
    Bool.pick(U32, U32.is_lt(idx, 2),
      Bool.pick(U32, U32.is_eq(idx, 0), x0, x1),
      Bool.pick(U32, U32.is_eq(idx, 2), x2, x3)),
    Bool.pick(U32, U32.is_lt(idx, 6),
      Bool.pick(U32, U32.is_eq(idx, 4), x4, x5),
      Bool.pick(U32, U32.is_eq(idx, 6), x6, x7)))

def Schedule8.set(s: Schedule8, +idx: U32, +val: U32) -> Schedule8:
  S8{x0, x1, x2, x3, x4, x5, x6, x7} = s
  S8{
    Bool.pick(U32, U32.is_eq(idx, 0), val, x0),
    Bool.pick(U32, U32.is_eq(idx, 1), val, x1),
    Bool.pick(U32, U32.is_eq(idx, 2), val, x2),
    Bool.pick(U32, U32.is_eq(idx, 3), val, x3),
    Bool.pick(U32, U32.is_eq(idx, 4), val, x4),
    Bool.pick(U32, U32.is_eq(idx, 5), val, x5),
    Bool.pick(U32, U32.is_eq(idx, 6), val, x6),
    Bool.pick(U32, U32.is_eq(idx, 7), val, x7)
  }

def Schedule8.swap(+s: Schedule8, +i: U32, +j: U32) -> Schedule8:
  +vi = Schedule8.get(s, i)
  +vj = Schedule8.get(s, j)
  +s_next = Schedule8.set(s, i, vj)
  Schedule8.set(s_next, j, vi)

def Schedule8.show(s: Schedule8) -> String:
  S8{x0, x1, x2, x3, x4, x5, x6, x7} = s
  "[" ++ U32.show(x0) ++ " " ++ U32.show(x1) ++ " | " ++
         U32.show(x2) ++ " " ++ U32.show(x3) ++ " | " ++
         U32.show(x4) ++ " " ++ U32.show(x5) ++ " | " ++
         U32.show(x6) ++ " " ++ U32.show(x7) ++ "]"

# Timetable evaluation:
# Subjects: 1 = Matematica (Prof M, shared between Turma 1 and Turma 2)
#           2 = Historia   (Prof H, Turma 1 only)
#           3 = Geografia  (Prof G, Turma 2 only)

def check_collision(+a: U32, +b: U32) -> U32:
  # Both classes having Matematica (1) at the same time: 100 penalty points
  Bool.pick(U32, Bool.and(U32.is_eq(a, 1), U32.is_eq(b, 1)), 100, 0)

def check_unavail_h(+a: U32) -> U32:
  # Prof H (Historia=2) unavailable in morning slots 0 and 1: 50 penalty points
  Bool.pick(U32, U32.is_eq(a, 2), 50, 0)

def check_unavail_g(+b: U32) -> U32:
  # Prof G (Geografia=3) unavailable in late slots 6 and 7: 50 penalty points
  Bool.pick(U32, U32.is_eq(b, 3), 50, 0)

def check_group(+x: U32, +y: U32) -> U32:
  # Consecutive lessons in a 2-hour block should be the same subject: 15 penalty points
  Bool.pick(U32, U32.is_ne(x, y), 15, 0)

def evaluate_timetable(tt: Timetable) -> U32:
  TT{t1, t2} = tt
  S8{a0, a1, a2, a3, a4, a5, a6, a7} = t1
  S8{b0, b1, b2, b3, b4, b5, b6, b7} = t2

  +a0 = a0; +a1 = a1; +a2 = a2; +a3 = a3
  +a4 = a4; +a5 = a5; +a6 = a6; +a7 = a7
  +b0 = b0; +b1 = b1; +b2 = b2; +b3 = b3
  +b4 = b4; +b5 = b5; +b6 = b6; +b7 = b7

  # Hard 1: Teacher Collisions
  +c0 = check_collision(a0, b0)
  +c1 = check_collision(a1, b1)
  +c2 = check_collision(a2, b2)
  +c3 = check_collision(a3, b3)
  +c4 = check_collision(a4, b4)
  +c5 = check_collision(a5, b5)
  +c6 = check_collision(a6, b6)
  +c7 = check_collision(a7, b7)
  +coll_total = (c0 + c1 + c2 + c3 + c4 + c5 + c6 + c7 : U32)

  # Hard 2: Teacher Unavailability (H at slots 0, 1; G at slots 6, 7)
  +u_h = (check_unavail_h(a0) + check_unavail_h(a1) : U32)
  +u_g = (check_unavail_g(b6) + check_unavail_g(b7) : U32)
  +unavail_total = (u_h + u_g : U32)

  # Soft 3: Subject Grouping in 2-lesson blocks
  +g1_0 = check_group(a0, a1)
  +g1_1 = check_group(a2, a3)
  +g1_2 = check_group(a4, a5)
  +g1_3 = check_group(a6, a7)

  +g2_0 = check_group(b0, b1)
  +g2_1 = check_group(b2, b3)
  +g2_2 = check_group(b4, b5)
  +g2_3 = check_group(b6, b7)
  +group_total = (g1_0 + g1_1 + g1_2 + g1_3 + g2_0 + g2_1 + g2_2 + g2_3 : U32)

  (coll_total + unavail_total + group_total : U32)

def fitness(tt: Timetable) -> U32:
  +penalties = evaluate_timetable(tt)
  (1000 - penalties : U32)

type Ind is Data:
  Ind{gene: Timetable, fit: U32}

def Ind.gene(ind: Ind) -> Timetable:
  Ind{g, _} = ind
  g

def Ind.fit(ind: Ind) -> U32:
  Ind{_, f} = ind
  f

type PopTree is Data:
  Leaf{ind: Ind}
  Node{left: PopTree, right: PopTree}

def eval_pop(tree: PopTree) -> PopTree:
  match tree:
    case Leaf{ind}:
      Ind{g, _} = ind
      +gene = g
      Leaf{Ind{gene, fitness(gene)}}
    case Node{left, right}:
      l r = eval_pop(left) eval_pop(right)
      Node{l, r}

def pick_better(+a: Ind, +b: Ind) -> Ind:
  +fa = Ind.fit(a)
  +fb = Ind.fit(b)
  Bool.pick(Ind, U32.is_ge(fa, fb), a, b)

def best_pop(tree: PopTree) -> Ind:
  match tree:
    case Leaf{ind}:
      ind
    case Node{left, right}:
      bl br = best_pop(left) best_pop(right)
      pick_better(bl, br)

# Initial multiset base schedules:
# Turma 1: 4 Matematica (1), 4 Historia (2)
def init_t1() -> Schedule8:
  S8{2, 1, 2, 1, 2, 1, 2, 1}

# Turma 2: 4 Matematica (1), 4 Geografia (3)
def init_t2() -> Schedule8:
  S8{1, 3, 1, 3, 1, 3, 1, 3}

def init_tt() -> Timetable:
  TT{init_t1(), init_t2()}

def Schedule8.swap_block(+s: Schedule8, +b1: U32, +b2: U32) -> Schedule8:
  +idx1 = U32.shln(b1, 1n)
  +idx2 = U32.shln(b2, 1n)
  +s_next1 = Schedule8.swap(s, idx1, idx2)
  Schedule8.swap(s_next1, U32.inc(idx1), U32.inc(idx2))

def Timetable.swap_col(+tt: Timetable, +i: U32, +j: U32) -> Timetable:
  TT{t1, t2} = tt
  TT{Schedule8.swap(t1, i, j), Schedule8.swap(t2, i, j)}

def Timetable.swap_block_col(+tt: Timetable, +b1: U32, +b2: U32) -> Timetable:
  TT{t1, t2} = tt
  TT{Schedule8.swap_block(t1, b1, b2), Schedule8.swap_block(t2, b1, b2)}

# Mutate timetable: applies either intra-turma slot/block swap or cross-turma column swap
def mutate_tt(+tt: Timetable, +s: U32) -> Timetable:
  TT{t1, t2} = tt
  +s1 = step(s)
  +s2 = step(s1)
  +s3 = step(s2)
  +s4 = step(s3)
  +mode = U32.mod(s1, 4)
  +i = U32.mod(s2, 8)
  +j = U32.mod(s3, 8)
  +b1 = U32.mod(s2, 4)
  +b2 = U32.mod(s3, 4)
  +which_turma = U32.and(s4, 1)

  Bool.pick(Timetable, U32.is_eq(mode, 0),
    Bool.pick(Timetable, U32.is_zero(which_turma),
      TT{Schedule8.swap(t1, i, j), t2},
      TT{t1, Schedule8.swap(t2, i, j)}),
    Bool.pick(Timetable, U32.is_eq(mode, 1),
      Bool.pick(Timetable, U32.is_zero(which_turma),
        TT{Schedule8.swap_block(t1, b1, b2), t2},
        TT{t1, Schedule8.swap_block(t2, b1, b2)}),
      Bool.pick(Timetable, U32.is_eq(mode, 2),
        Timetable.swap_col(tt, i, j),
        Timetable.swap_block_col(tt, b1, b2))))

def shuffle_tt(+tt: Timetable, +s: U32) -> Timetable:
  +s1 = step(s)
  +s2 = step(s1)
  +s3 = step(s2)
  +s4 = step(s3)
  +tt1 = mutate_tt(tt, s1)
  +tt2 = mutate_tt(tt1, s2)
  +tt3 = mutate_tt(tt2, s3)
  mutate_tt(tt3, s4)

def gen_pop(d: Nat, +seed: U32) -> PopTree:
  match d:
    case 0n:
      +g = shuffle_tt(init_tt(), seed)
      Leaf{Ind{g, fitness(g)}}
    case 1n+p:
      +p = p
      +seed = seed
      l r = gen_pop(p, split.fst(seed)) gen_pop(p, split.snd(seed))
      Node{l, r}

# Domain-specific Crossover: exchange Turma 2 between parent and elite
def crossover_tt(a: Timetable, b: Timetable) -> Timetable:
  TT{t1_a, _} = a
  TT{_, t2_b} = b
  TT{t1_a, t2_b}

def reproduce(tree: PopTree, +seed: U32, +elite: Ind) -> PopTree:
  match tree:
    case Leaf{ind}:
      Ind{g, _} = ind
      Ind{ge, _} = elite
      +g = g
      +s1 = step(seed)
      +s2 = step(s1)
      # 50% crossover with elite, else keep parent
      +crossed = Bool.pick(Timetable, U32.is_zero(U32.and(s1, 1)), crossover_tt(g, ge), g)
      +child = mutate_tt(crossed, s2)
      Leaf{Ind{child, fitness(child)}}
    case Node{left, right}:
      +seed = seed
      +elite = elite
      l r = reproduce(left, split.fst(seed), elite) reproduce(right, split.snd(seed), elite)
      Node{l, r}

def inject_elite(tree: PopTree, +elite: Ind) -> PopTree:
  match tree:
    case Leaf{_}:
      Leaf{elite}
    case Node{left, right}:
      Node{inject_elite(left, elite), right}

def step_gen(tree: PopTree, +seed: U32) -> PopTree:
  +evaluated = eval_pop(tree)
  +best = best_pop(evaluated)
  +next_pop = reproduce(evaluated, seed, best)
  inject_elite(next_pop, best)

def run_ga(g: Nat, tree: PopTree, +seed: U32) -> PopTree:
  match g:
    case 0n:
      tree
    case 1n+p:
      +next_seed = step(seed)
      +next_tree = step_gen(tree, seed)
      run_ga(p, next_tree, next_seed)

def Timetable.show(tt: Timetable) -> String:
  TT{t1, t2} = tt
  "\n  Turma 1 (1=Matematica, 2=Historia):  " ++ Schedule8.show(t1) ++
  "\n  Turma 2 (1=Matematica, 3=Geografia): " ++ Schedule8.show(t2) ++ "\n"

def main_seed() -> U32:
  998877

def main() -> IO(Unit):
  +s0 = main_seed()
  # Depth 5 = 32 individuals in the parallel population tree
  +pop0 = gen_pop(5n, s0)
  +eval0 = eval_pop(pop0)
  +best0 = best_pop(eval0)
  +g0 = Ind.gene(best0)
  +f0 = Ind.fit(best0)
  +p0 = evaluate_timetable(g0)

  # Run for 80 generations
  +pop_final = run_ga(80n, eval0, step(s0))
  +eval_final = eval_pop(pop_final)
  +best_fin = best_pop(eval_final)
  +g_fin = Ind.gene(best_fin)
  +f_fin = Ind.fit(best_fin)
  +p_fin = evaluate_timetable(g_fin)

  IO.print(
    "=== CENÁRIO 5: SOLVER DE HORÁRIO ESCOLAR (TIMETABLE SOLVER) ===\n" ++
    "Estrutura: 2 Turmas x 8 Tempos | 3 Professores (1 compartilhado)\n" ++
    "Restrições Rígidas: Choque de Professor (100 pts), Indisponibilidade (50 pts)\n" ++
    "Restrições Leves: Agrupamento em blocos de 2 aulas (15 pts)\n" ++
    "Invariante de Carga Horária: 100% garantida por construção (swaps intra-turma)\n" ++
    "População: 32 indivíduos (árvore binária profundidade 5)\n" ++
    "Geração 0  - Penalidades: " ++ U32.show(p0) ++ " (Fitness: " ++ U32.show(f0) ++ " / 1000)" ++ Timetable.show(g0) ++
    "Geração 80 - Penalidades: " ++ U32.show(p_fin) ++ " (Fitness: " ++ U32.show(f_fin) ++ " / 1000)" ++ Timetable.show(g_fin) ++
    "Quadro Perfeito Encontrado (0 penalidades)? " ++ Bool.show(U32.is_zero(p_fin)) ++ "\n"
  )
