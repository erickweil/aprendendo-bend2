import Base
import ./math.bend as M
import ./random.bend as R

# ================================================================
# BEND 2 GENETIC UTILS - VETOR CONTÍNUO 4D (vec4.bend)
# ================================================================
# Representação imutável de um ponto em R^4 com coordenadas F32.
# Utilizada em otimização numérica contínua (Evolução Diferencial,
# Rastrigin, Sphere, Rosenbrock e demais paisagens multi-modais).
# ================================================================

type Vec4 is Data:
  Vec4{x0: F32, x1: F32, x2: F32, x3: F32}

def make_vec4(+x0: F32, +x1: F32, +x2: F32, +x3: F32) -> Vec4:
  Vec4{x0, x1, x2, x3}

# Vetor uniforme no hipercubo [lo, hi]^4, com as 4 coordenadas
# amostradas de sementes sucessivas do Xorshift32
def rnd_vec4(+seed: U32, +lo: F32, +hi: F32) -> Vec4:
  +s0 = R.step(seed)
  +s1 = R.step(s0)
  +s2 = R.step(s1)
  +s3 = R.step(s2)
  Vec4{
    M.rnd_range_f32(s0, lo, hi),
    M.rnd_range_f32(s1, lo, hi),
    M.rnd_range_f32(s2, lo, hi),
    M.rnd_range_f32(s3, lo, hi)
  }

def Vec4.show(v: Vec4) -> String:
  Vec4{x0, x1, x2, x3} = v
  "(" ++ F32.show(x0) ++ ", " ++ F32.show(x1) ++ ", " ++ F32.show(x2) ++ ", " ++ F32.show(x3) ++ ")"
