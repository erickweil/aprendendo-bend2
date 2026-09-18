import Base
import ./../ga.bend as GA
import ./../utils/random.bend as R

# ================================================================
# CENÁRIO 10: PROGRAMAÇÃO GENÉTICA / REGRESSÃO SIMBÓLICA (GP)
# COM MOTOR GENÉRICO
# ================================================================
# Representação: AST de Expressões Algébricas (Expr: Var, Val, Add, Mul).
# Alvo Desconhecido: f(x) = x^2 + 1
# Treino: x = [0..5] -> [1, 2, 5, 10, 17, 26]
# Bloat Control: Penalidade de complexidade sintática (tree_size).
# ================================================================

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

def eval_error(+e: Expr) -> U32:
  +e0 = abs_diff(eval_expr(e, 0), 1)
  +e1 = abs_diff(eval_expr(e, 1), 2)
  +e2 = abs_diff(eval_expr(e, 2), 5)
  +e3 = abs_diff(eval_expr(e, 3), 10)
  +e4 = abs_diff(eval_expr(e, 4), 17)
  +e5 = abs_diff(eval_expr(e, 5), 26)
  (e0 + e1 + e2 + e3 + e4 + e5 : U32)

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

def fitness(e: Expr) -> U32:
  +e = e
  +err = eval_error(e)
  +sz = tree_size(e)
  +penalty = (U32.mul(err, 50) + sz : U32)
  Bool.pick(U32, U32.is_lt(penalty, 1000), (1000 - penalty : U32), 0)

def gen_expr(d: Nat, +seed: U32) -> Expr:
  match d:
    case 0n:
      Bool.pick(Expr, U32.is_zero(U32.and(seed, 1)),
        expr_var(),
        expr_val((1 + U32.mod(R.step(seed), 4) : U32)))
    case 1n+p:
      +p = p
      +s1 = R.step(seed); +s2 = R.step(s1); +s3 = R.step(s2)
      +mode = U32.mod(s1, 3)
      Bool.pick(Expr, U32.is_eq(mode, 0),
        expr_add(gen_expr(p, s2), gen_expr(p, s3)),
        Bool.pick(Expr, U32.is_eq(mode, 1),
          expr_mul(gen_expr(p, s2), gen_expr(p, s3)),
          Bool.pick(Expr, U32.is_zero(U32.and(s2, 1)),
            expr_var(),
            expr_val((1 + U32.mod(s3, 4) : U32)))))

def init_expr(seed: U32) -> Expr:
  gen_expr(2n, seed)

def mutate_expr(e: Expr, +rnd: U32) -> Expr:
  match e:
    case Var{}:
      +s1 = R.step(rnd)
      Bool.pick(Expr, U32.is_lt(U32.mod(rnd, 10), 3),
        expr_val((1 + U32.mod(s1, 4) : U32)),
        expr_var())
    case Val{v}:
      +s1 = R.step(rnd)
      Bool.pick(Expr, U32.is_lt(U32.mod(rnd, 10), 4),
        expr_var(),
        expr_val((1 + U32.mod(s1, 4) : U32)))
    case Add{+l, +r}:
      +s1 = R.step(rnd)
      +mode = U32.mod(rnd, 4)
      Bool.pick(Expr, U32.is_eq(mode, 0),
        expr_mul(l, r),
        Bool.pick(Expr, U32.is_eq(mode, 1),
          expr_add(mutate_expr(l, s1), r),
          Bool.pick(Expr, U32.is_eq(mode, 2),
            expr_add(l, mutate_expr(r, s1)),
            l)))
    case Mul{+l, +r}:
      +s1 = R.step(rnd)
      +mode = U32.mod(rnd, 4)
      Bool.pick(Expr, U32.is_eq(mode, 0),
        expr_add(l, r),
        Bool.pick(Expr, U32.is_eq(mode, 1),
          expr_mul(mutate_expr(l, s1), r),
          Bool.pick(Expr, U32.is_eq(mode, 2),
            expr_mul(l, mutate_expr(r, s1)),
            l)))

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

def reproduce(parent: Expr, champ: Expr, seed: U32) -> Expr:
  +s1 = R.step(seed); +s2 = R.step(s1); +s3 = R.step(s2)
  +crossed = crossover_expr(parent, champ, s1)
  +child = Bool.pick(Expr, U32.is_lt(U32.mod(s2, 10), 6), mutate_expr(crossed, s3), crossed)
  +f_child = fitness(child)
  +f_base = fitness(crossed)
  Bool.pick(Expr, U32.is_ge(f_child, f_base), child, crossed)

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
  # População: 64 árvores de expressão (profundidade 6)
  +pop0 = GA.gen_population(~Expr, ~init_expr, ~fitness, 6n, s0)
  +best0 = GA.best_ind(Expr, pop0)
  +e0 = GA.Ind.gene(Expr, best0)
  +f0 = GA.Ind.fit(Expr, best0)
  +err0 = eval_error(e0)

  # 50 gerações de Programação Genética com o motor genérico
  +pop_final = GA.run_generations(~Expr, ~reproduce, ~fitness, 50n, pop0, R.step(s0))
  +best_fin = GA.best_ind(Expr, pop_final)
  +e_fin = GA.Ind.gene(Expr, best_fin)
  +f_fin = GA.Ind.fit(Expr, best_fin)
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
