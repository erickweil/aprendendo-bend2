import Base

# ================================================================
# BEND 2 GENETIC UTILS - MATH (Funções Matemáticas e Ativação F32)
# ================================================================

# Limita um valor F32 entre [min_val, max_val]
def clamp(+val: F32, +min_val: F32, +max_val: F32) -> F32:
  +val_lo = Bool.pick(F32, F32.is_lt(val, min_val), min_val, val)
  Bool.pick(F32, F32.is_gt(val_lo, max_val), max_val, val_lo)

# Função de ativação Softsign / Fast Tanh: x / (1.0 + |x|)
# Mapeia (-inf, +inf) para (-1.0, 1.0) de forma contínua e sem overflow
def fast_tanh(+x: F32) -> F32:
  (x / (1.0 + F32.abs(x)) : F32)

# Unidade Linear Retificada (ReLU)
def relu(+x: F32) -> F32:
  Bool.pick(F32, F32.is_gt(x, 0.0), x, 0.0)

# Produto escalar de 4 dimensões (Dot Product 4D)
def dot4(+x0: F32, +x1: F32, +x2: F32, +x3: F32,
         +w0: F32, +w1: F32, +w2: F32, +w3: F32) -> F32:
  ((x0 * w0) + (x1 * w1) + (x2 * w2) + (x3 * w3) : F32)

# Conversão de graus para radianos
def deg_to_rad(+deg: F32) -> F32:
  ((deg * F32.pi()) / 180.0 : F32)
