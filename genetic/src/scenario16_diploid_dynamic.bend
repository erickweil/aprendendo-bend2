import Base
import ./../utils/random.bend as R
import ./../utils/bits.bend as B
import ./../utils/poptree.bend as T
import ./../utils/stats.bend as S

# ================================================================
# CENÁRIO 16: GENÉTICA DIPLÓIDE E PAISAGEM DINÂMICA (NON-STATIONARY)
# ================================================================
# Arquitetura:
# - Cromossomos Homólogos (2n): chr1, chr2 e máscara de dominância (dom)
# - Expressão Fenotípica: (chr1 & dom) | (chr2 & ~dom)
# - Gametogênese Meiótica: Crossing-over intra-genômico na produção de gametas
# - Memória Genética de Longo Prazo: Alelos recessivos protegidos da seleção
# - Paisagem Dinâmica: Inversão brusca de ambiente (Alvo A -> Alvo B -> Alvo A)
# - Módulos: utils/random.bend, utils/bits.bend, utils/poptree.bend, utils/stats.bend
# ================================================================

# Genoma Diplóide: 2 fitas homólogas de 32 bits + fita reguladora de dominância
type Diploid is Data:
  Diploid{chr1: U32, chr2: U32, dom: U32}

def make_diploid(+chr1: U32, +chr2: U32, +dom: U32) -> Diploid:
  Diploid{chr1, chr2, dom}

# Expressão Fenotípica por Seleção Alélica:
# Onde dom=1, o fenótipo expressa o alelo de chr1
# Onde dom=0, o fenótipo expressa o alelo de chr2 (chr1 permanece recessivo/abrigado)
def express(d: Diploid) -> U32:
  Diploid{c1, c2, dom} = d
  +c1 = c1
  +c2 = c2
  +dom = dom
  +part1 = U32.and(c1, dom)
  +part2 = U32.and(c2, U32.not(dom))
  U32.or(part1, part2)

# Aptidão contra o ambiente atual: 32 - distância de Hamming em relação ao alvo
def eval_diploid(+d: Diploid, +env: U32) -> U32:
  +pheno = express(d)
  +diff = U32.xor(pheno, env)
  +dist = B.popcount(diff)
  (32 - dist : U32)

# Indivíduo Diplóide
type DipInd is Data:
  DipInd{genome: Diploid, fit: U32}

def make_dip_ind(+g: Diploid, +env: U32) -> DipInd:
  DipInd{g, eval_diploid(g, env)}

def DipInd.genome(i: DipInd) -> Diploid:
  DipInd{g, _} = i
  g

def DipInd.fit(i: DipInd) -> U32:
  DipInd{_, f} = i
  f

def pick_better_dip(+a: DipInd, +b: DipInd) -> DipInd:
  Bool.pick(DipInd, U32.is_ge(DipInd.fit(a), DipInd.fit(b)), a, b)

# Campeão da População em Árvore
def best_dip_pop(tree: T.PopTree<DipInd>) -> DipInd:
  match tree:
    case T.Leaf{ind}:
      ind
    case T.Node{left, right}:
      bl br = best_dip_pop(left) best_dip_pop(right)
      pick_better_dip(bl, br)

# Redução de Estatísticas Agregadas em O(log N)
def stats_dip_pop(tree: T.PopTree<DipInd>) -> S.PopStats:
  match tree:
    case T.Leaf{ind}:
      S.leaf_stats(DipInd.fit(ind))
    case T.Node{left, right}:
      sl sr = stats_dip_pop(left) stats_dip_pop(right)
      S.merge_stats(sl, sr)

# Fertilização e Recombinação Homóloga:
# Fita homóloga 1 recombina com fita 1 do parceiro
# Fita homóloga 2 recombina com fita 2 do parceiro
# Fita de dominância regula a expressão e permite resgate de memória ancestral
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

# Reprodução Paralela na Árvore Fork-Join
def reproduce_dip(tree: T.PopTree<DipInd>, +seed: U32, +champ: DipInd, +env: U32) -> T.PopTree<DipInd>:
  match tree:
    case T.Leaf{+ind}:
      +s1 = R.step(seed)
      +child_g = fertilize(DipInd.genome(ind), DipInd.genome(champ), s1)
      +child_ind = make_dip_ind(child_g, env)
      T.leaf(DipInd, pick_better_dip(child_ind, ind))
    case T.Node{left, right}:
      +seed = seed
      +champ = champ
      +env = env
      l r = reproduce_dip(left, R.split.fst(seed), champ, env) reproduce_dip(right, R.split.snd(seed), champ, env)
      T.node(DipInd, l, r)

def step_dip_gen(+tree: T.PopTree<DipInd>, +seed: U32, +env: U32) -> T.PopTree<DipInd>:
  +champ = best_dip_pop(tree)
  reproduce_dip(tree, seed, champ, env)

def run_dip_epochs(g: Nat, tree: T.PopTree<DipInd>, +seed: U32, +env: U32) -> T.PopTree<DipInd>:
  match g:
    case 0n:
      tree
    case 1n+p:
      +next_seed = R.step(seed)
      +next_tree = step_dip_gen(tree, seed, env)
      run_dip_epochs(p, next_tree, next_seed, env)

# Re-avaliação Concorrente de toda a População sob Novo Regime Ambiental
def reevaluate_dip(tree: T.PopTree<DipInd>, +env: U32) -> T.PopTree<DipInd>:
  match tree:
    case T.Leaf{+ind}:
      +g = DipInd.genome(ind)
      T.leaf(DipInd, make_dip_ind(g, env))
    case T.Node{left, right}:
      +env = env
      l r = reevaluate_dip(left, env) reevaluate_dip(right, env)
      T.node(DipInd, l, r)

# Geração de População Inicial Diplóide
def gen_rand_diploid(+seed: U32) -> Diploid:
  +s0 = R.step(seed); +s1 = R.step(s0); +s2 = R.step(s1)
  make_diploid(s0, s1, s2)

def gen_dip_pop(d: Nat, +seed: U32, +env: U32) -> T.PopTree<DipInd>:
  match d:
    case 0n:
      T.leaf(DipInd, make_dip_ind(gen_rand_diploid(seed), env))
    case 1n+p:
      +p = p
      +seed = seed
      +env = env
      l r = gen_dip_pop(p, R.split.fst(seed), env) gen_dip_pop(p, R.split.snd(seed), env)
      T.node(DipInd, l, r)

# Ambientes Alternantes (Alvo A = 0xFF00FF00, Alvo B = 0x00FF00FF)
def env_target_a() -> U32:
  4278255360 # 0xFF00FF00

def env_target_b() -> U32:
  16711935   # 0x00FF00FF

def main_seed() -> U32:
  77889911

def main() -> IO(Unit):
  +s0 = main_seed()
  +target_a = env_target_a()
  +target_b = env_target_b()

  # População inicial: 64 indivíduos diplóides (profundidade 6)
  +pop0 = gen_dip_pop(6n, s0, target_a)
  +st0 = stats_dip_pop(pop0)

  # FASE 1: Adaptação ao Alvo A (35 gerações)
  +pop_p1 = run_dip_epochs(35n, pop0, 112233, target_a)
  +st_p1 = stats_dip_pop(pop_p1)

  # TURBULÊNCIA 1: Mudança Ambiental Brusca para Alvo B (Inversão)
  +pop_shift1_raw = reevaluate_dip(pop_p1, target_b)
  +st_shift1_raw = stats_dip_pop(pop_shift1_raw)

  # FASE 2: Adaptação ao Alvo B (35 gerações) com abrigo de alelos A no recessivo
  +pop_p2 = run_dip_epochs(35n, pop_shift1_raw, 445566, target_b)
  +st_p2 = stats_dip_pop(pop_p2)

  # TURBULÊNCIA 2: Retorno ao Alvo Ancestral A (Verificação de Memória Genética)
  +pop_shift2_raw = reevaluate_dip(pop_p2, target_a)
  +st_shift2_raw = stats_dip_pop(pop_shift2_raw)

  # FASE 3: Re-ativação Rápida da Memória Ancestral (20 gerações)
  +pop_p3 = run_dip_epochs(20n, pop_shift2_raw, 778899, target_a)
  +st_p3 = stats_dip_pop(pop_p3)

  IO.print(
    "=== CENÁRIO 16: GENÉTICA DIPLÓIDE E PAISAGEM DINÂMICA (NON-STATIONARY) ===\n" ++
    "Estrutura Genômica: 2n (2 Cromossomos Homólogos de 32 bits + Máscara de Dominância)\n" ++
    "Operador Biológico: Gametogênese Meiótica com Recombinação Homóloga\n" ++
    "População: 64 indivíduos diplóides (Árvore Fork-Join de Profundidade 6)\n" ++
    "Módulos da Lib: utils/bits.bend, random.bend, poptree.bend e stats.bend\n\n" ++
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
    Bool.show(U32.is_ge(DipInd.fit(best_dip_pop(pop_p3)), 31)) ++ "\n"
  )
