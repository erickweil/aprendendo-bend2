import Base
import ./../ga.bend as GA
import ./../utils/random.bend as R
import ./../operators.bend as Op

# ================================================================
# CENÁRIO 7: PROBLEMA DA MOCHILA (0/1 KNAPSACK) COM MOTOR GENÉRICO
# ================================================================
# Representação: U32 como bitmask (10 bits = 10 itens).
# Cada bit indica se o item correspondente foi incluído na mochila.
# Capacidade máxima: 80 kg.
# Fitness: Se peso <= 80: valor total; senão: penalidade severa.
# ================================================================

def item_weight(+idx: U32) -> U32:
  Bool.pick(U32, U32.is_lt(idx, 5),
    Bool.pick(U32, U32.is_lt(idx, 3),
      Bool.pick(U32, U32.is_eq(idx, 0), 10, Bool.pick(U32, U32.is_eq(idx, 1), 15, 20)),
      Bool.pick(U32, U32.is_eq(idx, 3), 25, 30)),
    Bool.pick(U32, U32.is_lt(idx, 8),
      Bool.pick(U32, U32.is_eq(idx, 5), 12, Bool.pick(U32, U32.is_eq(idx, 6), 18, 8)),
      Bool.pick(U32, U32.is_eq(idx, 8), 22, 14)))

def item_value(+idx: U32) -> U32:
  Bool.pick(U32, U32.is_lt(idx, 5),
    Bool.pick(U32, U32.is_lt(idx, 3),
      Bool.pick(U32, U32.is_eq(idx, 0), 20, Bool.pick(U32, U32.is_eq(idx, 1), 30, 40)),
      Bool.pick(U32, U32.is_eq(idx, 3), 55, 60)),
    Bool.pick(U32, U32.is_lt(idx, 8),
      Bool.pick(U32, U32.is_eq(idx, 5), 25, Bool.pick(U32, U32.is_eq(idx, 6), 38, 18)),
      Bool.pick(U32, U32.is_eq(idx, 8), 50, 32)))

def bit_selected(+mask: U32, +bit: Nat) -> Bool:
  U32.is_ne(U32.and(mask, U32.shln(1, bit)), 0)

def total_weight(+mask: U32) -> U32:
  +w0 = Bool.pick(U32, bit_selected(mask, 0n), item_weight(0), 0)
  +w1 = Bool.pick(U32, bit_selected(mask, 1n), item_weight(1), 0)
  +w2 = Bool.pick(U32, bit_selected(mask, 2n), item_weight(2), 0)
  +w3 = Bool.pick(U32, bit_selected(mask, 3n), item_weight(3), 0)
  +w4 = Bool.pick(U32, bit_selected(mask, 4n), item_weight(4), 0)
  +w5 = Bool.pick(U32, bit_selected(mask, 5n), item_weight(5), 0)
  +w6 = Bool.pick(U32, bit_selected(mask, 6n), item_weight(6), 0)
  +w7 = Bool.pick(U32, bit_selected(mask, 7n), item_weight(7), 0)
  +w8 = Bool.pick(U32, bit_selected(mask, 8n), item_weight(8), 0)
  +w9 = Bool.pick(U32, bit_selected(mask, 9n), item_weight(9), 0)
  (w0 + w1 + w2 + w3 + w4 + w5 + w6 + w7 + w8 + w9 : U32)

def total_value(+mask: U32) -> U32:
  +v0 = Bool.pick(U32, bit_selected(mask, 0n), item_value(0), 0)
  +v1 = Bool.pick(U32, bit_selected(mask, 1n), item_value(1), 0)
  +v2 = Bool.pick(U32, bit_selected(mask, 2n), item_value(2), 0)
  +v3 = Bool.pick(U32, bit_selected(mask, 3n), item_value(3), 0)
  +v4 = Bool.pick(U32, bit_selected(mask, 4n), item_value(4), 0)
  +v5 = Bool.pick(U32, bit_selected(mask, 5n), item_value(5), 0)
  +v6 = Bool.pick(U32, bit_selected(mask, 6n), item_value(6), 0)
  +v7 = Bool.pick(U32, bit_selected(mask, 7n), item_value(7), 0)
  +v8 = Bool.pick(U32, bit_selected(mask, 8n), item_value(8), 0)
  +v9 = Bool.pick(U32, bit_selected(mask, 9n), item_value(9), 0)
  (v0 + v1 + v2 + v3 + v4 + v5 + v6 + v7 + v8 + v9 : U32)

def max_capacity() -> U32:
  80

def fitness(mask: U32) -> U32:
  +mask = mask
  +w = total_weight(mask)
  +v = total_value(mask)
  +cap = max_capacity()
  # Penalidade graduada: 40 pontos de valor por kg de excesso, com piso em 0.
  # O coeficiente 40 > maior valor/kg do conjunto garante que nenhuma solução
  # inválida possa superar a melhor solução viável, preservando ainda assim o
  # gradiente que permite a uma solução levemente acima do peso evoluir de volta
  # para a região viável (a penalidade-morte com fitness 0 apaga esse gradiente).
  # O excesso e a subtração final são calculados com guarda explícita porque
  # U32.sub faz wrap-around em Bend (3 - 10 == 4294967289); a versão anterior
  # calculava `v - 4*(w - cap)` sem guarda e, quando a penalidade superava o
  # valor, o wrap devolvia ~4.29e9 de aptidão para soluções inválidas.
  +over = Bool.pick(U32, U32.is_le(w, cap), 0, (w - cap : U32))
  +penalty = U32.mul(over, 40)
  +penalty = penalty
  Bool.pick(U32, U32.is_gt(v, penalty), (v - penalty : U32), 0)

def init_knapsack(seed: U32) -> U32:
  U32.and(R.step(seed), 1023)

# Reprodução via pipeline de operadores reutilizáveis (Crossover Uniforme + Flip de 10 bits)
def reproduce(parent: U32, champ: U32, seed: U32) -> U32:
  Op.pipe(~U32, ~Op.cross_bits_uniform10, ~Op.mut_bit_flip10, parent, champ, seed)

def main_seed() -> U32:
  223344

def main() -> IO(Unit):
  +s0 = main_seed()
  # População: 32 indivíduos (profundidade 5)
  +pop0 = GA.gen_population(~U32, ~init_knapsack, ~fitness, 5n, s0)
  +best0 = GA.best_ind(U32, pop0)
  +g0 = GA.Ind.gene(U32, best0)
  +w0 = total_weight(g0)
  +v0 = total_value(g0)

  # Evolução por 35 gerações com elitismo no motor ga.bend
  +pop_final = GA.run_generations(~U32, ~reproduce, ~fitness, 35n, pop0, R.step(s0))
  +best_fin = GA.best_ind(U32, pop_final)
  +g_fin = GA.Ind.gene(U32, best_fin)
  +w_fin = total_weight(g_fin)
  +v_fin = total_value(g_fin)

  IO.print(
    "=== CENÁRIO 7: PROBLEMA DA MOCHILA (0/1 KNAPSACK) ===\n" ++
    "Itens: 10 itens com pesos e valores | Capacidade Máxima: " ++ U32.show(max_capacity()) ++ " kg\n" ++
    "População: 32 indivíduos (árvore binária profundidade 5)\n" ++
    "Geração 0  - Valor: " ++ U32.show(v0) ++ " | Peso: " ++ U32.show(w0) ++ " kg (Máscara: " ++ U32.show(g0) ++ ")\n" ++
    "Geração 35 - Valor: " ++ U32.show(v_fin) ++ " | Peso: " ++ U32.show(w_fin) ++ " kg (Máscara: " ++ U32.show(g_fin) ++ ")\n" ++
    "Solução Ótima (Valor >= 175 e Peso <= 80)? " ++ Bool.show(Bool.and(U32.is_ge(v_fin, 175), U32.is_le(w_fin, 80))) ++ "\n"
  )
