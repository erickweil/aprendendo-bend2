import Base

# Relação de Dominância de Pareto para Max(Valor) e Min(Custo/Peso):
# A domina B se: val(A) >= val(B) E cost(A) <= cost(B), com pelo menos uma desigualdade estrita
def dominates_min_max(+val_a: U32, +cost_a: U32, +val_b: U32, +cost_b: U32) -> Bool:
  +not_worse = Bool.and(U32.is_ge(val_a, val_b), U32.is_le(cost_a, cost_b))
  +strictly_better = Bool.or(U32.is_gt(val_a, val_b), U32.is_lt(cost_a, cost_b))
  Bool.and(not_worse, strictly_better)

# Relação de Dominância de Pareto para Max(Obj1) e Max(Obj2):
def dominates_max_max(+val1_a: U32, +val2_a: U32, +val1_b: U32, +val2_b: U32) -> Bool:
  +not_worse = Bool.and(U32.is_ge(val1_a, val1_b), U32.is_ge(val2_a, val2_b))
  +strictly_better = Bool.or(U32.is_gt(val1_a, val1_b), U32.is_gt(val2_a, val2_b))
  Bool.and(not_worse, strictly_better)

# Razão de densidade/eficiência: (val * 100) / (cost + 1)
def efficiency_ratio(+val: U32, +cost: U32) -> U32:
  U32.div(U32.mul(val, 100), (cost + 1 : U32))
