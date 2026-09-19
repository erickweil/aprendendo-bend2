import Base

# Limita um valor F32 entre [min_val, max_val]
def clamp(+val: F32, +min_val: F32, +max_val: F32) -> F32:
  +val_lo = Bool.pick(F32, F32.is_lt(val, min_val), min_val, val)
  Bool.pick(F32, F32.is_gt(val_lo, max_val), max_val, val_lo)

# Função de ativação Softsign / Fast Tanh: x / (1.0 + |x|)
# Mapeia (-inf, +inf) para (-1.0, 1.0) de forma contínua e sem overflow
def fast_tanh(+x: F32) -> F32:
  (x / (1.0 + F32.abs(x)) : F32)

# Conversão de graus para radianos
def deg_to_rad(+deg: F32) -> F32:
  ((deg * F32.pi()) / 180.0 : F32)

# ----------------------------------------------------------------
# BITS
# ----------------------------------------------------------------

# Quantidade de bits ligados (SWAR, O(1) sem laço)
def bit_count(+x: U32) -> U32:
  +a = U32.sub(x, U32.and(U32.shrn(x, 1n), 1431655765))
  +b = U32.add(U32.and(a, 858993459), U32.and(U32.shrn(a, 2n), 858993459))
  +c = U32.and(U32.add(b, U32.shrn(b, 4n)), 252645135)
  U32.shrn(U32.mul(c, 16843009), 24n)
