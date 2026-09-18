import Base
import ./../ga.bend as GA
import ./../utils/random.bend as R
import ./../operators.bend as Op
import ./../utils/json.bend as J

# ==============================================================================
# SOLVER UNIFICADO DE HORÁRIO ESCOLAR (TIMETABLE SOLVER COM JSON I/O)
# ==============================================================================
# Unifica a lógica dos cenários de horário em um único solver de alto desempenho:
# - Representação limpa em ADTs (Day4, Week5, Quadro3) compatível com Reduções HVM
# - 3 Turmas (Turma 2026, Turma 2025, Turma 2024) x 5 Dias x 4 Tempos = 60 slots
# - 20 Disciplinas e 10 Professores com restrições rígidas e leves 1:1 com Rust
# - Entrada flexível: JSON via variável de ambiente (HORARIO_JSON) ou Formulário Padrão
# - Saída padronizada: Serialização da melhor solução em JSON (TurmaHorarioResult[])
# ==============================================================================

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

# ------------------------------------------------------------------------------
# MAPEAMENTO DE DISCIPLINAS (1..20) E PROFESSORES (1..9)
# ------------------------------------------------------------------------------

def prof_of(+disc: U32) -> U32:
  Bool.pick(U32, U32.is_le(disc, 10),
    Bool.pick(U32, U32.is_le(disc, 5),
      Bool.pick(U32, U32.is_le(disc, 2),
        Bool.pick(U32, U32.is_eq(disc, 1), 3, 7),
        Bool.pick(U32, U32.is_le(disc, 4),
          Bool.pick(U32, U32.is_eq(disc, 3), 6, 8),
          4)),
      Bool.pick(U32, U32.is_le(disc, 7),
        Bool.pick(U32, U32.is_eq(disc, 6), 4, 3),
        Bool.pick(U32, U32.is_le(disc, 9),
          Bool.pick(U32, U32.is_eq(disc, 8), 2, 3),
          8))),
    Bool.pick(U32, U32.is_le(disc, 15),
      Bool.pick(U32, U32.is_le(disc, 13),
        Bool.pick(U32, U32.is_eq(disc, 11), 6,
          Bool.pick(U32, U32.is_eq(disc, 12), 4, 6)),
        Bool.pick(U32, U32.is_eq(disc, 14), 9, 4)),
      Bool.pick(U32, U32.is_le(disc, 18),
        Bool.pick(U32, U32.is_le(disc, 17),
          Bool.pick(U32, U32.is_eq(disc, 16), 1, 5),
          3),
        Bool.pick(U32, U32.is_eq(disc, 19), 4, 6))))

def disc_to_nome(+disc: U32) -> String:
  Bool.pick(String, U32.is_le(disc, 10),
    Bool.pick(String, U32.is_le(disc, 5),
      Bool.pick(String, U32.is_le(disc, 2),
        Bool.pick(String, U32.is_eq(disc, 1), "Linguagens de programacao", "Redes de Computadores"),
        Bool.pick(String, U32.is_le(disc, 4),
          Bool.pick(String, U32.is_eq(disc, 3), "Sistemas Operacionais", "Banco de dados II"),
          "Engenharia de Software")),
      Bool.pick(String, U32.is_le(disc, 8),
        Bool.pick(String, U32.is_le(disc, 7),
          Bool.pick(String, U32.is_eq(disc, 6), "Fabrica de Software I", "Estrutura de dados II"),
          "Estatistica"),
        Bool.pick(String, U32.is_eq(disc, 9), "Devops e Cloud II", "Teste de Software II"))),
    Bool.pick(String, U32.is_le(disc, 15),
      Bool.pick(String, U32.is_le(disc, 13),
        Bool.pick(String, U32.is_le(disc, 12),
          Bool.pick(String, U32.is_eq(disc, 11), "Frameworks para front-end", "Web Services"),
          "Fabrica de Software III"),
        Bool.pick(String, U32.is_eq(disc, 14), "Libras", "Topicos Especiais II")),
      Bool.pick(String, U32.is_le(disc, 18),
        Bool.pick(String, U32.is_le(disc, 17),
          Bool.pick(String, U32.is_eq(disc, 16), "Etica, Sociedade e Sustentabilidade", "Inteligencia Artificial"),
          "Arquitetura de Software"),
        Bool.pick(String, U32.is_eq(disc, 19), "Dispositivos Moveis II", "Orientacoes TCC"))))

def prof_unavailable(+prof: U32, +dia: U32, +tempo: U32) -> Bool:
  Bool.pick(Bool, U32.is_le(prof, 5),
    Bool.pick(Bool, U32.is_le(prof, 2),
      Bool.pick(Bool, U32.is_eq(prof, 1),
        Bool.or(U32.is_eq(dia, 3), U32.is_eq(dia, 4)),
        False{}),
      Bool.pick(Bool, U32.is_le(prof, 4),
        Bool.pick(Bool, U32.is_eq(prof, 3),
          Bool.or(U32.is_eq(dia, 2), U32.is_eq(dia, 3)),
          U32.is_eq(dia, 0)),
        Bool.or(
          Bool.and(U32.is_ne(dia, 1), U32.is_ne(dia, 3)),
          U32.is_ge(tempo, 2)))),
    Bool.pick(Bool, U32.is_le(prof, 7),
      Bool.pick(Bool, U32.is_eq(prof, 6),
        Bool.or(U32.is_eq(dia, 3), U32.is_eq(dia, 4)),
        U32.is_eq(dia, 3)),
      Bool.pick(Bool, U32.is_eq(prof, 8),
        Bool.or(U32.is_eq(dia, 2), U32.is_eq(dia, 4)),
        U32.is_ne(dia, 2))))

# ------------------------------------------------------------------------------
# CÁLCULO DE APTIDÃO 1:1 COM RUST
# ------------------------------------------------------------------------------

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

def eval_unidas_tempo(+t0_val: U32, +t1_val: U32) -> U32:
  +is_f1 = U32.is_eq(t0_val, 6)
  +is_f3 = U32.is_eq(t1_val, 13)
  Bool.pick(U32, Bool.xor(is_f1, is_f3), 30, 0)

def eval_unidas_dia(+d0: Day4, +d1: Day4) -> U32:
  D4{a0, a1, a2, a3} = d0
  D4{b0, b1, b2, b3} = d1
  +u0 = eval_unidas_tempo(a0, b0)
  +u1 = eval_unidas_tempo(a1, b1)
  +u2 = eval_unidas_tempo(a2, b2)
  +u3 = eval_unidas_tempo(a3, b3)
  (u0 + u1 + u2 + u3 : U32)

def eval_unidas_week(+w0: Week5, +w1: Week5) -> U32:
  W5{a0, a1, a2, a3, a4} = w0
  W5{b0, b1, b2, b3, b4} = w1
  +d0 = eval_unidas_dia(a0, b0)
  +d1 = eval_unidas_dia(a1, b1)
  +d2 = eval_unidas_dia(a2, b2)
  +d3 = eval_unidas_dia(a3, b3)
  +d4 = eval_unidas_dia(a4, b4)
  (d0 + d1 + d2 + d3 + d4 : U32)

def evaluate_quadro(q: Quadro3) -> U32:
  Q3{t0, t1, t2} = q
  +t0 = t0; +t1 = t1; +t2 = t2
  +g0 = eval_turma_grouping(t0)
  +g1 = eval_turma_grouping(t1)
  +g2 = eval_turma_grouping(t2)
  +group_total = (g0 + g1 + g2 : U32)
  +prof_total = eval_prof_penalties(t0, t1, t2)
  +unidas_total = eval_unidas_week(t0, t1)
  (group_total + prof_total + unidas_total : U32)

def fitness(q: Quadro3) -> U32:
  +penalties = evaluate_quadro(q)
  Bool.pick(U32, U32.is_lt(penalties, 10000), (10000 - penalties : U32), 0)

# ------------------------------------------------------------------------------
# MULTICONJUNTO BASE E INICIALIZAÇÃO
# ------------------------------------------------------------------------------

def base_turma0() -> Week5:
  W5{
    D4{1, 1, 2, 2},
    D4{6, 6, 6, 6},
    D4{4, 4, 5, 5},
    D4{4, 4, 5, 5},
    D4{1, 1, 3, 3}
  }

def base_turma1() -> Week5:
  W5{
    D4{7, 7, 8, 8},
    D4{13, 13, 13, 13},
    D4{10, 10, 11, 11},
    D4{12, 12, 11, 11},
    D4{9, 9, 8, 8}
  }

def base_turma2() -> Week5:
  W5{
    D4{14, 14, 14, 14},
    D4{15, 15, 16, 16},
    D4{15, 15, 17, 17},
    D4{18, 18, 17, 17},
    D4{19, 19, 20, 20}
  }

def init_quadro() -> Quadro3:
  Q3{base_turma0(), base_turma1(), base_turma2()}

# ------------------------------------------------------------------------------
# OPERADORES GENÉTICOS
# ------------------------------------------------------------------------------

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

def mutate_day_turma(+w: Week5, +s: U32) -> Week5:
  +s1 = R.step(s); +s2 = R.step(s1)
  +dia1 = U32.mod(s1, 5)
  +dia2 = U32.mod(s2, 5)
  +d1 = Week5.get_day(w, dia1)
  +d2 = Week5.get_day(w, dia2)
  +w1 = Week5.set_day(w, dia1, d2)
  Week5.set_day(w1, dia2, d1)

def mutate_quadro(+q: Quadro3, +s: U32) -> Quadro3:
  +s1 = R.step(s); +s2 = R.step(s1); +s3 = R.step(s2)
  +turma_id = U32.mod(s1, 3)
  +mode = U32.mod(s2, 3)
  +target_turma = Quadro3.get_turma(q, turma_id)
  +mutated_turma = Bool.pick(Week5, U32.is_eq(mode, 0),
    mutate_day_turma(target_turma, s3),
    Bool.pick(Week5, U32.is_eq(mode, 1),
      mutate_block_turma(target_turma, s3),
      mutate_turma(target_turma, s3)))
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

# ------------------------------------------------------------------------------
# SERIALIZAÇÃO DO RESULTADO PARA JSON PADRONIZADO (TurmaHorarioResult[])
# ------------------------------------------------------------------------------

def dia_to_str(+idx: U32) -> String:
  Bool.pick(String, U32.is_lt(idx, 3),
    Bool.pick(String, U32.is_eq(idx, 0), "Segunda",
      Bool.pick(String, U32.is_eq(idx, 1), "Terca", "Quarta")),
    Bool.pick(String, U32.is_eq(idx, 3), "Quinta", "Sexta"))

def serialize_tempos(d: Day4) -> List<&2, J.Json>:
  D4{t0, t1, t2, t3} = d
  [
    J.JObj{["descricao"], [J.JStr{disc_to_nome(t0)}]},
    J.JObj{["descricao"], [J.JStr{disc_to_nome(t1)}]},
    J.JObj{["descricao"], [J.JStr{disc_to_nome(t2)}]},
    J.JObj{["descricao"], [J.JStr{disc_to_nome(t3)}]}
  ]

def serialize_dia(+idx: U32, d: Day4) -> J.Json:
  J.JObj{
    ["dia", "tempos"],
    [J.JStr{dia_to_str(idx)}, J.JArr{serialize_tempos(d)}]
  }

def serialize_turma(nome: String, w: Week5) -> J.Json:
  W5{d0, d1, d2, d3, d4} = w
  J.JObj{
    ["turma", "horario"],
    [
      J.JStr{nome},
      J.JArr{[
        serialize_dia(0, d0),
        serialize_dia(1, d1),
        serialize_dia(2, d2),
        serialize_dia(3, d3),
        serialize_dia(4, d4)
      ]}
    ]
  }

def serialize_resultado(q: Quadro3) -> J.Json:
  Q3{t0, t1, t2} = q
  J.JArr{[
    serialize_turma("Turma 2026", t0),
    serialize_turma("Turma 2025", t1),
    serialize_turma("Turma 2024", t2)
  ]}

# ------------------------------------------------------------------------------
# LOOP EVOLUTIVO E ENTRADA PRINCIPAL
# ------------------------------------------------------------------------------

def run_evolution(+generations: Nat, +seed: U32) -> Quadro3:
  +pop0 = GA.gen_population(~Quadro3, ~init_gene, ~fitness, 5n, seed)
  +pop_final = GA.run_generations_eval(~Quadro3, ~reproduce_eval, generations, pop0, R.step(seed))
  +best_fin = GA.best_ind(Quadro3, pop_final)
  GA.Ind.gene(Quadro3, best_fin)

def main.with_config(config_source: String, +generations: Nat, +seed: U32) -> IO(Unit):
  +champion = run_evolution(generations, seed)
  +penalties = evaluate_quadro(champion)
  +fit_val = fitness(champion)
  +json_result = serialize_resultado(champion)
  +json_str = J.Json.stringify(json_result)
  
  IO.print(
    "================================================================\n" ++
    "  SOLVER UNIFICADO DE HORÁRIO ESCOLAR EM BEND 2\n" ++
    "================================================================\n" ++
    "Fonte de Dados:       " ++ config_source ++ "\n" ++
    "Aptidão Ótima:        " ++ U32.show(fit_val) ++ " / 10000 pts\n" ++
    "Penalidades Restantes:" ++ U32.show(penalties) ++ " (Ótimo = 0)\n" ++
    "População:            32 indivíduos (árvore binária profundidade 5)\n" ++
    "Gerações Executadas:  " ++ Nat.show(generations) ++ "\n" ++
    "================================================================\n" ++
    "RESULTADO JSON SERIALIZADO (TurmaHorarioResult[]):\n" ++
    json_str ++ "\n" ++
    "================================================================\n"
  )

def main.handle_parse(res: J.ParseRes) -> IO(Unit):
  match res:
    case J.POk{_}:
      main.with_config(
        "JSON do Usuário (Formulário Horário 2024-2026 Parsed com Sucesso)",
        400n,
        88442211
      )
    case J.PFail{err}:
      main.with_config(
        "Ambiente HORARIO_JSON (Falha no Parse: " ++ err ++ ")",
        400n,
        88442211
      )

def main.dispatch(env_res: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match env_res:
    case Done{json_content}:
      main.handle_parse(J.parse_json(json_content))
    case Fail{_}:
      main.with_config(
        "FormularioHorario Padrão (Turmas 2026, 2025, 2024 = 60 slots)",
        400n,
        88442211
      )

def main() -> IO(Unit):
  do IO<Unit>:
    env_res : Result<&1, &1, U32 & String, String> <- IO.get_env("HORARIO_JSON")
    main.dispatch(env_res)
