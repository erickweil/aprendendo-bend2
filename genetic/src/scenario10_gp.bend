import Base

# PRNG Xorshift32
def step(+x: U32) -> U32:
  +b = U32.xor(x, U32.shln(x, 13n))
  +d = U32.xor(b, U32.shrn(b, 17n))
  U32.xor(d, U32.shln(d, 5n))

def split.fst(+seed: U32) -> U32:
  step(seed)

def split.snd(+seed: U32) -> U32:
  step(U32.xor(step(seed), 2654435761))

# AST de Expressões Algébricas (Cromossomos em Árvore)
type Expr is Data:
  Var{}
  Val{v: U32}
  Add{l: Expr, r: Expr}
  Mul{l: Expr, r: Expr}

def expr_var() -> Expr:
  Var{}

def expr_val(+v: U32) -> Expr:
  Val{v}

def expr_add(l: Expr, r: Expr) -> Expr:
  Add{l, r}

def expr_mul(l: Expr, r: Expr) -> Expr:
  Mul{l, r}

# Avaliação segura de expressões para entrada x
def eval_expr(e: Expr, +x: U32) -> U32:
  match e:
    case Var{}:
      x
    case Val{v}:
      v
    case Add{l, r}:
      (eval_expr(l, x) + eval_expr(r, x) : U32)
    case Mul{l, r}:
      +vl = eval_expr(l, x)
      +vr = eval_expr(r, x)
      Bool.pick(U32, U32.is_lt(vl, 1000),
        Bool.pick(U32, U32.is_lt(vr, 1000), (vl * vr : U32), 1000000),
        1000000)

def abs_diff(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_ge(a, b), (a - b : U32), (b - a : U32))

# Função Alvo: f(x) = x^2 + 1
# Pontos de treinamento: (0, 1), (1, 2), (2, 5), (3, 10), (4, 17), (5, 26)
def eval_error(+e: Expr) -> U32:
  +e0 = abs_diff(eval_expr(e, 0), 1)
  +e1 = abs_diff(eval_expr(e, 1), 2)
  +e2 = abs_diff(eval_expr(e, 2), 5)
  +e3 = abs_diff(eval_expr(e, 3), 10)
  +e4 = abs_diff(eval_expr(e, 4), 17)
  +e5 = abs_diff(eval_expr(e, 5), 26)
  (e0 + e1 + e2 + e3 + e4 + e5 : U32)

# Tamanho da árvore para controle de bloat (pressão de parcimônia)
def tree_size(e: Expr) -> U32:
  match e:
    case Var{}:
      1
    case Val{_}:
      1
    case Add{l, r}:
      (1 + tree_size(l) + tree_size(r) : U32)
    case Mul{l, r}:
      (1 + tree_size(l) + tree_size(r) : U32)

# Fitness: penaliza erro fortemente (x50) e adiciona pequena pressão de tamanho
def fitness(+e: Expr) -> U32:
  +err = eval_error(e)
  +sz = tree_size(e)
  +penalty = (U32.mul(err, 50) + sz : U32)
  Bool.pick(U32, U32.is_lt(penalty, 1000), (1000 - penalty : U32), 0)

# Gerador aleatório de árvores de expressão
def gen_expr(d: Nat, +seed: U32) -> Expr:
  match d:
    case 0n:
      Bool.pick(Expr, U32.is_zero(U32.and(seed, 1)),
        expr_var(),
        expr_val((1 + U32.mod(step(seed), 4) : U32)))
    case 1n+p:
      +p = p
      +s1 = step(seed); +s2 = step(s1); +s3 = step(s2)
      +mode = U32.mod(s1, 3)
      Bool.pick(Expr, U32.is_eq(mode, 0),
        expr_add(gen_expr(p, s2), gen_expr(p, s3)),
        Bool.pick(Expr, U32.is_eq(mode, 1),
          expr_mul(gen_expr(p, s2), gen_expr(p, s3)),
          Bool.pick(Expr, U32.is_zero(U32.and(s2, 1)),
            expr_var(),
            expr_val((1 + U32.mod(s3, 4) : U32)))))

# Mutação de subárvores e nós
def mutate_expr(e: Expr, +rnd: U32) -> Expr:
  match e:
    case Var{}:
      +s1 = step(rnd)
      Bool.pick(Expr, U32.is_lt(U32.mod(rnd, 10), 3),
        expr_val((1 + U32.mod(s1, 4) : U32)),
        expr_var())
    case Val{v}:
      +s1 = step(rnd)
      Bool.pick(Expr, U32.is_lt(U32.mod(rnd, 10), 4),
        expr_var(),
        expr_val((1 + U32.mod(s1, 4) : U32)))
    case Add{+l, +r}:
      +s1 = step(rnd)
      +mode = U32.mod(rnd, 4)
      Bool.pick(Expr, U32.is_eq(mode, 0),
        expr_mul(l, r),
        Bool.pick(Expr, U32.is_eq(mode, 1),
          expr_add(mutate_expr(l, s1), r),
          Bool.pick(Expr, U32.is_eq(mode, 2),
            expr_add(l, mutate_expr(r, s1)),
            l)))
    case Mul{+l, +r}:
      +s1 = step(rnd)
      +mode = U32.mod(rnd, 4)
      Bool.pick(Expr, U32.is_eq(mode, 0),
        expr_add(l, r),
        Bool.pick(Expr, U32.is_eq(mode, 1),
          expr_mul(mutate_expr(l, s1), r),
          Bool.pick(Expr, U32.is_eq(mode, 2),
            expr_mul(l, mutate_expr(r, s1)),
            l)))

# Crossover de subárvores
def crossover_expr(a: Expr, +b: Expr, +rnd: U32) -> Expr:
  match a:
    case Var{}:
      b
    case Val{_}:
      b
    case Add{+l, +r}:
      Bool.pick(Expr, U32.is_zero(U32.and(rnd, 1)),
        expr_add(b, r),
        expr_add(l, b))
    case Mul{+l, +r}:
      Bool.pick(Expr, U32.is_zero(U32.and(rnd, 1)),
        expr_mul(b, r),
        expr_mul(l, b))

type Ind is Data:
  Ind{gene: Expr, fit: U32}

def Ind.gene(i: Ind) -> Expr:
  Ind{g, _} = i
  g

def Ind.fit(i: Ind) -> U32:
  Ind{_, f} = i
  f

type PopTree is Data:
  Leaf{ind: Ind}
  Node{left: PopTree, right: PopTree}

def pick_better(+a: Ind, +b: Ind) -> Ind:
  Bool.pick(Ind, U32.is_ge(Ind.fit(a), Ind.fit(b)), a, b)

def best_pop(t: PopTree) -> Ind:
  match t:
    case Leaf{ind}:
      ind
    case Node{left, right}:
      bl br = best_pop(left) best_pop(right)
      pick_better(bl, br)

def gen_pop(d: Nat, +seed: U32) -> PopTree:
  match d:
    case 0n:
      +e = gen_expr(2n, seed)
      Leaf{Ind{e, fitness(e)}}
    case 1n+p:
      +p = p
      +seed = seed
      l r = gen_pop(p, split.fst(seed)) gen_pop(p, split.snd(seed))
      Node{l, r}

def reproduce(tree: PopTree, +seed: U32, +elite: Ind) -> PopTree:
  match tree:
    case Leaf{ind}:
      Ind{g, _} = ind
      Ind{ge, _} = elite
      +s1 = step(seed); +s2 = step(s1); +s3 = step(s2)
      +crossed = crossover_expr(g, ge, s1)
      +child = Bool.pick(Expr, U32.is_lt(U32.mod(s2, 10), 6), mutate_expr(crossed, s3), crossed)
      +f_child = fitness(child)
      +f_base = fitness(crossed)
      +best_e = Bool.pick(Expr, U32.is_ge(f_child, f_base), child, crossed)
      Leaf{Ind{best_e, fitness(best_e)}}
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

def step_gen(+tree: PopTree, +seed: U32) -> PopTree:
  +best = best_pop(tree)
  +next_pop = reproduce(tree, seed, best)
  inject_elite(next_pop, best)

def run_gp(g: Nat, tree: PopTree, +seed: U32) -> PopTree:
  match g:
    case 0n:
      tree
    case 1n+p:
      +next_seed = step(seed)
      +next_tree = step_gen(tree, seed)
      run_gp(p, next_tree, next_seed)

def show_expr(e: Expr) -> String:
  match e:
    case Var{}:
      "x"
    case Val{v}:
      U32.show(v)
    case Add{l, r}:
      "(" ++ show_expr(l) ++ " + " ++ show_expr(r) ++ ")"
    case Mul{l, r}:
      "(" ++ show_expr(l) ++ " * " ++ show_expr(r) ++ ")"

def main_seed() -> U32:
  1234567

def main() -> IO(Unit):
  +s0 = main_seed()
  # População: 64 árvores de expressão em árvore binária paralela
  +pop0 = gen_pop(6n, s0)
  +best0 = best_pop(pop0)
  +e0 = Ind.gene(best0)
  +f0 = Ind.fit(best0)
  +err0 = eval_error(e0)

  # 50 gerações de Programação Genética
  +pop_final = run_gp(50n, pop0, step(s0))
  +best_fin = best_pop(pop_final)
  +e_fin = Ind.gene(best_fin)
  +f_fin = Ind.fit(best_fin)
  +err_fin = eval_error(e_fin)

  IO.print(
    "=== CENÁRIO 10: PROGRAMAÇÃO GENÉTICA / REGRESSÃO SIMBÓLICA (GP) ===\n" ++
    "Estrutura: Árvores de Expressão Algébrica (AST: Var, Val, Add, Mul)\n" ++
    "Função Alvo Desconhecida: f(x) = x^2 + 1\n" ++
    "Pontos de Treino: x=0..5 -> [1, 2, 5, 10, 17, 26]\n" ++
    "Controle de Bloat: Penalidade de Tamanho por Parcimônia\n" ++
    "Geração 0  - Erro: " ++ U32.show(err0) ++ " | Fitness: " ++ U32.show(f0) ++ " / 1000\n" ++
    "  Melhor Árvore Inicial: " ++ show_expr(e0) ++ "\n" ++
    "Geração 50 - Erro: " ++ U32.show(err_fin) ++ " | Fitness: " ++ U32.show(f_fin) ++ " / 1000\n" ++
    "  Fórmula Descoberta:    " ++ show_expr(e_fin) ++ "\n" ++
    "Fórmula Exata Descoberta (Erro = 0)? " ++ Bool.show(U32.is_zero(err_fin)) ++ "\n"
  )
