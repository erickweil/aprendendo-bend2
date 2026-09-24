import Base
import ./../utils/io.bend as IOU
import ./../utils/random.bend as R

# ESTIMANDO π COM SORTEIOS, EM PARALELO.
#
# Sorteia pontos no quadrado [0, 1] x [0, 1]; a fração que cai dentro do
# quarto de círculo (x² + y² <= 1) tende a π/4.
#
# Bend é puro: não há gerador aleatório global. A "semente" é o estado, e
# passa de mão em mão (utils/random.bend: `R.step` avança, `R.unit` dá um F32
# em (0, 1]). Numa chamada paralela, cada lado recebe um fluxo DERIVADO com
# `R.split.fst`/`R.split.snd`, que não se sobrepõem: se os dois lados usassem
# a mesma semente, sorteariam os mesmos pontos (AGENTS.md, Armadilha 9).
#
# Só a semente inicial vem do sistema (`IOU.semente`, uma syscall); dali em
# diante tudo é determinístico: a mesma semente dá o mesmo resultado.

# `k` pontos a partir da semente `s`; conta os que caem dentro
def amostra(k: Nat, +s: U32, +dentro: U32) -> U32:
  match k:
    case 0n:
      dentro
    case 1n+p:
      +x = R.unit(s)
      +s2 = R.step(s)
      +y = R.unit(s2)
      amostra(p, R.step(s2), (dentro + Bool.to_u32((x * x + y * y <= 1.0 : F32)) : U32))

# 2^prof tarefas, cada uma com `n` pontos e o seu próprio fluxo
def paralelo(prof: Nat, +s: U32, +n: U32) -> U32:
  match prof:
    case 0n:
      amostra(U32.to_nat(n), s, 0)
    case 1n+ +p:
      a b = paralelo(p, R.split.fst(s), n) paralelo(p, R.split.snd(s), n)
      (a + b : U32)

# Uso: monte_carlo [milhões de pontos=16] [semente=0: aleatória]
#   ../bin/monte_carlo 256 7 --threads 1      (compare com --threads 12)
#
# Medido no nativo (256 milhões de pontos): 1,31 s com 1 thread, 0,45 s com
# 4 e 0,24 s com 8 ou 12 (5,4×). Nenhuma memória compartilhada, trabalho
# igual em cada tarefa: é o melhor caso de paralelismo desta máquina.
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +ns : List<&2, Maybe<&2, U32>> = IOU.numbers(args)
    +milhoes : U32 = U32.max(IOU.num_at(ns, 0n, 16), 1)
    s : U32 <- IOU.semente(IOU.num_at(ns, 1n, 0))
    +t0 : Nat <- IO.now()
    # 64 tarefas de (milhões / 64) milhões de pontos cada
    +total : U32 = (milhoes * 1048576 : U32)
    +dentro : U32 = paralelo(6n, s, (total / 64 : U32))
    +pi : F32 = (4.0 * U32.to_f32(dentro) / U32.to_f32(total) : F32)
    IO.print("π ≈ " ++ F32.show(pi) ++ " com " ++ U32.show(total) ++ " pontos (erro " ++ F32.show(F32.abs((pi - F32.pi() : F32))) ++ ")")
    dt : String <- IOU.tempo_desde(t0)
    IO.print("  " ++ dt)
