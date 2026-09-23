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

# Menor potência de 2 maior ou igual a x (o `next_power_of_two` do Rust):
# 6 -> 8, 13 -> 16, 8 -> 8, 0 -> 1, 1 -> 1. Sem laço: espalha o bit mais alto
# de x - 1 para todos os bits abaixo dele e soma 1.
# Acima de 2^31 não existe resposta em U32 e o resultado dá a volta para 0.
def next_pow2(+x: U32) -> U32:
  # x = 0 vira 0 aqui (e não 0xFFFFFFFF), para que o resultado seja 1
  +a = U32.sub(U32.add(x, Bool.to_u32(U32.is_zero(x))), 1)
  +b = U32.or(a, U32.shrn(a, 1n))
  +c = U32.or(b, U32.shrn(b, 2n))
  +d = U32.or(c, U32.shrn(c, 4n))
  +e = U32.or(d, U32.shrn(d, 8n))
  U32.add(U32.or(e, U32.shrn(e, 16n)), 1)

# Expoente da potência de 2 que cabe x, arredondado para cima, como Nat:
# 8 -> 3n, 16 -> 4n, 6 -> 3n, 13 -> 4n, 1 -> 0n, 0 -> 0n, e 32n acima de 2^31
# (next_pow2 dá 0 ali, e 0 - 1 tem os 32 bits ligados).
# É a profundidade de um array com pelo menos x slots: `[0 : U32^log2_ceil(x)]`.
# (O `U32.log2` da Base arredonda para BAIXO e faz um laço de 32 passos.)
def log2_ceil(+x: U32) -> Nat:
  # next_pow2 = 2^k, e 2^k - 1 tem exatamente k bits ligados
  U32.to_nat(bit_count(U32.sub(next_pow2(x), 1)))
