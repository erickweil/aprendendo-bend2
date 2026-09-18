import Base
import ./../ga.bend as GA
import ./../utils/random.bend as R
import ./../utils/bits.bend as B
import ./../utils/stats.bend as S

# ================================================================
# CENÁRIO 16: GENÉTICA DIPLÓIDE E PAISAGEM DINÂMICA (NON-STATIONARY)
# COM MOTOR GENÉRICO
# ================================================================
# Cromossomos Homólogos (2n): chr1, chr2 e máscara de dominância (dom)
# Expressão Fenotípica: (chr1 & dom) | (chr2 & ~dom)
# Gametogênese Meiótica: Recombinação homóloga na fertilização
# Paisagem Dinâmica: Inversão de ambiente (Alvo A -> Alvo B -> Alvo A)
# ================================================================

# Genoma Diplóide: 2 fitas homólogas de 32 bits + fita reguladora de dominância
type Diploid is Data:
  Diploid{chr1: U32, chr2: U32, dom: U32}

def make_diploid(+chr1: U32, +chr2: U32, +dom: U32) -> Diploid:
  Diploid{chr1, chr2, dom}

# Expressão Fenotípica por Seleção Alélica:
# Onde dom=1, o fenótipo expressa o alelo de chr1
# Onde dom=0, o fenótipo expressa o alelo de chr2 (chr1 permanece recessivo)
def express(d: Diploid) -> U32:
  Diploid{c1, c2, dom} = d
  +c1 = c1; +c2 = c2; +dom = dom
  +part1 = U32.and(c1, dom)
  +part2 = U32.and(c2, U32.not(dom))
  U32.or(part1, part2)

# Aptidão contra o ambiente atual: 32 - distância de Hamming em relação ao alvo
def eval_diploid(+d: Diploid, +env: U32) -> U32:
  +pheno = express(d)
  +diff = U32.xor(pheno, env)
  +dist = B.popcount(diff)
  (32 - dist : U32)

def env_target_a() -> U32:
  4278255360 # 0xFF00FF00

def env_target_b() -> U32:
  16711935   # 0x00FF00FF

def fitness_a(d: Diploid) -> U32:
  eval_diploid(d, env_target_a())

def fitness_b(d: Diploid) -> U32:
  eval_diploid(d, env_target_b())

def init_diploid(seed: U32) -> Diploid:
  +s0 = R.step(seed); +s1 = R.step(s0); +s2 = R.step(s1)
  make_diploid(s0, s1, s2)

# Fertilização e Recombinação Homóloga
def fertilize(+p1: Diploid, +p2: Diploid, +seed: U32) -> Diploid:
  Diploid{c1_1, c2_1, d1} = p1
  Diploid{c1_2, c2_2, d2} = p2
  +s0 = R.step(seed); +s1 = R.step(s0); +s2 = R.step(s1); +s3 = R.step(s2); +s4 = R.step(s3)
  +r0 = R.step(s4);   +r1 = R.step(r0); +r2 = R.step(r1)

  # Crossover homólogo das fitas
  +child_c1_raw = B.crossover_uniform(c1_1, c1_2, s0)
  +child_c2_raw = B.crossover_uniform(c2_1, c2_2, s1)
  +child_dom_raw = B.crossover_uniform(d1, d2, s2)

  # Mutação pontual
  +child_c1 = Bool.pick(U32, R.chance(s3, 30), B.mutate_bit(child_c1_raw, r0), child_c1_raw)
  +child_c2 = Bool.pick(U32, R.chance(s4, 30), B.mutate_bit(child_c2_raw, r1), child_c2_raw)

  # Mutação na dominância (chave de regulação epigenética)
  +child_dom_mut = Bool.pick(U32, R.chance(r2, 40), B.mutate_bit(child_dom_raw, r2), child_dom_raw)
  +child_dom = Bool.pick(U32, R.chance(s2, 15), U32.not(child_dom_mut), child_dom_mut)

  make_diploid(child_c1, child_c2, child_dom)

def reproduce(parent: Diploid, champ: Diploid, seed: U32) -> Diploid:
  fertilize(parent, champ, seed)

def main_seed() -> U32:
  77889911

def main() -> IO(Unit):
  +s0 = main_seed()

  # População inicial: 64 indivíduos diplóides (profundidade 6) sob Alvo A
  +pop0 = GA.gen_population(~Diploid, ~init_diploid, ~fitness_a, 6n, s0)
  +st0 = GA.population_stats(Diploid, pop0)

  # FASE 1: Adaptação ao Alvo A (35 gerações)
  +pop_p1 = GA.run_generations(~Diploid, ~reproduce, ~fitness_a, 35n, pop0, 112233)
  +st_p1 = GA.population_stats(Diploid, pop_p1)

  # TURBULÊNCIA 1: Mudança Ambiental Brusca para Alvo B (Inversão)
  +pop_shift1_raw = GA.reevaluate_pop(~Diploid, ~fitness_b, pop_p1)
  +st_shift1_raw = GA.population_stats(Diploid, pop_shift1_raw)

  # FASE 2: Adaptação ao Alvo B (35 gerações) com abrigo de alelos A no recessivo
  +pop_p2 = GA.run_generations(~Diploid, ~reproduce, ~fitness_b, 35n, pop_shift1_raw, 445566)
  +st_p2 = GA.population_stats(Diploid, pop_p2)

  # TURBULÊNCIA 2: Retorno ao Alvo Ancestral A (Verificação de Memória Genética)
  +pop_shift2_raw = GA.reevaluate_pop(~Diploid, ~fitness_a, pop_p2)
  +st_shift2_raw = GA.population_stats(Diploid, pop_shift2_raw)

  # FASE 3: Re-ativação Rápida da Memória Ancestral (20 gerações)
  +pop_p3 = GA.run_generations(~Diploid, ~reproduce, ~fitness_a, 20n, pop_shift2_raw, 778899)
  +st_p3 = GA.population_stats(Diploid, pop_p3)
  +best_fin = GA.best_ind(Diploid, pop_p3)
  +f_fin = GA.Ind.fit(Diploid, best_fin)

  IO.print(
    "=== CENÁRIO 16: GENÉTICA DIPLÓIDE E PAISAGEM DINÂMICA (NON-STATIONARY) ===\n" ++
    "Estrutura Genômica: 2n (2 Cromossomos Homólogos de 32 bits + Máscara de Dominância)\n" ++
    "Operador Biológico: Gametogênese Meiótica com Recombinação Homóloga\n" ++
    "População: 64 indivíduos diplóides (Árvore Fork-Join de Profundidade 6)\n" ++
    "Módulos da Lib: utils/bits.bend, random.bend, stats.bend e motor ga.bend\n\n" ++
    "--- GERAÇÃO 0 (Inicial) sob Alvo A ---\n" ++
    "  Estatísticas: " ++ S.PopStats.show(st0) ++ "\n\n" ++
    "--- FASE 1 (Geração 35 sob Alvo A) ---\n" ++
    "  Estatísticas: " ++ S.PopStats.show(st_p1) ++ "\n\n" ++
    "--- IMPACTO DO PRIMEIRO CHOQUE AMBIENTAL (Mudança Instantânea para Alvo B) ---\n" ++
    "  Aptidão Imediata pós-choque: " ++ S.PopStats.show(st_shift1_raw) ++ "\n\n" ++
    "--- FASE 2 (Geração 70 após Adaptação ao Alvo B) ---\n" ++
    "  Estatísticas: " ++ S.PopStats.show(st_p2) ++ "\n\n" ++
    "--- IMPACTO DO RETORNO AMBIENTAL AO ALVO A (Desafio de Memória Genética) ---\n" ++
    "  Aptidão Imediata pós-retorno: " ++ S.PopStats.show(st_shift2_raw) ++ "\n\n" ++
    "--- FASE 3 (20 Gerações pós-retorno ao Alvo A) ---\n" ++
    "  Estatísticas Finais: " ++ S.PopStats.show(st_p3) ++ "\n\n" ++
    "Memória Genética Diplóide Restaurou o Alvo Ancestral com Sucesso (>= 31 bits)? " ++
    Bool.show(U32.is_ge(f_fin, 31)) ++ "\n"
  )
