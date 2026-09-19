import Base
import ./../../utils/random.bend as R
import ./../../utils/io.bend as IOHelper
import ./../utils/bits.bend as Bits
import ./../ga.bend as GA
import ./../operators.bend as Op

# ================================================================
# CENÁRIO 1: BIT MAXING (ONE-MAX) COM MOTOR GENÉTICO GENÉRICO
# ================================================================
# Problema: Encontrar um número de 32 bits com todos os bits ligados (32).
# Toda a lógica genérica (árvore, elitismo, estatísticas, fork-join)
# é delegada para o motor ga.bend e utilitários.
# ================================================================

# Inicialização aleatória do genoma de 32 bits
def init_gene(seed: U32) -> U32:
  R.step(seed)

# Função de Aptidão (Fitness): contar bits '1' via SWAR O(1)
def fitness(gene: U32) -> U32:
  Bits.popcount(gene)

# Reprodução: pipeline Crossover Uniforme + Flip de 1 bit, montado pelo
# combinador `Op.pipe` de operators.bend.
# Nota: o `problem_onemax.rs` original usa Single-Point Crossover +
# `mutation_replace` por gene (P_c = P_m = 0.9, taxa por gene 1/32); essa
# configuração também converge aqui (`Op.pipe_rated(~U32, ~Op.cross_bits_1point,
# ~mut, 90, 90, ...)`), porém precisa de 60 gerações em vez de 25, porque o
# motor em árvore usa elitismo com o campeão no lugar de seleção por torneio.
def reproduce(parent: U32, champ: U32, seed: U32) -> U32:
  Op.pipe(~U32, ~Op.cross_bits_uniform, ~Op.mut_bit_flip32, parent, champ, seed)

def main() -> IO(Unit):
    +s0 = {12345678 : U32}
    # População inicial: 32 indivíduos (árvore de profundidade 5). `first_gen`
    # já devolve o campeão junto, descoberto na própria construção da árvore.
    +gen0 = GA.first_gen(~U32, ~init_gene, ~fitness, 5n, s0)
    +gen0 = gen0
    +f0 = GA.Gen.bfit(U32, gen0)

    # Evolução por 25 gerações com elitismo no motor genérico ga.bend.
    # O campeão atravessa o laço dentro do `Gen`, então ler o resultado não
    # percorre a árvore final de novo.
    +gen_fin = GA.run_gen_loop(~U32, ~reproduce, ~fitness, 25n, gen0, R.step(s0))
    +best_fin = GA.Gen.best(U32, gen_fin)
    +f_fin = GA.Ind.fit(U32, best_fin)
    +g_fin = GA.Ind.gene(U32, best_fin)

    IO.print(
      "=== CENÁRIO 1: BIT MAXING (ONE-MAX) ===\n" ++
      "População: 32 indivíduos (árvore binária profundidade 5)\n" ++
      "Geração 0 - Melhor Fitness: " ++ U32.show(f0) ++ " / 32 bits\n" ++
      "Geração 25 - Melhor Fitness: " ++ U32.show(f_fin) ++ " / 32 bits\n" ++
      "Gene final (U32): " ++ U32.show(g_fin) ++ "\n" ++
      "Solução Ótima Atingida? " ++ Bool.show(U32.is_eq(f_fin, 32)) ++ "\n"
    )
