import Base
import ./../ga.bend as GA
import ./../utils/random.bend as R
import ./../operators.bend as Op

# ================================================================
# CENÁRIO 17: SOLVER DE HORÁRIO ESCOLAR MÉDIO (TIMETABLE SOLVER)
# ================================================================
# Especificação fiel ao solver original em Rust/TypeScript:
# - 3 Turmas (T0, T1, T2)
# - 5 Dias da Semana (Segunda a Sexta) x 4 Tempos = 20 tempos/turma
# - 60 slots no quadro total
# - 20 Disciplinas no total (sempre 2 ou 4 aulas cada)
# - 8 Professores com restrições rígidas de indisponibilidade
# - Invariante de carga horária 100% garantido por construção
# ================================================================
# Regras de Aptidão (1:1 com o solver original):
# 1. Choque de Professor (duas turmas com mesmo professor no mesmo tempo): -50 pts
# 2. Indisponibilidade de Professor (aula alocada em tempo que o prof não pode): -50 pts
# 3. Agrupamento em Blocos de 2 Aulas (aula isolada/desagrupada): -20 pts
# ================================================================

type Day4 is Data:
  D4{t0: U32, t1: U32, t2: U32, t3: U32}

def Day4.get(d: Day4, +idx: U32) -> U32:
  D4{t0, t1, t2, t3} = d
  Bool.pick(U32, U32.is_lt(idx, 2),
    Bool.pick(U32, U32.is_eq(idx, 0), t0, t1),
    Bool.pick(U32, U32.is_eq(idx, 2), t2, t3))

def Day4.set(d: Day4, +idx: U32, +val: U32) -> Day4:
  D4{t0, t1, t2, t3} = d
  D4{
    Bool.pick(U32, U32.is_eq(idx, 0), val, t0),
    Bool.pick(U32, U32.is_eq(idx, 1), val, t1),
    Bool.pick(U32, U32.is_eq(idx, 2), val, t2),
    Bool.pick(U32, U32.is_eq(idx, 3), val, t3)
  }

# Semana de 5 dias
type Week5 is Data:
  W5{d0: Day4, d1: Day4, d2: Day4, d3: Day4, d4: Day4}

def Week5.get_day(w: Week5, +dia: U32) -> Day4:
  W5{d0, d1, d2, d3, d4} = w
  Bool.pick(Day4, U32.is_lt(dia, 3),
    Bool.pick(Day4, U32.is_eq(dia, 0), d0,
      Bool.pick(Day4, U32.is_eq(dia, 1), d1, d2)),
    Bool.pick(Day4, U32.is_eq(dia, 3), d3, d4))

def Week5.set_day(w: Week5, +dia: U32, +day: Day4) -> Week5:
  W5{d0, d1, d2, d3, d4} = w
  W5{
    Bool.pick(Day4, U32.is_eq(dia, 0), day, d0),
    Bool.pick(Day4, U32.is_eq(dia, 1), day, d1),
    Bool.pick(Day4, U32.is_eq(dia, 2), day, d2),
    Bool.pick(Day4, U32.is_eq(dia, 3), day, d3),
    Bool.pick(Day4, U32.is_eq(dia, 4), day, d4)
  }

def Week5.get(w: Week5, +dia: U32, +tempo: U32) -> U32:
  +day = Week5.get_day(w, dia)
  Day4.get(day, tempo)

def Week5.set(+w: Week5, +dia: U32, +tempo: U32, +val: U32) -> Week5:
  +day = Week5.get_day(w, dia)
  +day_next = Day4.set(day, tempo, val)
  Week5.set_day(w, dia, day_next)

def Week5.swap(+w: Week5, +dia1: U32, +tempo1: U32, +dia2: U32, +tempo2: U32) -> Week5:
  +v1 = Week5.get(w, dia1, tempo1)
  +v2 = Week5.get(w, dia2, tempo2)
  +w1 = Week5.set(w, dia1, tempo1, v2)
  Week5.set(w1, dia2, tempo2, v1)

# Quadro Geral com 3 Turmas
type Quadro3 is Data:
  Q3{t0: Week5, t1: Week5, t2: Week5}

def Quadro3.get_turma(q: Quadro3, +t: U32) -> Week5:
  Q3{t0, t1, t2} = q
  Bool.pick(Week5, U32.is_eq(t, 0), t0,
    Bool.pick(Week5, U32.is_eq(t, 1), t1, t2))

def Quadro3.set_turma(q: Quadro3, +t: U32, +w: Week5) -> Quadro3:
  Q3{t0, t1, t2} = q
  Q3{
    Bool.pick(Week5, U32.is_eq(t, 0), w, t0),
    Bool.pick(Week5, U32.is_eq(t, 1), w, t1),
    Bool.pick(Week5, U32.is_eq(t, 2), w, t2)
  }

# ----------------------------------------------------------------
# MAPEAMENTO DE DISCIPLINAS (1..20) PARA PROFESSORES (1..8)
# ----------------------------------------------------------------
def prof_of(+disc: U32) -> U32:
  Bool.pick(U32, U32.is_le(disc, 7),
    Bool.pick(U32, U32.is_le(disc, 3),
      Bool.pick(U32, U32.is_eq(disc, 1), 1, Bool.pick(U32, U32.is_eq(disc, 2), 2, 3)),
      Bool.pick(U32, U32.is_le(disc, 5), 5, Bool.pick(U32, U32.is_eq(disc, 6), 6, 7))),
    Bool.pick(U32, U32.is_le(disc, 14),
      Bool.pick(U32, U32.is_le(disc, 10),
        Bool.pick(U32, U32.is_eq(disc, 8), 1, Bool.pick(U32, U32.is_eq(disc, 9), 2, 4)),
        Bool.pick(U32, U32.is_le(disc, 12), 5, 8)),
      Bool.pick(U32, U32.is_le(disc, 18),
        Bool.pick(U32, U32.is_le(disc, 16),
          Bool.pick(U32, U32.is_eq(disc, 15), 1, 2),
          Bool.pick(U32, U32.is_eq(disc, 17), 3, 4)),
        Bool.pick(U32, U32.is_eq(disc, 19), 6, 7))))

# ----------------------------------------------------------------
# INDISPONIBILIDADE DE PROFESSORES (Regra Rígida 1:1 com Rust)
# ----------------------------------------------------------------
def prof_unavailable(+prof: U32, +dia: U32, +tempo: U32) -> Bool:
  Bool.pick(Bool, U32.is_eq(prof, 1),
    # Prof 1 (Mat): indisponível Sexta tempos 2 e 3
    Bool.and(U32.is_eq(dia, 4), U32.is_ge(tempo, 2)),
    Bool.pick(Bool, U32.is_eq(prof, 2),
      # Prof 2 (Port): indisponível Segunda tempos 0 e 1
      Bool.and(U32.is_eq(dia, 0), U32.is_le(tempo, 1)),
      Bool.pick(Bool, U32.is_eq(prof, 3),
        # Prof 3 (Hist): indisponível Quarta tempos 2 e 3
        Bool.and(U32.is_eq(dia, 2), U32.is_ge(tempo, 2)),
        Bool.pick(Bool, U32.is_eq(prof, 4),
          # Prof 4 (Geo): indisponível Terça tempos 0 e 1
          Bool.and(U32.is_eq(dia, 1), U32.is_le(tempo, 1)),
          Bool.pick(Bool, U32.is_eq(prof, 5),
            # Prof 5 (Fis/Qui): indisponível Quinta inteira
            U32.is_eq(dia, 3),
            Bool.pick(Bool, U32.is_eq(prof, 6),
              # Prof 6 (Bio): disponível só Terça e Quinta
              Bool.or(U32.is_eq(dia, 0), Bool.or(U32.is_eq(dia, 2), U32.is_eq(dia, 4))),
              Bool.pick(Bool, U32.is_eq(prof, 7),
                # Prof 7 (Ing): disponível só Segunda e Quarta
                Bool.or(U32.is_eq(dia, 1), Bool.or(U32.is_eq(dia, 3), U32.is_eq(dia, 4))),
                # Prof 8 (Art/EdF): indisponível Sexta tempos 0 e 1
                Bool.and(U32.is_eq(dia, 4), U32.is_le(tempo, 1)))))))))

# ----------------------------------------------------------------
# CÁLCULO DE APTIDÃO 1:1
# ----------------------------------------------------------------

def eval_slot(+pA: U32, +pB: U32, +pC: U32, +dia: U32, +tempo: U32) -> U32:
  +c_ab = Bool.pick(U32, U32.is_eq(pA, pB), 50, 0)
  +c_ac = Bool.pick(U32, U32.is_eq(pA, pC), 50, 0)
  +c_bc = Bool.pick(U32, U32.is_eq(pB, pC), 50, 0)
  +coll = (c_ab + c_ac + c_bc : U32)

  +uA = Bool.pick(U32, prof_unavailable(pA, dia, tempo), 50, 0)
  +uB = Bool.pick(U32, prof_unavailable(pB, dia, tempo), 50, 0)
  +uC = Bool.pick(U32, prof_unavailable(pC, dia, tempo), 50, 0)
  +unavail = (uA + uB + uC : U32)

  (coll + unavail : U32)

def eval_day_grouping(day: Day4) -> U32:
  D4{t0, t1, t2, t3} = day
  +t0 = t0; +t1 = t1; +t2 = t2; +t3 = t3
  +p1_ok = U32.is_eq(t0, t1)
  +p2_ok = U32.is_eq(t2, t3)
  +mid_ok = U32.is_eq(t1, t2)
  Bool.pick(U32, Bool.and(p1_ok, p2_ok), 0,
    Bool.pick(U32, mid_ok, 40,
      Bool.pick(U32, Bool.or(p1_ok, p2_ok), 40, 80)))

def eval_turma_grouping(w: Week5) -> U32:
  W5{d0, d1, d2, d3, d4} = w
  +p0 = eval_day_grouping(d0)
  +p1 = eval_day_grouping(d1)
  +p2 = eval_day_grouping(d2)
  +p3 = eval_day_grouping(d3)
  +p4 = eval_day_grouping(d4)
  (p0 + p1 + p2 + p3 + p4 : U32)

def eval_day_prof(+d0: Day4, +d1: Day4, +d2: Day4, +dia: U32) -> U32:
  D4{a0, a1, a2, a3} = d0
  D4{b0, b1, b2, b3} = d1
  D4{c0, c1, c2, c3} = d2
  +s0 = eval_slot(prof_of(a0), prof_of(b0), prof_of(c0), dia, 0)
  +s1 = eval_slot(prof_of(a1), prof_of(b1), prof_of(c1), dia, 1)
  +s2 = eval_slot(prof_of(a2), prof_of(b2), prof_of(c2), dia, 2)
  +s3 = eval_slot(prof_of(a3), prof_of(b3), prof_of(c3), dia, 3)
  (s0 + s1 + s2 + s3 : U32)

def eval_prof_penalties(+w0: Week5, +w1: Week5, +w2: Week5) -> U32:
  W5{a0, a1, a2, a3, a4} = w0
  W5{b0, b1, b2, b3, b4} = w1
  W5{c0, c1, c2, c3, c4} = w2
  +d0 = eval_day_prof(a0, b0, c0, 0)
  +d1 = eval_day_prof(a1, b1, c1, 1)
  +d2 = eval_day_prof(a2, b2, c2, 2)
  +d3 = eval_day_prof(a3, b3, c3, 3)
  +d4 = eval_day_prof(a4, b4, c4, 4)
  (d0 + d1 + d2 + d3 + d4 : U32)

def evaluate_quadro(q: Quadro3) -> U32:
  Q3{t0, t1, t2} = q
  +t0 = t0; +t1 = t1; +t2 = t2
  +g0 = eval_turma_grouping(t0)
  +g1 = eval_turma_grouping(t1)
  +g2 = eval_turma_grouping(t2)
  +group_total = (g0 + g1 + g2 : U32)
  +prof_total = eval_prof_penalties(t0, t1, t2)
  (group_total + prof_total : U32)

def fitness(q: Quadro3) -> U32:
  +penalties = evaluate_quadro(q)
  Bool.pick(U32, U32.is_lt(penalties, 10000), (10000 - penalties : U32), 0)

# ----------------------------------------------------------------
# INICIALIZAÇÃO DO MULTICONJUNTO BASE (100% Carga Horária)
# ----------------------------------------------------------------
def base_turma0() -> Week5:
  W5{
    D4{1, 1, 2, 2},
    D4{3, 3, 4, 4},
    D4{1, 1, 2, 2},
    D4{3, 3, 5, 5},
    D4{6, 6, 7, 7}
  }

def base_turma1() -> Week5:
  W5{
    D4{8, 8, 9, 9},
    D4{10, 10, 11, 11},
    D4{8, 8, 9, 9},
    D4{10, 10, 12, 12},
    D4{13, 13, 14, 14}
  }

def base_turma2() -> Week5:
  W5{
    D4{15, 15, 16, 16},
    D4{17, 17, 18, 18},
    D4{15, 15, 16, 16},
    D4{17, 17, 18, 18},
    D4{19, 19, 20, 20}
  }

def init_quadro() -> Quadro3:
  Q3{base_turma0(), base_turma1(), base_turma2()}

# ----------------------------------------------------------------
# OPERADORES GENÉTICOS
# ----------------------------------------------------------------

def mutate_turma(+w: Week5, +s: U32) -> Week5:
  +s1 = R.step(s); +s2 = R.step(s1); +s3 = R.step(s2); +s4 = R.step(s3)
  +dia1 = U32.mod(s1, 5)
  +tempo1 = U32.mod(s2, 4)
  +dia2 = U32.mod(s3, 5)
  +tempo2 = U32.mod(s4, 4)
  Week5.swap(w, dia1, tempo1, dia2, tempo2)

def mutate_block_turma(+w: Week5, +s: U32) -> Week5:
  +s1 = R.step(s); +s2 = R.step(s1)
  +dia1 = U32.mod(s1, 5)
  +dia2 = U32.mod(s2, 5)
  +b1 = Bool.pick(U32, U32.is_zero(U32.and(s1, 1)), 0, 2)
  +b2 = Bool.pick(U32, U32.is_zero(U32.and(s2, 1)), 0, 2)
  +w_step1 = Week5.swap(w, dia1, b1, dia2, b2)
  Week5.swap(w_step1, dia1, U32.inc(b1), dia2, U32.inc(b2))

def mutate_quadro(+q: Quadro3, +s: U32) -> Quadro3:
  +s1 = R.step(s); +s2 = R.step(s1); +s3 = R.step(s2)
  +turma_id = U32.mod(s1, 3)
  +is_block = U32.is_zero(U32.and(s2, 1))
  +target_turma = Quadro3.get_turma(q, turma_id)
  +mutated_turma = Bool.pick(Week5, is_block,
    mutate_block_turma(target_turma, s3),
    mutate_turma(target_turma, s3))
  Quadro3.set_turma(q, turma_id, mutated_turma)

def shuffle_quadro(+q: Quadro3, +s: U32) -> Quadro3:
  +s1 = R.step(s); +s2 = R.step(s1); +s3 = R.step(s2); +s4 = R.step(s3)
  +s5 = R.step(s4); +s6 = R.step(s5); +s7 = R.step(s6); +s8 = R.step(s7)
  +q1 = mutate_quadro(q, s1)
  +q2 = mutate_quadro(q1, s2)
  +q3 = mutate_quadro(q2, s3)
  +q4 = mutate_quadro(q3, s4)
  +q5 = mutate_quadro(q4, s5)
  +q6 = mutate_quadro(q5, s6)
  +q7 = mutate_quadro(q6, s7)
  mutate_quadro(q7, s8)

def init_gene(seed: U32) -> Quadro3:
  shuffle_quadro(init_quadro(), seed)

def crossover_quadro(a: Quadro3, b: Quadro3, +mask: U32) -> Quadro3:
  Q3{t0_a, t1_a, t2_a} = a
  Q3{t0_b, t1_b, t2_b} = b
  Q3{
    Bool.pick(Week5, U32.is_ne(U32.and(mask, 1), 0), t0_a, t0_b),
    Bool.pick(Week5, U32.is_ne(U32.and(mask, 2), 0), t1_a, t1_b),
    Bool.pick(Week5, U32.is_ne(U32.and(mask, 4), 0), t2_a, t2_b)
  }

def pick_better_q3(c: Bool, cand: Quadro3, +fc: U32, base: Quadro3, +fb: U32) -> GA.Ind<Quadro3>:
  match c:
    case True{}:
      GA.Ind{cand, fc}
    case False{}:
      GA.Ind{base, fb}

def reproduce_eval(parent: Quadro3, champ: Quadro3, seed: U32) -> GA.Ind<Quadro3>:
  +parent = parent
  +s1 = R.step(seed); +s2 = R.step(s1); +s3 = R.step(s2)
  +crossed = crossover_quadro(parent, champ, s1)
  +cand = mutate_quadro(crossed, s2)
  +f_cand = fitness(cand)
  +f_base = fitness(crossed)
  pick_better_q3(U32.is_ge(f_cand, f_base), cand, f_cand, crossed, f_base)

def reproduce(parent: Quadro3, champ: Quadro3, seed: U32) -> Quadro3:
  GA.Ind.gene(Quadro3, reproduce_eval(parent, champ, seed))

# ----------------------------------------------------------------
# APRESENTAÇÃO E RELATÓRIO
# ----------------------------------------------------------------

def Day4.show(d: Day4) -> String:
  D4{t0, t1, t2, t3} = d
  "[" ++ U32.show(t0) ++ " " ++ U32.show(t1) ++ " | " ++ U32.show(t2) ++ " " ++ U32.show(t3) ++ "]"

def Week5.show(w: Week5) -> String:
  W5{d0, d1, d2, d3, d4} = w
  "\n    Seg: " ++ Day4.show(d0) ++
  "\n    Ter: " ++ Day4.show(d1) ++
  "\n    Qua: " ++ Day4.show(d2) ++
  "\n    Qui: " ++ Day4.show(d3) ++
  "\n    Sex: " ++ Day4.show(d4)

def Quadro3.show(q: Quadro3) -> String:
  Q3{t0, t1, t2} = q
  "\n  -- Turma 0 --" ++ Week5.show(t0) ++
  "\n  -- Turma 1 --" ++ Week5.show(t1) ++
  "\n  -- Turma 2 --" ++ Week5.show(t2) ++ "\n"

def main_seed() -> U32:
  88442211

def main() -> IO(Unit):
  +s0 = main_seed()
  # População: 32 indivíduos (árvore binária profundidade 5)
  +pop0 = GA.gen_population(~Quadro3, ~init_gene, ~fitness, 5n, s0)
  +best0 = GA.best_ind(Quadro3, pop0)
  +g0 = GA.Ind.gene(Quadro3, best0)
  +f0 = GA.Ind.fit(Quadro3, best0)
  +p0 = evaluate_quadro(g0)

  # 120 gerações com reprodução avaliada e elitismo estrito
  +pop_final = GA.run_generations_eval(~Quadro3, ~reproduce_eval, 120n, pop0, R.step(s0))
  +best_fin = GA.best_ind(Quadro3, pop_final)
  +g_fin = GA.Ind.gene(Quadro3, best_fin)
  +f_fin = GA.Ind.fit(Quadro3, best_fin)
  +p_fin = evaluate_quadro(g_fin)

  IO.print(
    "=== CENÁRIO 17: SOLVER DE HORÁRIO ESCOLAR MÉDIO ===\n" ++
    "Estrutura: 3 Turmas x 5 Dias x 4 Tempos = 60 slots | 20 Disciplinas | 8 Professores\n" ++
    "Regras 1:1 com Rust: Choque Prof (-50 pts), Indisponibilidade (-50 pts), Agrupamento Bloco 2 (-20 pts)\n" ++
    "Invariante de Carga Horária: 100% garantido por construção (swaps intra-turma)\n" ++
    "População: 32 indivíduos (árvore binária profundidade 5)\n\n" ++
    "Geração 0   - Penalidades: " ++ U32.show(p0) ++ " (Fitness: " ++ U32.show(f0) ++ " / 10000)" ++ Quadro3.show(g0) ++ "\n" ++
    "Geração 120 - Penalidades: " ++ U32.show(p_fin) ++ " (Fitness: " ++ U32.show(f_fin) ++ " / 10000)" ++ Quadro3.show(g_fin) ++ "\n" ++
    "Quadro Válido Encontrado (0 penalidades)? " ++ Bool.show(U32.is_zero(p_fin)) ++ "\n"
  )
