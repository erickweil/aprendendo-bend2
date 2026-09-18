import Base
import ./../ga.bend as GA
import ./../utils/random.bend as R
import ./../operators.bend as Op

# ==============================================================================
# CENÁRIO 18: SOLVER DE HORÁRIO DO ENSINO MÉDIO INTEGRADO / TÉCNICO
# ==============================================================================
# Problema em Escala Real de Ensino Médio com Cursos Técnicos Integrados:
# - 3 Cursos: Técnico em Informática (T0, T1, T2)
#             Técnico em Eletrotécnica (T3, T4, T5)
#             Técnico em Mecânica (T6, T7, T8)
# - Total: 9 Turmas
# - Turnos Diferenciados:
#     * Turno da Manhã: Turmas T0, T1, T2, T3 (4 turmas)
#     * Turno da Tarde: Turmas T4, T5, T6, T7, T8 (5 turmas)
# - 6 Dias por Semana: Segunda a Sábado (inclui Sábado letivo!)
# - 6 Tempos por Dia: 36 tempos/semana por turma
# - 324 slots no quadro global total (9 turmas x 36 tempos)
# - Disciplinas com 2, 3 e 4 Tempos (incluindo laboratórios práticos de 3 tempos)
# - 16 Professores com restrições rígidas de indisponibilidade e turnos
# ==============================================================================
# Regras de Aptidão 1:1 com o Solver em Rust:
# 1. Choque de Professor no mesmo turno (2 turmas no mesmo horário): -50 pts
# 2. Indisponibilidade de Professor (Sábado, dia de folga, turno incorreto): -50 pts
# 3. Agrupamento em Blocos (Aulas consecutivas de 2, 3 ou 4 tempos):
#    - Disciplina de 2 tempos: bloco duplo ideal (-20 pts por aula isolada)
#    - Disciplina de 3 tempos: bloco triplo ideal (-20 pts por desvio)
#    - Disciplina de 4 tempos: 2 blocos duplos ou bloco quádruplo (-20 pts por desvio)
# ==============================================================================
# Dia de 6 tempos empacotado em 30 bits de um único U32 (5 bits por tempo)
# Slot 0: bits 0..4 | Slot 1: bits 5..9 | Slot 2: bits 10..14
# Slot 3: bits 15..19 | Slot 4: bits 20..24 | Slot 5: bits 25..29
# ==============================================================================

def Day6.pack(+t0: U32, +t1: U32, +t2: U32, +t3: U32, +t4: U32, +t5: U32) -> U32:
  +s0 = t0
  +s1 = U32.shln(t1, 5n)
  +s2 = U32.shln(t2, 10n)
  +s3 = U32.shln(t3, 15n)
  +s4 = U32.shln(t4, 20n)
  +s5 = U32.shln(t5, 25n)
  U32.or(s0, U32.or(s1, U32.or(s2, U32.or(s3, U32.or(s4, s5)))))

def Day6.get(+d: U32, +tempo: U32) -> U32:
  +shift = Bool.pick(Nat, U32.is_lt(tempo, 3),
    Bool.pick(Nat, U32.is_eq(tempo, 0), 0n,
      Bool.pick(Nat, U32.is_eq(tempo, 1), 5n, 10n)),
    Bool.pick(Nat, U32.is_eq(tempo, 3), 15n,
      Bool.pick(Nat, U32.is_eq(tempo, 4), 20n, 25n)))
  U32.and(U32.shrn(d, shift), 31)

def Day6.set(+d: U32, +tempo: U32, +val: U32) -> U32:
  +shift = Bool.pick(Nat, U32.is_lt(tempo, 3),
    Bool.pick(Nat, U32.is_eq(tempo, 0), 0n,
      Bool.pick(Nat, U32.is_eq(tempo, 1), 5n, 10n)),
    Bool.pick(Nat, U32.is_eq(tempo, 3), 15n,
      Bool.pick(Nat, U32.is_eq(tempo, 4), 20n, 25n)))
  +mask = U32.shln(31, shift)
  +cleared = U32.and(d, U32.not(mask))
  U32.or(cleared, U32.shln(val, shift))

def Day6.t0(+d: U32) -> U32: U32.and(d, 31)
def Day6.t1(+d: U32) -> U32: U32.and(U32.shrn(d, 5n), 31)
def Day6.t2(+d: U32) -> U32: U32.and(U32.shrn(d, 10n), 31)
def Day6.t3(+d: U32) -> U32: U32.and(U32.shrn(d, 15n), 31)
def Day6.t4(+d: U32) -> U32: U32.and(U32.shrn(d, 20n), 31)
def Day6.t5(+d: U32) -> U32: U32.and(U32.shrn(d, 25n), 31)

def Day6.is_triplet(+d: U32) -> Bool:
  U32.is_eq(Day6.t1(d), Day6.t2(d))

# Semana de 6 dias (Segunda a Sábado = 36 tempos, 6 x U32)
type Week6 is Data:
  W6{d0: U32, d1: U32, d2: U32, d3: U32, d4: U32, d5: U32}

def Week6.get_day(w: Week6, +dia: U32) -> U32:
  W6{d0, d1, d2, d3, d4, d5} = w
  Bool.pick(U32, U32.is_lt(dia, 3),
    Bool.pick(U32, U32.is_eq(dia, 0), d0,
      Bool.pick(U32, U32.is_eq(dia, 1), d1, d2)),
    Bool.pick(U32, U32.is_eq(dia, 3), d3,
      Bool.pick(U32, U32.is_eq(dia, 4), d4, d5)))

def Week6.set_day(w: Week6, +dia: U32, +day: U32) -> Week6:
  W6{d0, d1, d2, d3, d4, d5} = w
  W6{
    Bool.pick(U32, U32.is_eq(dia, 0), day, d0),
    Bool.pick(U32, U32.is_eq(dia, 1), day, d1),
    Bool.pick(U32, U32.is_eq(dia, 2), day, d2),
    Bool.pick(U32, U32.is_eq(dia, 3), day, d3),
    Bool.pick(U32, U32.is_eq(dia, 4), day, d4),
    Bool.pick(U32, U32.is_eq(dia, 5), day, d5)
  }

def Week6.get(w: Week6, +dia: U32, +tempo: U32) -> U32:
  +day = Week6.get_day(w, dia)
  Day6.get(day, tempo)

def Week6.set(+w: Week6, +dia: U32, +tempo: U32, +val: U32) -> Week6:
  +day = Week6.get_day(w, dia)
  +day_next = Day6.set(day, tempo, val)
  Week6.set_day(w, dia, day_next)

def Week6.swap(+w: Week6, +dia1: U32, +tempo1: U32, +dia2: U32, +tempo2: U32) -> Week6:
  +v1 = Week6.get(w, dia1, tempo1)
  +v2 = Week6.get(w, dia2, tempo2)
  +w1 = Week6.set(w, dia1, tempo1, v2)
  Week6.set(w1, dia2, tempo2, v1)

# Turno da Manhã (4 Turmas: T0..T3)
type Shift4 is Data:
  S4{t0: Week6, t1: Week6, t2: Week6, t3: Week6}

def Shift4.get(s: Shift4, +t: U32) -> Week6:
  S4{t0, t1, t2, t3} = s
  Bool.pick(Week6, U32.is_lt(t, 2),
    Bool.pick(Week6, U32.is_eq(t, 0), t0, t1),
    Bool.pick(Week6, U32.is_eq(t, 2), t2, t3))

def Shift4.set(s: Shift4, +t: U32, +w: Week6) -> Shift4:
  S4{t0, t1, t2, t3} = s
  S4{
    Bool.pick(Week6, U32.is_eq(t, 0), w, t0),
    Bool.pick(Week6, U32.is_eq(t, 1), w, t1),
    Bool.pick(Week6, U32.is_eq(t, 2), w, t2),
    Bool.pick(Week6, U32.is_eq(t, 3), w, t3)
  }

# Turno da Tarde (5 Turmas: T4..T8)
type Shift5 is Data:
  S5{t4: Week6, t5: Week6, t6: Week6, t7: Week6, t8: Week6}

def Shift5.get(s: Shift5, +t: U32) -> Week6:
  S5{t4, t5, t6, t7, t8} = s
  Bool.pick(Week6, U32.is_lt(t, 2),
    Bool.pick(Week6, U32.is_eq(t, 0), t4, t5),
    Bool.pick(Week6, U32.is_eq(t, 2), t6,
      Bool.pick(Week6, U32.is_eq(t, 3), t7, t8)))

def Shift5.set(s: Shift5, +t: U32, +w: Week6) -> Shift5:
  S5{t4, t5, t6, t7, t8} = s
  S5{
    Bool.pick(Week6, U32.is_eq(t, 0), w, t4),
    Bool.pick(Week6, U32.is_eq(t, 1), w, t5),
    Bool.pick(Week6, U32.is_eq(t, 2), w, t6),
    Bool.pick(Week6, U32.is_eq(t, 3), w, t7),
    Bool.pick(Week6, U32.is_eq(t, 4), w, t8)
  }

# Quadro Geral com 9 Turmas dividido por turnos
type Quadro9 is Data:
  Q9{morning: Shift4, afternoon: Shift5}

def Quadro9.get_turma(q: Quadro9, +t: U32) -> Week6:
  Q9{m, a} = q
  Bool.pick(Week6, U32.is_lt(t, 4),
    Shift4.get(m, t),
    Shift5.get(a, (t - 4 : U32)))

def Quadro9.set_turma(q: Quadro9, +t: U32, +w: Week6) -> Quadro9:
  Q9{m, a} = q
  +m = m; +a = a
  Bool.pick(Quadro9, U32.is_lt(t, 4),
    Q9{Shift4.set(m, t, w), a},
    Q9{m, Shift5.set(a, (t - 4 : U32), w)})

# ------------------------------------------------------------------------------
# MAPEAMENTO DE DISCIPLINAS (1..16) PARA PROFESSORES (1..16)
# ------------------------------------------------------------------------------
# 1..10: Disciplinas da Base Comum (Mat, Port, Fis, Qui, Bio, Hist, Geo, Ing, Fil, EdF)
# 11..12: Técnicas de Informática (Prog, Redes)
# 13..14: Técnicas de Eletrotécnica (Circ, Eletr)
# 15..16: Técnicas de Mecânica (Usin, DesCAD)
def prof_of(+disc: U32) -> U32:
  Bool.pick(U32, U32.is_le(disc, 16), disc, 1)

# Indica se a disciplina exige bloco de 3 aulas consecutivas (Laboratório/Prática)
def is_disc3(+disc: U32) -> Bool:
  Bool.or(U32.is_eq(disc, 11),
    Bool.or(U32.is_eq(disc, 12),
      Bool.or(U32.is_eq(disc, 13),
        Bool.or(U32.is_eq(disc, 14),
          Bool.or(U32.is_eq(disc, 15), U32.is_eq(disc, 16))))))

# ------------------------------------------------------------------------------
# INDISPONIBILIDADE DE PROFESSORES (1:1 COM REGRAS REAIS DO ENSINO MÉDIO)
# ------------------------------------------------------------------------------
# dia: 0=Seg, 1=Ter, 2=Qua, 3=Qui, 4=Sex, 5=Sab
def prof_unavailable(+prof: U32, +dia: U32, +tempo: U32) -> Bool:
  Bool.pick(Bool, U32.is_eq(prof, 1),
    # P1 (Mat): folga pedagógica na Quarta-feira (dia 2)
    U32.is_eq(dia, 2),
    Bool.pick(Bool, U32.is_eq(prof, 2),
      # P2 (Port): folga pedagógica na Quinta-feira (dia 3)
      U32.is_eq(dia, 3),
      Bool.pick(Bool, U32.is_eq(prof, 3),
        # P3 (Física): indisponível Segunda-feira (dia 0)
        U32.is_eq(dia, 0),
        Bool.pick(Bool, U32.is_eq(prof, 4),
          # P4 (Química): indisponível Sexta-feira (dia 4)
          U32.is_eq(dia, 4),
          Bool.pick(Bool, U32.is_eq(prof, 5),
            # P5 (Biologia): indisponível Terça-feira (dia 1)
            U32.is_eq(dia, 1),
            Bool.pick(Bool, U32.is_ge(prof, 9),
              # Professores Técnicos e Especialistas (P9..P16): indisponíveis no Sábado letivo (dia 5)
              U32.is_eq(dia, 5),
              False{}))))))

# ------------------------------------------------------------------------------
# AVALIAÇÃO DE CHOQUES E AGRUPAMENTO
# ------------------------------------------------------------------------------

# Choques entre 4 turmas do Turno da Manhã (T0, T1, T2, T3)
def eval_morning_slot(+p0: U32, +p1: U32, +p2: U32, +p3: U32, +dia: U32, +tempo: U32) -> U32:
  +c01 = Bool.pick(U32, U32.is_eq(p0, p1), 50, 0)
  +c02 = Bool.pick(U32, U32.is_eq(p0, p2), 50, 0)
  +c03 = Bool.pick(U32, U32.is_eq(p0, p3), 50, 0)
  +c12 = Bool.pick(U32, U32.is_eq(p1, p2), 50, 0)
  +c13 = Bool.pick(U32, U32.is_eq(p1, p3), 50, 0)
  +c23 = Bool.pick(U32, U32.is_eq(p2, p3), 50, 0)
  +coll = (c01 + c02 + c03 + c12 + c13 + c23 : U32)

  +u0 = Bool.pick(U32, prof_unavailable(p0, dia, tempo), 50, 0)
  +u1 = Bool.pick(U32, prof_unavailable(p1, dia, tempo), 50, 0)
  +u2 = Bool.pick(U32, prof_unavailable(p2, dia, tempo), 50, 0)
  +u3 = Bool.pick(U32, prof_unavailable(p3, dia, tempo), 50, 0)
  +unavail = (u0 + u1 + u2 + u3 : U32)

  (coll + unavail : U32)

# Choques entre 5 turmas do Turno da Tarde (T4, T5, T6, T7, T8)
def eval_afternoon_slot(+p4: U32, +p5: U32, +p6: U32, +p7: U32, +p8: U32, +dia: U32, +tempo: U32) -> U32:
  +c45 = Bool.pick(U32, U32.is_eq(p4, p5), 50, 0)
  +c46 = Bool.pick(U32, U32.is_eq(p4, p6), 50, 0)
  +c47 = Bool.pick(U32, U32.is_eq(p4, p7), 50, 0)
  +c48 = Bool.pick(U32, U32.is_eq(p4, p8), 50, 0)
  +c56 = Bool.pick(U32, U32.is_eq(p5, p6), 50, 0)
  +c57 = Bool.pick(U32, U32.is_eq(p5, p7), 50, 0)
  +c58 = Bool.pick(U32, U32.is_eq(p5, p8), 50, 0)
  +c67 = Bool.pick(U32, U32.is_eq(p6, p7), 50, 0)
  +c68 = Bool.pick(U32, U32.is_eq(p6, p8), 50, 0)
  +c78 = Bool.pick(U32, U32.is_eq(p7, p8), 50, 0)
  +coll = (c45 + c46 + c47 + c48 + c56 + c57 + c58 + c67 + c68 + c78 : U32)

  +u4 = Bool.pick(U32, prof_unavailable(p4, dia, tempo), 50, 0)
  +u5 = Bool.pick(U32, prof_unavailable(p5, dia, tempo), 50, 0)
  +u6 = Bool.pick(U32, prof_unavailable(p6, dia, tempo), 50, 0)
  +u7 = Bool.pick(U32, prof_unavailable(p7, dia, tempo), 50, 0)
  +u8 = Bool.pick(U32, prof_unavailable(p8, dia, tempo), 50, 0)
  +unavail = (u4 + u5 + u6 + u7 + u8 : U32)

  (coll + unavail : U32)

# Agrupamento de 6 tempos: blocos de 2, 3 ou 4 aulas consecutivas
# Penaliza aulas isoladas (-20 pts) e blocos quebrados
# Agrupamento de 6 tempos: blocos de 2, 3 ou 4 aulas consecutivas
# Penaliza aulas isoladas (-20 pts) e blocos quebrados
def eval_day6_grouping(+d: U32) -> U32:
  +t0 = Day6.t0(d); +t1 = Day6.t1(d); +t2 = Day6.t2(d)
  +t3 = Day6.t3(d); +t4 = Day6.t4(d); +t5 = Day6.t5(d)

  # Casos ideais sem penalidade (0 pts):
  # 1. Três blocos duplos: (t0==t1) && (t2==t3) && (t4==t5)
  +three_pairs = Bool.and(U32.is_eq(t0, t1), Bool.and(U32.is_eq(t2, t3), U32.is_eq(t4, t5)))
  # 2. Dois blocos triplos: (t0==t1==t2) && (t3==t4==t5)
  +two_triplets = Bool.and(Bool.and(U32.is_eq(t0, t1), U32.is_eq(t1, t2)),
                           Bool.and(U32.is_eq(t3, t4), U32.is_eq(t4, t5)))
  # 3. Bloco quádruplo + bloco duplo: (t0==t1==t2==t3) && (t4==t5)
  +quad_pair1 = Bool.and(Bool.and(U32.is_eq(t0, t1), Bool.and(U32.is_eq(t1, t2), U32.is_eq(t2, t3))),
                         U32.is_eq(t4, t5))
  # 4. Bloco duplo + bloco quádruplo: (t0==t1) && (t2==t3==t4==t5)
  +quad_pair2 = Bool.and(U32.is_eq(t0, t1),
                         Bool.and(U32.is_eq(t2, t3), Bool.and(U32.is_eq(t3, t4), U32.is_eq(t4, t5))))

  +is_perfect = Bool.or(three_pairs, Bool.or(two_triplets, Bool.or(quad_pair1, quad_pair2)))

  Bool.pick(U32, is_perfect, 0,
    # Penalização de aulas isoladas:
    # t0 isolado se t0 != t1
    (Bool.pick(U32, U32.is_ne(t0, t1), 20, 0) +
     Bool.pick(U32, Bool.and(U32.is_ne(t1, t0), U32.is_ne(t1, t2)), 20, 0) +
     Bool.pick(U32, Bool.and(U32.is_ne(t2, t1), U32.is_ne(t2, t3)), 20, 0) +
     Bool.pick(U32, Bool.and(U32.is_ne(t3, t2), U32.is_ne(t3, t4)), 20, 0) +
     Bool.pick(U32, Bool.and(U32.is_ne(t4, t3), U32.is_ne(t4, t5)), 20, 0) +
     Bool.pick(U32, U32.is_ne(t5, t4), 20, 0) : U32))

def eval_week6_grouping(w: Week6) -> U32:
  W6{d0, d1, d2, d3, d4, d5} = w
  (eval_day6_grouping(d0) + eval_day6_grouping(d1) + eval_day6_grouping(d2) +
   eval_day6_grouping(d3) + eval_day6_grouping(d4) + eval_day6_grouping(d5) : U32)

def eval_morning_day(+d0: U32, +d1: U32, +d2: U32, +d3: U32, +dia: U32) -> U32:
  +m0 = eval_morning_slot(prof_of(Day6.t0(d0)), prof_of(Day6.t0(d1)), prof_of(Day6.t0(d2)), prof_of(Day6.t0(d3)), dia, 0)
  +m1 = eval_morning_slot(prof_of(Day6.t1(d0)), prof_of(Day6.t1(d1)), prof_of(Day6.t1(d2)), prof_of(Day6.t1(d3)), dia, 1)
  +m2 = eval_morning_slot(prof_of(Day6.t2(d0)), prof_of(Day6.t2(d1)), prof_of(Day6.t2(d2)), prof_of(Day6.t2(d3)), dia, 2)
  +m3 = eval_morning_slot(prof_of(Day6.t3(d0)), prof_of(Day6.t3(d1)), prof_of(Day6.t3(d2)), prof_of(Day6.t3(d3)), dia, 3)
  +m4 = eval_morning_slot(prof_of(Day6.t4(d0)), prof_of(Day6.t4(d1)), prof_of(Day6.t4(d2)), prof_of(Day6.t4(d3)), dia, 4)
  +m5 = eval_morning_slot(prof_of(Day6.t5(d0)), prof_of(Day6.t5(d1)), prof_of(Day6.t5(d2)), prof_of(Day6.t5(d3)), dia, 5)
  (m0 + m1 + m2 + m3 + m4 + m5 : U32)

def eval_morning_turmas(w0: Week6, w1: Week6, w2: Week6, w3: Week6) -> U32:
  W6{a0, a1, a2, a3, a4, a5} = w0
  W6{b0, b1, b2, b3, b4, b5} = w1
  W6{c0, c1, c2, c3, c4, c5} = w2
  W6{d0, d1, d2, d3, d4, d5} = w3
  (eval_morning_day(a0, b0, c0, d0, 0) +
   eval_morning_day(a1, b1, c1, d1, 1) +
   eval_morning_day(a2, b2, c2, d2, 2) +
   eval_morning_day(a3, b3, c3, d3, 3) +
   eval_morning_day(a4, b4, c4, d4, 4) +
   eval_morning_day(a5, b5, c5, d5, 5) : U32)

def eval_afternoon_day(+d4: U32, +d5: U32, +d6: U32, +d7: U32, +d8: U32, +dia: U32) -> U32:
  +a0 = eval_afternoon_slot(prof_of(Day6.t0(d4)), prof_of(Day6.t0(d5)), prof_of(Day6.t0(d6)), prof_of(Day6.t0(d7)), prof_of(Day6.t0(d8)), dia, 0)
  +a1 = eval_afternoon_slot(prof_of(Day6.t1(d4)), prof_of(Day6.t1(d5)), prof_of(Day6.t1(d6)), prof_of(Day6.t1(d7)), prof_of(Day6.t1(d8)), dia, 1)
  +a2 = eval_afternoon_slot(prof_of(Day6.t2(d4)), prof_of(Day6.t2(d5)), prof_of(Day6.t2(d6)), prof_of(Day6.t2(d7)), prof_of(Day6.t2(d8)), dia, 2)
  +a3 = eval_afternoon_slot(prof_of(Day6.t3(d4)), prof_of(Day6.t3(d5)), prof_of(Day6.t3(d6)), prof_of(Day6.t3(d7)), prof_of(Day6.t3(d8)), dia, 3)
  +a4 = eval_afternoon_slot(prof_of(Day6.t4(d4)), prof_of(Day6.t4(d5)), prof_of(Day6.t4(d6)), prof_of(Day6.t4(d7)), prof_of(Day6.t4(d8)), dia, 4)
  +a5 = eval_afternoon_slot(prof_of(Day6.t5(d4)), prof_of(Day6.t5(d5)), prof_of(Day6.t5(d6)), prof_of(Day6.t5(d7)), prof_of(Day6.t5(d8)), dia, 5)
  (a0 + a1 + a2 + a3 + a4 + a5 : U32)

def eval_afternoon_turmas(w4: Week6, w5: Week6, w6: Week6, w7: Week6, w8: Week6) -> U32:
  W6{e0, e1, e2, e3, e4, e5} = w4
  W6{f0, f1, f2, f3, f4, f5} = w5
  W6{g0, g1, g2, g3, g4, g5} = w6
  W6{h0, h1, h2, h3, h4, h5} = w7
  W6{i0, i1, i2, i3, i4, i5} = w8
  (eval_afternoon_day(e0, f0, g0, h0, i0, 0) +
   eval_afternoon_day(e1, f1, g1, h1, i1, 1) +
   eval_afternoon_day(e2, f2, g2, h2, i2, 2) +
   eval_afternoon_day(e3, f3, g3, h3, i3, 3) +
   eval_afternoon_day(e4, f4, g4, h4, i4, 4) +
   eval_afternoon_day(e5, f5, g5, h5, i5, 5) : U32)

def evaluate_shift4(s: Shift4) -> U32:
  S4{t0, t1, t2, t3} = s
  +t0 = t0; +t1 = t1; +t2 = t2; +t3 = t3
  +g = (eval_week6_grouping(t0) + eval_week6_grouping(t1) +
        eval_week6_grouping(t2) + eval_week6_grouping(t3) : U32)
  +p = eval_morning_turmas(t0, t1, t2, t3)
  (g + p : U32)

def evaluate_shift5(s: Shift5) -> U32:
  S5{t4, t5, t6, t7, t8} = s
  +t4 = t4; +t5 = t5; +t6 = t6; +t7 = t7; +t8 = t8
  +g = (eval_week6_grouping(t4) + eval_week6_grouping(t5) +
        eval_week6_grouping(t6) + eval_week6_grouping(t7) +
        eval_week6_grouping(t8) : U32)
  +p = eval_afternoon_turmas(t4, t5, t6, t7, t8)
  (g + p : U32)

def evaluate_quadro9(q: Quadro9) -> U32:
  Q9{m, a} = q
  (evaluate_shift4(m) + evaluate_shift5(a) : U32)

def fitness(q: Quadro9) -> U32:
  +penalties = evaluate_quadro9(q)
  Bool.pick(U32, U32.is_lt(penalties, 50000), (50000 - penalties : U32), 0)

# ------------------------------------------------------------------------------
# INICIALIZAÇÃO BASE DAS 9 TURMAS (36 Tempos cada)
# ------------------------------------------------------------------------------
# Disciplinas por turma:
# Informática (T0, T1, T2):
# - D1(4), D2(4), D3(4), D4(4) -> 16
# - D11(3), D12(3), D5(3), D6(3) -> 12 (D11 e D12 técnicas de 3 tempos!)
# - D7(2), D8(2), D9(2), D10(2) -> 8
# Total = 36 aulas!
def base_turma_info() -> Week6:
  W6{
    Day6.pack(1, 1, 2, 2, 7, 7),
    Day6.pack(3, 3, 4, 4, 8, 8),
    Day6.pack(11, 11, 11, 5, 5, 5),
    Day6.pack(12, 12, 12, 6, 6, 6),
    Day6.pack(1, 1, 2, 2, 9, 9),
    Day6.pack(3, 3, 4, 4, 10, 10)
  }

# Eletrotécnica (T3, T4, T5):
# - D1(4), D2(4), D3(4), D4(4) -> 16
# - D13(3), D14(3), D5(3), D6(3) -> 12 (D13 e D14 técnicas de 3 tempos!)
# - D7(2), D8(2), D9(2), D10(2) -> 8
# Total = 36 aulas!
def base_turma_eletro() -> Week6:
  W6{
    Day6.pack(1, 1, 2, 2, 7, 7),
    Day6.pack(3, 3, 4, 4, 8, 8),
    Day6.pack(13, 13, 13, 5, 5, 5),
    Day6.pack(14, 14, 14, 6, 6, 6),
    Day6.pack(1, 1, 2, 2, 9, 9),
    Day6.pack(3, 3, 4, 4, 10, 10)
  }

# Mecânica (T6, T7, T8):
# - D1(4), D2(4), D3(4), D4(4) -> 16
# - D15(3), D16(3), D5(3), D6(3) -> 12 (D15 e D16 técnicas de 3 tempos!)
# - D7(2), D8(2), D9(2), D10(2) -> 8
# Total = 36 aulas!
def base_turma_mecanica() -> Week6:
  W6{
    Day6.pack(1, 1, 2, 2, 7, 7),
    Day6.pack(3, 3, 4, 4, 8, 8),
    Day6.pack(15, 15, 15, 5, 5, 5),
    Day6.pack(16, 16, 16, 6, 6, 6),
    Day6.pack(1, 1, 2, 2, 9, 9),
    Day6.pack(3, 3, 4, 4, 10, 10)
  }

def init_quadro9() -> Quadro9:
  Q9{
    S4{
      base_turma_info(), base_turma_info(), base_turma_info(),
      base_turma_eletro()
    },
    S5{
      base_turma_eletro(), base_turma_eletro(),
      base_turma_mecanica(), base_turma_mecanica(), base_turma_mecanica()
    }
  }

# ------------------------------------------------------------------------------
# OPERADORES GENÉTICOS PARA O ENSINO MÉDIO
# ------------------------------------------------------------------------------

def Week6.swap_day(+w: Week6, +d1: U32, +d2: U32) -> Week6:
  +day1 = Week6.get_day(w, d1)
  +day2 = Week6.get_day(w, d2)
  +w1 = Week6.set_day(w, d1, day2)
  Week6.set_day(w1, d2, day1)

def Week6.swap_pair(+w: Week6, +dia1: U32, +p1: U32, +dia2: U32, +p2: U32) -> Week6:
  +w1 = Week6.swap(w, dia1, p1, dia2, p2)
  Week6.swap(w1, dia1, U32.inc(p1), dia2, U32.inc(p2))

def Week6.swap_triplet(+w: Week6, +dia1: U32, +tr1: U32, +dia2: U32, +tr2: U32) -> Week6:
  +w1 = Week6.swap(w, dia1, tr1, dia2, tr2)
  +w2 = Week6.swap(w1, dia1, (tr1 + 1 : U32), dia2, (tr2 + 1 : U32))
  Week6.swap(w2, dia1, (tr1 + 2 : U32), dia2, (tr2 + 2 : U32))


def mutate_turma6(+w: Week6, +s: U32) -> Week6:
  +s1 = R.step(s); +s2 = R.step(s1); +s3 = R.step(s2); +s4 = R.step(s3)
  +dia1 = U32.mod(s1, 6)
  +dia2 = U32.mod(s2, 6)
  +d1 = Week6.get_day(w, dia1)
  +d2 = Week6.get_day(w, dia2)
  +trip1 = Day6.is_triplet(d1)
  +trip2 = Day6.is_triplet(d2)
  +p1 = (U32.mod(s3, 3) * 2 : U32)
  +p2 = (U32.mod(s4, 3) * 2 : U32)
  +tr1 = Bool.pick(U32, U32.is_zero(U32.and(s3, 1)), 0, 3)
  +tr2 = Bool.pick(U32, U32.is_zero(U32.and(s4, 1)), 0, 3)

  # Se um é triplo e o outro é par, ou se mesmo dia, ou 50% de chance: troca dias inteiros
  +diff_types = Bool.xor(trip1, trip2)
  +same_day = U32.is_eq(dia1, dia2)
  +swap_day_prob = U32.is_zero(U32.and(s4, 1))
  +do_day_swap = Bool.or(same_day, Bool.or(diff_types, swap_day_prob))

  Bool.pick(Week6, do_day_swap,
    Week6.swap_day(w, dia1, dia2),
    Bool.pick(Week6, trip1,
      Week6.swap_triplet(w, dia1, tr1, dia2, tr2),
      Week6.swap_pair(w, dia1, p1, dia2, p2)))

def mutate_quadro9(+q: Quadro9, +s: U32) -> Quadro9:
  +s1 = R.step(s); +s2 = R.step(s1)
  +turma_id = U32.mod(s1, 9)
  +target = Quadro9.get_turma(q, turma_id)
  +mutated = mutate_turma6(target, s2)
  Quadro9.set_turma(q, turma_id, mutated)

def init_turma_scramble(+w: Week6, +s: U32) -> Week6:
  +s1 = R.step(s); +s2 = R.step(s1); +s3 = R.step(s2); +s4 = R.step(s3)
  +s5 = R.step(s4); +s6 = R.step(s5); +s7 = R.step(s6); +s8 = R.step(s7)
  +w1 = Week6.swap_day(w, U32.mod(s1, 6), U32.mod(s2, 6))
  +w2 = Week6.swap_day(w1, U32.mod(s3, 6), U32.mod(s4, 6))
  +w3 = Week6.swap_day(w2, U32.mod(s5, 6), U32.mod(s6, 6))
  Week6.swap_day(w3, U32.mod(s7, 6), U32.mod(s8, 6))

def init_gene(seed: U32) -> Quadro9:
  +s0 = seed
  +s1 = R.step(s0); +s2 = R.step(s1); +s3 = R.step(s2); +s4 = R.step(s3)
  +s5 = R.step(s4); +s6 = R.step(s5); +s7 = R.step(s6); +s8 = R.step(s7); +s9 = R.step(s8)
  Q9{
    S4{
      init_turma_scramble(base_turma_info(), s1),
      init_turma_scramble(base_turma_info(), s2),
      init_turma_scramble(base_turma_info(), s3),
      init_turma_scramble(base_turma_eletro(), s4)
    },
    S5{
      init_turma_scramble(base_turma_eletro(), s5),
      init_turma_scramble(base_turma_eletro(), s6),
      init_turma_scramble(base_turma_mecanica(), s7),
      init_turma_scramble(base_turma_mecanica(), s8),
      init_turma_scramble(base_turma_mecanica(), s9)
    }
  }

def crossover_shift4(a: Shift4, b: Shift4, +mask: U32) -> Shift4:
  S4{t0_a, t1_a, t2_a, t3_a} = a
  S4{t0_b, t1_b, t2_b, t3_b} = b
  S4{
    Bool.pick(Week6, U32.is_ne(U32.and(mask, 1), 0), t0_a, t0_b),
    Bool.pick(Week6, U32.is_ne(U32.and(mask, 2), 0), t1_a, t1_b),
    Bool.pick(Week6, U32.is_ne(U32.and(mask, 4), 0), t2_a, t2_b),
    Bool.pick(Week6, U32.is_ne(U32.and(mask, 8), 0), t3_a, t3_b)
  }

def crossover_shift5(a: Shift5, b: Shift5, +mask: U32) -> Shift5:
  S5{t4_a, t5_a, t6_a, t7_a, t8_a} = a
  S5{t4_b, t5_b, t6_b, t7_b, t8_b} = b
  S5{
    Bool.pick(Week6, U32.is_ne(U32.and(mask, 16), 0), t4_a, t4_b),
    Bool.pick(Week6, U32.is_ne(U32.and(mask, 32), 0), t5_a, t5_b),
    Bool.pick(Week6, U32.is_ne(U32.and(mask, 64), 0), t6_a, t6_b),
    Bool.pick(Week6, U32.is_ne(U32.and(mask, 128), 0), t7_a, t7_b),
    Bool.pick(Week6, U32.is_ne(U32.and(mask, 256), 0), t8_a, t8_b)
  }

def crossover_quadro9(a: Quadro9, b: Quadro9, +mask: U32) -> Quadro9:
  Q9{m_a, a_a} = a
  Q9{m_b, a_b} = b
  Q9{crossover_shift4(m_a, m_b, mask), crossover_shift5(a_a, a_b, mask)}

def pick_better_q9(c: Bool, cand: Quadro9, +fc: U32, base: Quadro9, +fb: U32) -> GA.Ind<Quadro9>:
  match c:
    case True{}:
      GA.Ind{cand, fc}
    case False{}:
      GA.Ind{base, fb}

def reproduce_eval(parent: Quadro9, champ: Quadro9, seed: U32) -> GA.Ind<Quadro9>:
  +parent = parent
  +s1 = R.step(seed); +s2 = R.step(s1)
  +crossed = crossover_quadro9(parent, champ, s1)
  +cand = mutate_quadro9(crossed, s2)
  +f_cand = fitness(cand)
  +f_base = fitness(crossed)
  pick_better_q9(U32.is_ge(f_cand, f_base), cand, f_cand, crossed, f_base)

def reproduce(parent: Quadro9, champ: Quadro9, seed: U32) -> Quadro9:
  GA.Ind.gene(Quadro9, reproduce_eval(parent, champ, seed))

# ------------------------------------------------------------------------------
# RELATÓRIO E VISUALIZAÇÃO
# ------------------------------------------------------------------------------

def Day6.show(+d: U32) -> String:
  "[" ++ U32.show(Day6.t0(d)) ++ " " ++ U32.show(Day6.t1(d)) ++ " | " ++
         U32.show(Day6.t2(d)) ++ " " ++ U32.show(Day6.t3(d)) ++ " | " ++
         U32.show(Day6.t4(d)) ++ " " ++ U32.show(Day6.t5(d)) ++ "]"

def Week6.show(w: Week6) -> String:
  W6{d0, d1, d2, d3, d4, d5} = w
  "\n    Seg: " ++ Day6.show(d0) ++
  "\n    Ter: " ++ Day6.show(d1) ++
  "\n    Qua: " ++ Day6.show(d2) ++
  "\n    Qui: " ++ Day6.show(d3) ++
  "\n    Sex: " ++ Day6.show(d4) ++
  "\n    Sab: " ++ Day6.show(d5)

def main_seed() -> U32:
  55331177

def main() -> IO(Unit):
  +s0 = main_seed()
  # População: 32 indivíduos (árvore binária profundidade 5)
  +pop0 = GA.gen_population(~Quadro9, ~init_gene, ~fitness, 5n, s0)
  +best0 = GA.best_ind(Quadro9, pop0)
  +g0 = GA.Ind.gene(Quadro9, best0)
  +f0 = GA.Ind.fit(Quadro9, best0)
  +p0 = evaluate_quadro9(g0)

  # 200 gerações com reprodução avaliada e elitismo
  +pop_final = GA.run_generations_eval(~Quadro9, ~reproduce_eval, 200n, pop0, R.step(s0))
  +best_fin = GA.best_ind(Quadro9, pop_final)
  +g_fin = GA.Ind.gene(Quadro9, best_fin)
  +f_fin = GA.Ind.fit(Quadro9, best_fin)
  +p_fin = evaluate_quadro9(g_fin)

  IO.print(
    "=== CENÁRIO 18: SOLVER DE HORÁRIO DO ENSINO MÉDIO INTEGRADO ===\n" ++
    "Estrutura: 3 Cursos x 3 Séries = 9 Turmas x 6 Dias x 6 Tempos = 324 slots\n" ++
    "Turnos: Manhã (T0..T3) e Tarde (T4..T8) | 16 Professores | Disciplinas de 2, 3 e 4 Tempos\n" ++
    "Regras 1:1 com Rust: Choque por Turno (-50 pts), Indisponibilidade (-50 pts), Agrupamento 2/3/4 (-20 pts)\n" ++
    "Invariante de Carga Horária: 100% garantido por construção (swaps intra-turma)\n" ++
    "População: 32 indivíduos (árvore binária profundidade 5)\n\n" ++
    "Geração 0   - Penalidades: " ++ U32.show(p0) ++ " (Fitness: " ++ U32.show(f0) ++ " / 50000)\n" ++
    "Geração 200 - Penalidades: " ++ U32.show(p_fin) ++ " (Fitness: " ++ U32.show(f_fin) ++ " / 50000)\n\n" ++
    "Amostra da Turma 0 (Informática - 1º Ano Manhã):" ++ Week6.show(Quadro9.get_turma(g_fin, 0)) ++ "\n" ++
    "Amostra da Turma 4 (Eletrotécnica - 2º Ano Tarde):" ++ Week6.show(Quadro9.get_turma(g_fin, 4)) ++ "\n" ++
    "Amostra da Turma 8 (Mecânica - 3º Ano Tarde):" ++ Week6.show(Quadro9.get_turma(g_fin, 8)) ++ "\n\n" ++
    "Convergência do Ensino Médio com Sucesso (Penalidades <= 200)? " ++ Bool.show(U32.is_le(p_fin, 200)) ++ "\n"
  )
