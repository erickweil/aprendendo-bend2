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

# 12 Itens para Otimização Multi-Objetivo
# Objetivo 1: MAXIMIZAR Valor
# Objetivo 2: MINIMIZAR Peso (Custo de Recursos)
# Restrição: Capacidade Máxima = 100 kg
def item_val(+i: U32) -> U32:
  Bool.pick(U32, U32.is_eq(i, 0), 25,
    Bool.pick(U32, U32.is_eq(i, 1), 35,
      Bool.pick(U32, U32.is_eq(i, 2), 45,
        Bool.pick(U32, U32.is_eq(i, 3), 15,
          Bool.pick(U32, U32.is_eq(i, 4), 50,
            Bool.pick(U32, U32.is_eq(i, 5), 30,
              Bool.pick(U32, U32.is_eq(i, 6), 40,
                Bool.pick(U32, U32.is_eq(i, 7), 60,
                  Bool.pick(U32, U32.is_eq(i, 8), 20,
                    Bool.pick(U32, U32.is_eq(i, 9), 55,
                      Bool.pick(U32, U32.is_eq(i, 10), 10, 30)))))))))))

def item_wt(+i: U32) -> U32:
  Bool.pick(U32, U32.is_eq(i, 0), 10,
    Bool.pick(U32, U32.is_eq(i, 1), 15,
      Bool.pick(U32, U32.is_eq(i, 2), 25,
        Bool.pick(U32, U32.is_eq(i, 3), 8,
          Bool.pick(U32, U32.is_eq(i, 4), 30,
            Bool.pick(U32, U32.is_eq(i, 5), 18,
              Bool.pick(U32, U32.is_eq(i, 6), 22,
                Bool.pick(U32, U32.is_eq(i, 7), 35,
                  Bool.pick(U32, U32.is_eq(i, 8), 12,
                    Bool.pick(U32, U32.is_eq(i, 9), 28,
                      Bool.pick(U32, U32.is_eq(i, 10), 5, 16)))))))))))

type Obj2 is Data:
  Obj2{val: U32, wt: U32}

# Avaliação dos dois objetivos
def eval_objectives(+mask: U32) -> Obj2:
  +v0 = Bool.pick(U32, U32.is_ne(U32.and(mask, 1), 0), item_val(0), 0)
  +v1 = Bool.pick(U32, U32.is_ne(U32.and(mask, 2), 0), item_val(1), 0)
  +v2 = Bool.pick(U32, U32.is_ne(U32.and(mask, 4), 0), item_val(2), 0)
  +v3 = Bool.pick(U32, U32.is_ne(U32.and(mask, 8), 0), item_val(3), 0)
  +v4 = Bool.pick(U32, U32.is_ne(U32.and(mask, 16), 0), item_val(4), 0)
  +v5 = Bool.pick(U32, U32.is_ne(U32.and(mask, 32), 0), item_val(5), 0)
  +v6 = Bool.pick(U32, U32.is_ne(U32.and(mask, 64), 0), item_val(6), 0)
  +v7 = Bool.pick(U32, U32.is_ne(U32.and(mask, 128), 0), item_val(7), 0)
  +v8 = Bool.pick(U32, U32.is_ne(U32.and(mask, 256), 0), item_val(8), 0)
  +v9 = Bool.pick(U32, U32.is_ne(U32.and(mask, 512), 0), item_val(9), 0)
  +va = Bool.pick(U32, U32.is_ne(U32.and(mask, 1024), 0), item_val(10), 0)
  +vb = Bool.pick(U32, U32.is_ne(U32.and(mask, 2048), 0), item_val(11), 0)
  +tot_val = (v0 + v1 + v2 + v3 + v4 + v5 + v6 + v7 + v8 + v9 + va + vb : U32)

  +w0 = Bool.pick(U32, U32.is_ne(U32.and(mask, 1), 0), item_wt(0), 0)
  +w1 = Bool.pick(U32, U32.is_ne(U32.and(mask, 2), 0), item_wt(1), 0)
  +w2 = Bool.pick(U32, U32.is_ne(U32.and(mask, 4), 0), item_wt(2), 0)
  +w3 = Bool.pick(U32, U32.is_ne(U32.and(mask, 8), 0), item_wt(3), 0)
  +w4 = Bool.pick(U32, U32.is_ne(U32.and(mask, 16), 0), item_wt(4), 0)
  +w5 = Bool.pick(U32, U32.is_ne(U32.and(mask, 32), 0), item_wt(5), 0)
  +w6 = Bool.pick(U32, U32.is_ne(U32.and(mask, 64), 0), item_wt(6), 0)
  +w7 = Bool.pick(U32, U32.is_ne(U32.and(mask, 128), 0), item_wt(7), 0)
  +w8 = Bool.pick(U32, U32.is_ne(U32.and(mask, 256), 0), item_wt(8), 0)
  +w9 = Bool.pick(U32, U32.is_ne(U32.and(mask, 512), 0), item_wt(9), 0)
  +wa = Bool.pick(U32, U32.is_ne(U32.and(mask, 1024), 0), item_wt(10), 0)
  +wb = Bool.pick(U32, U32.is_ne(U32.and(mask, 2048), 0), item_wt(11), 0)
  +tot_wt = (w0 + w1 + w2 + w3 + w4 + w5 + w6 + w7 + w8 + w9 + wa + wb : U32)

  # Penalização de capacidade estrita (> 100 kg zera valor e infla peso)
  +is_valid = U32.is_le(tot_wt, 100)
  +final_val = Bool.pick(U32, is_valid, tot_val, 0)
  +final_wt = Bool.pick(U32, is_valid, tot_wt, 999)
  Obj2{final_val, final_wt}

type MOInd is Data:
  MOInd{gene: U32, val: U32, wt: U32}

def make_mo_ind.apply(+clean_gene: U32, obj: Obj2) -> MOInd:
  Obj2{v, w} = obj
  MOInd{clean_gene, v, w}

def make_mo_ind(+gene: U32) -> MOInd:
  +clean_gene = U32.and(gene, 4095)
  make_mo_ind.apply(clean_gene, eval_objectives(clean_gene))

def MOInd.val(i: MOInd) -> U32:
  MOInd{_, v, _} = i
  v

def MOInd.wt(i: MOInd) -> U32:
  MOInd{_, _, w} = i
  w

def MOInd.gene(i: MOInd) -> U32:
  MOInd{g, _, _} = i
  g

# Relação de Dominância de Pareto:
# A domina B se: val(A) >= val(B) E wt(A) <= wt(B), com pelo menos uma desigualdade estrita
def dominates(+a: MOInd, +b: MOInd) -> Bool:
  MOInd{_, va, wa} = a
  MOInd{_, vb, wb} = b
  +not_worse = Bool.and(U32.is_ge(va, vb), U32.is_le(wa, wb))
  +strictly_better = Bool.or(U32.is_gt(va, vb), U32.is_lt(wa, wb))
  Bool.and(not_worse, strictly_better)

# Densidade de Eficiência: (val * 100) / (wt + 1)
def efficiency(+ind: MOInd) -> U32:
  MOInd{_, v, w} = ind
  U32.div(U32.mul(v, 100), (w + 1 : U32))

# Seleção de Torneio Pareto com desempate por diversidade
def pareto_pick(+a: MOInd, +b: MOInd, +rnd: U32) -> MOInd:
  +a_dom_b = dominates(a, b)
  +b_dom_a = dominates(b, a)
  Bool.pick(MOInd, a_dom_b, a,
    Bool.pick(MOInd, b_dom_a, b,
      # Ambos não-dominados: alternar entre maior valor, menor peso ou maior densidade
      Bool.pick(MOInd, U32.is_eq(U32.mod(rnd, 3), 0),
        Bool.pick(MOInd, U32.is_ge(efficiency(a), efficiency(b)), a, b),
        Bool.pick(MOInd, U32.is_eq(U32.mod(rnd, 3), 1),
          Bool.pick(MOInd, U32.is_ge(MOInd.val(a), MOInd.val(b)), a, b),
          Bool.pick(MOInd, U32.is_le(MOInd.wt(a), MOInd.wt(b)), a, b)))))

type PopTree is Data:
  Leaf{ind: MOInd}
  Node{left: PopTree, right: PopTree}

def pick_best_val(+a: MOInd, +b: MOInd) -> MOInd:
  Bool.pick(MOInd, U32.is_ge(MOInd.val(a), MOInd.val(b)), a, b)

def pick_best_eff(+a: MOInd, +b: MOInd) -> MOInd:
  Bool.pick(MOInd, U32.is_ge(efficiency(a), efficiency(b)), a, b)

def pick_min_wt(+a: MOInd, +b: MOInd) -> MOInd:
  +va = MOInd.val(a); +vb = MOInd.val(b)
  +wa = MOInd.wt(a);  +wb = MOInd.wt(b)
  Bool.pick(MOInd, U32.is_zero(va), b,
    Bool.pick(MOInd, U32.is_zero(vb), a,
      Bool.pick(MOInd, U32.is_le(wa, wb), a, b)))

def best_val(t: PopTree) -> MOInd:
  match t:
    case Leaf{ind}:
      ind
    case Node{left, right}:
      bl br = best_val(left) best_val(right)
      pick_best_val(bl, br)

def best_eff(t: PopTree) -> MOInd:
  match t:
    case Leaf{ind}:
      ind
    case Node{left, right}:
      bl br = best_eff(left) best_eff(right)
      pick_best_eff(bl, br)

def min_wt(t: PopTree) -> MOInd:
  match t:
    case Leaf{ind}:
      ind
    case Node{left, right}:
      bl br = min_wt(left) min_wt(right)
      pick_min_wt(bl, br)

def gen_pop(d: Nat, +seed: U32) -> PopTree:
  match d:
    case 0n:
      Leaf{make_mo_ind(seed)}
    case 1n+p:
      +p = p
      +seed = seed
      l r = gen_pop(p, split.fst(seed)) gen_pop(p, split.snd(seed))
      Node{l, r}

def crossover_uniform(+a: U32, +b: U32, +mask: U32) -> U32:
  U32.or(U32.and(a, mask), U32.and(b, U32.not(mask)))

def mutate_bits(+g: U32, +rnd: U32) -> U32:
  +bit_idx = U32.to_nat(U32.mod(rnd, 12))
  U32.xor(g, U32.shln(1, bit_idx))

# Reprodução com Torneio de Pareto entre vizinhos na árvore
def reproduce(tree: PopTree, +seed: U32, +partner: MOInd) -> PopTree:
  match tree:
    case Leaf{ind}:
      +s1 = step(seed); +s2 = step(s1); +s3 = step(s2)
      +winner = pareto_pick(ind, partner, s1)
      +g_win = MOInd.gene(winner)
      +g_part = MOInd.gene(partner)
      +crossed = crossover_uniform(g_win, g_part, s2)
      +mutated = Bool.pick(U32, U32.is_lt(U32.mod(s3, 10), 4), mutate_bits(crossed, s3), crossed)
      +child = make_mo_ind(mutated)
      Leaf{pareto_pick(winner, child, step(s3))}
    case Node{left, right}:
      +left = left
      +right = right
      +seed = seed
      +partner = partner
      +bl = best_eff(left)
      +br = best_eff(right)
      l r = reproduce(left, split.fst(seed), br) reproduce(right, split.snd(seed), bl)
      Node{l, r}

def step_gen(+tree: PopTree, +seed: U32) -> PopTree:
  +eff = best_eff(tree)
  reproduce(tree, seed, eff)

def run_moea(g: Nat, tree: PopTree, +seed: U32) -> PopTree:
  match g:
    case 0n:
      tree
    case 1n+p:
      +next_seed = step(seed)
      +next_tree = step_gen(tree, seed)
      run_moea(p, next_tree, next_seed)

def show_ind(ind: MOInd) -> String:
  MOInd{g, v, w} = ind
  +v = v
  +w = w
  +eff = U32.div(U32.mul(v, 100), (w + 1 : U32))
  "Valor: " ++ U32.show(v) ++ " | Peso: " ++ U32.show(w) ++ " kg | Eficiência: " ++ U32.show(eff) ++ " | Genoma: " ++ U32.show(g)

def main_seed() -> U32:
  88776655

def main() -> IO(Unit):
  +s0 = main_seed()
  # População: 64 soluções multi-objetivo em árvore paralela
  +pop0 = gen_pop(6n, s0)
  +b_val0 = best_val(pop0)
  +b_eff0 = best_eff(pop0)
  +m_wt0 = min_wt(pop0)

  # Executar Otimização Evolutiva Multi-Objetivo (50 gerações)
  +pop_fin = run_moea(50n, pop0, step(s0))
  +b_val_fin = best_val(pop_fin)
  +b_eff_fin = best_eff(pop_fin)
  +m_wt_fin = min_wt(pop_fin)

  +v_wt = MOInd.wt(b_val_fin)
  +e_wt = MOInd.wt(b_eff_fin)
  +m_wt = MOInd.wt(m_wt_fin)

  IO.print(
    "=== CENÁRIO 11: OTIMIZAÇÃO MULTI-OBJETIVO (MOEA / FRONTEIRA DE PARETO) ===\n" ++
    "Objetivos Conflitantes: Max(Valor) e Min(Peso) | Restrição: Peso <= 100 kg\n" ++
    "Seleção: Dominância de Pareto A > B (não-pior em todos, melhor em pelo menos um)\n" ++
    "População: 64 indivíduos (Árvore Binária Profundidade 6)\n\n" ++
    "-- GERAÇÃO 0 (Soluções Iniciais) --\n" ++
    "  Melhor Valor:      " ++ show_ind(b_val0) ++ "\n" ++
    "  Melhor Eficiência: " ++ show_ind(b_eff0) ++ "\n" ++
    "  Menor Peso Útil:   " ++ show_ind(m_wt0) ++ "\n\n" ++
    "-- GERAÇÃO 50 (Fronteira de Pareto Descoberta) --\n" ++
    "  [Especialista Valor]:      " ++ show_ind(b_val_fin) ++ "\n" ++
    "  [Especialista Eficiência]: " ++ show_ind(b_eff_fin) ++ "\n" ++
    "  [Especialista Leveza]:     " ++ show_ind(m_wt_fin) ++ "\n\n" ++
    "Fronteira Válida (Todos os Especialistas <= 100 kg)? " ++
    Bool.show(Bool.and(U32.is_le(v_wt, 100),
              Bool.and(U32.is_le(e_wt, 100),
                       U32.is_le(m_wt, 100)))) ++ "\n"
  )
