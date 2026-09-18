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

# ----------------------------------------------------------------
# SELETORES LINEARES DE AST
# ----------------------------------------------------------------
# Passar `expr_add(a, b)` e `expr_mul(a, b)` como argumentos de um
# `Bool.pick` faz o chamador construir OS DOIS nós. Estes seletores
# recebem os ingredientes e escolhem com `match` sobre um parâmetro,
# então apenas o nó vencedor é alocado.

def leaf_or_var(as_val: Bool, +v: U32) -> Expr:
  match as_val:
    case True{}:
      expr_val(v)
    case False{}:
      expr_var()

def gen_node(is_branch: Bool, is_add: Bool, +a: Expr, +b: Expr,
             as_val: Bool, +v: U32) -> Expr:
  match is_branch:
    case False{}:
      leaf_or_var(as_val, v)
    case True{}:
      match is_add:
        case True{}:
          expr_add(a, b)
        case False{}:
          expr_mul(a, b)

# `build` = False devolve uma folha barata em O(1). Isso torna a recursão
# condicional sem recursão mútua (proibida no Bend): o pai chama os dois
# filhos sempre, mas o ramo não escolhido custa uma folha em vez de uma
# subárvore inteira. Antes, as 4 chamadas recursivas especulativas eram
# construídas e 2 descartadas a cada nível.
def gen_expr(d: Nat, build: Bool, +seed: U32) -> Expr:
  match d build:
    case 0n _:
      +seed = seed
      leaf_or_var(U32.is_ne(U32.and(seed, 1), 0), (1 + U32.mod(R.step(seed), 4) : U32))
    case 1n+p False{}:
      +seed = seed
      leaf_or_var(U32.is_ne(U32.and(seed, 1), 0), (1 + U32.mod(R.step(seed), 4) : U32))
    case 1n+p True{}:
      +p = p
      +s1 = R.step(seed); +s2 = R.step(s1); +s3 = R.step(s2)
      +s2 = s2; +s3 = s3
      +mode = U32.mod(s1, 3)
      +mode = mode
      +is_branch = U32.is_lt(mode, 2)
      +is_branch = is_branch
      +a = gen_expr(p, is_branch, s2)
      +b = gen_expr(p, is_branch, s3)
      gen_node(is_branch, U32.is_eq(mode, 0), a, b,
               U32.is_ne(U32.and(s2, 1), 0), (1 + U32.mod(s3, 4) : U32))

def init_expr(seed: U32) -> Expr:
  gen_expr(2n, True{}, seed)

# Reconstrói o nó a partir dos dois filhos já resolvidos:
#   is_swap -> troca o operador (Add vira Mul e vice-versa)
#   is_drop -> colapsa o nó no filho esquerdo (controle de bloat)
#   senão   -> mantém o operador
def rebuild_add(is_swap: Bool, is_drop: Bool, +ml: Expr, +mr: Expr) -> Expr:
  match is_swap:
    case True{}:
      expr_mul(ml, mr)
    case False{}:
      match is_drop:
        case True{}:
          ml
        case False{}:
          expr_add(ml, mr)

def rebuild_mul(is_swap: Bool, is_drop: Bool, +ml: Expr, +mr: Expr) -> Expr:
  match is_swap:
    case True{}:
      expr_add(ml, mr)
    case False{}:
      match is_drop:
        case True{}:
          ml
        case False{}:
          expr_mul(ml, mr)

# `do_mut` = False devolve a expressão intacta em O(1). Com isso o nó pai
# chama os dois filhos, mas só o filho sorteado paga uma descida recursiva:
# antes as duas subárvores eram mutadas por completo e uma era descartada.
def mutate_expr(e: Expr, do_mut: Bool, +rnd: U32) -> Expr:
  match e do_mut:
    case _ False{}:
      e
    case Var{} True{}:
      +rnd = rnd
      leaf_or_var(U32.is_lt(U32.mod(rnd, 10), 3), (1 + U32.mod(R.step(rnd), 4) : U32))
    case Val{_} True{}:
      +rnd = rnd
      leaf_or_var(U32.is_ge(U32.mod(rnd, 10), 4), (1 + U32.mod(R.step(rnd), 4) : U32))
    case Add{+l, +r} True{}:
      +s1 = R.step(rnd)
      +mode = U32.mod(rnd, 4)
      +mode = mode
      +ml = mutate_expr(l, U32.is_eq(mode, 1), s1)
      +mr = mutate_expr(r, U32.is_eq(mode, 2), s1)
      rebuild_add(U32.is_eq(mode, 0), U32.is_eq(mode, 3), ml, mr)
    case Mul{+l, +r} True{}:
      +s1 = R.step(rnd)
      +mode = U32.mod(rnd, 4)
      +mode = mode
      +ml = mutate_expr(l, U32.is_eq(mode, 1), s1)
      +mr = mutate_expr(r, U32.is_eq(mode, 2), s1)
      rebuild_mul(U32.is_eq(mode, 0), U32.is_eq(mode, 3), ml, mr)

# Enxerta a subárvore doadora `b` no lugar do filho esquerdo ou direito
def graft_add(on_left: Bool, +l: Expr, +r: Expr, +b: Expr) -> Expr:
  match on_left:
    case True{}:
      expr_add(b, r)
    case False{}:
      expr_add(l, b)

def graft_mul(on_left: Bool, +l: Expr, +r: Expr, +b: Expr) -> Expr:
  match on_left:
    case True{}:
      expr_mul(b, r)
    case False{}:
      expr_mul(l, b)

def crossover_expr(a: Expr, +b: Expr, +rnd: U32) -> Expr:
  match a:
    case Var{}:
      b
    case Val{_}:
      b
    case Add{+l, +r}:
      graft_add(U32.is_zero(U32.and(rnd, 1)), l, r, b)
    case Mul{+l, +r}:
      graft_mul(U32.is_zero(U32.and(rnd, 1)), l, r, b)

def reproduce(parent: Expr, champ: Expr, seed: U32) -> Expr:
  +s1 = R.step(seed); +s2 = R.step(s1); +s3 = R.step(s2)
  +crossed = crossover_expr(parent, champ, s1)
  +child = mutate_expr(crossed, U32.is_lt(U32.mod(s2, 10), 6), s3)
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
