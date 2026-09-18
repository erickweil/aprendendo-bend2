import Base
import ./../ga.bend as GA
import ./../utils/random.bend as R
import ./../operators.bend as Op
import ./../utils/json.bend as J
import ./../utils/poptree.bend as T
import ./../utils/bits.bend as B

# ==============================================================================
# SOLVER DE HORÁRIO ESCOLAR EM BEND 2 — DADOS VINDOS DE JSON
# ==============================================================================
# - Turmas, Disciplinas, Cargas Horárias e Professores extraídos em runtime do
#   JSON em HORARIO_JSON. Nenhum nome é embutido no código.
# - Tabelas de acesso rápido Table16 e Table32 alimentadas em runtime pelo JSON
# - Avaliação de alta performance com genoma Quadro3
# - Serialização do resultado final no padrão TurmaHorarioResult[]
#
# ATENÇÃO — a FORMA do problema ainda é fixa no código, e a fitness NÃO é 1:1
# com o original em Rust (my-website/rust-wasm/src/horario/). Ver a tabela
# "Estado do port em relação ao original em Rust" no README.md da raiz.
# Resumo: genoma fixo em 3 turmas x 5 dias x 4 tempos; `repeat_val` satura em 4
# aulas; no máximo 15 professores e 31 disciplinas;
# `disciplinas_unidas` cobre só o 1o par, fixo entre as turmas 0 e 1;
# `turmas[].horarios` (disponibilidade da turma) não é lido.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. REPRESENTAÇÃO DO GENOMA (ADTs NATIVOS HVM)
# ------------------------------------------------------------------------------

type Day4 is Data:
  D4{t0: U32, t1: U32, t2: U32, t3: U32}

def make_d4(t0: U32, t1: U32, t2: U32, t3: U32) -> Day4:
  D4{t0, t1, t2, t3}

def Day4.get(d: Day4, +idx: U32) -> U32:
  D4{t0, t1, t2, t3} = d
  Bool.pick(U32, U32.is_lt(idx, 2),
    Bool.pick(U32, U32.is_eq(idx, 0), t0, t1),
    Bool.pick(U32, U32.is_eq(idx, 2), t2, t3))

def Day4.set(d: Day4, +idx: U32, +val: U32) -> Day4:
  D4{t0, t1, t2, t3} = d
  make_d4(
    Bool.pick(U32, U32.is_eq(idx, 0), val, t0),
    Bool.pick(U32, U32.is_eq(idx, 1), val, t1),
    Bool.pick(U32, U32.is_eq(idx, 2), val, t2),
    Bool.pick(U32, U32.is_eq(idx, 3), val, t3)
  )

type Week5 is Data:
  W5{d0: Day4, d1: Day4, d2: Day4, d3: Day4, d4: Day4}

def make_w5(d0: Day4, d1: Day4, d2: Day4, d3: Day4, d4: Day4) -> Week5:
  W5{d0, d1, d2, d3, d4}

def Week5.get_day(w: Week5, +dia: U32) -> Day4:
  W5{d0, d1, d2, d3, d4} = w
  Bool.pick(Day4, U32.is_lt(dia, 3),
    Bool.pick(Day4, U32.is_eq(dia, 0), d0,
      Bool.pick(Day4, U32.is_eq(dia, 1), d1, d2)),
    Bool.pick(Day4, U32.is_eq(dia, 3), d3, d4))

def Week5.set_day(w: Week5, +dia: U32, +day: Day4) -> Week5:
  W5{d0, d1, d2, d3, d4} = w
  make_w5(
    Bool.pick(Day4, U32.is_eq(dia, 0), day, d0),
    Bool.pick(Day4, U32.is_eq(dia, 1), day, d1),
    Bool.pick(Day4, U32.is_eq(dia, 2), day, d2),
    Bool.pick(Day4, U32.is_eq(dia, 3), day, d3),
    Bool.pick(Day4, U32.is_eq(dia, 4), day, d4)
  )

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

def make_q3(t0: Week5, t1: Week5, t2: Week5) -> Quadro3:
  Q3{t0, t1, t2}

def Quadro3.get_turma(q: Quadro3, +t: U32) -> Week5:
  Q3{t0, t1, t2} = q
  Bool.pick(Week5, U32.is_eq(t, 0), t0,
    Bool.pick(Week5, U32.is_eq(t, 1), t1, t2))

def Quadro3.set_turma(q: Quadro3, +t: U32, +w: Week5) -> Quadro3:
  Q3{t0, t1, t2} = q
  make_q3(
    Bool.pick(Week5, U32.is_eq(t, 0), w, t0),
    Bool.pick(Week5, U32.is_eq(t, 1), w, t1),
    Bool.pick(Week5, U32.is_eq(t, 2), w, t2)
  )

# ------------------------------------------------------------------------------
# 2. TABELAS DE ACESSO RÁPIDO O(1) PARA O LOOP GENÉTICO
# ------------------------------------------------------------------------------

type Table16 is Data:
  T16{
    x0: U32, x1: U32, x2: U32, x3: U32,
    x4: U32, x5: U32, x6: U32, x7: U32,
    x8: U32, x9: U32, x10: U32, x11: U32,
    x12: U32, x13: U32, x14: U32, x15: U32
  }

def make_t16(x0: U32, x1: U32, x2: U32, x3: U32,
             x4: U32, x5: U32, x6: U32, x7: U32,
             x8: U32, x9: U32, x10: U32, x11: U32,
             x12: U32, x13: U32, x14: U32, x15: U32) -> Table16:
  T16{x0, x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, x15}

def empty_t16() -> Table16:
  make_t16(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

def Table16.get(t: Table16, +idx: U32) -> U32:
  T16{x0, x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, x15} = t
  Bool.pick(U32, U32.is_lt(idx, 8),
    Bool.pick(U32, U32.is_lt(idx, 4),
      Bool.pick(U32, U32.is_lt(idx, 2),
        Bool.pick(U32, U32.is_eq(idx, 0), x0, x1),
        Bool.pick(U32, U32.is_eq(idx, 2), x2, x3)),
      Bool.pick(U32, U32.is_lt(idx, 6),
        Bool.pick(U32, U32.is_eq(idx, 4), x4, x5),
        Bool.pick(U32, U32.is_eq(idx, 6), x6, x7))),
    Bool.pick(U32, U32.is_lt(idx, 12),
      Bool.pick(U32, U32.is_lt(idx, 10),
        Bool.pick(U32, U32.is_eq(idx, 8), x8, x9),
        Bool.pick(U32, U32.is_eq(idx, 10), x10, x11)),
      Bool.pick(U32, U32.is_lt(idx, 14),
        Bool.pick(U32, U32.is_eq(idx, 12), x12, x13),
        Bool.pick(U32, U32.is_eq(idx, 14), x14, x15))))

# ATENCAO: idx >= 16 devolve a tabela INALTERADA (nenhum Bool.pick casa). Nao ha
# como sinalizar erro daqui; quem garante a faixa e validate_input (secao 5B).
def Table16.set(t: Table16, +idx: U32, +val: U32) -> Table16:
  T16{x0, x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, x15} = t
  make_t16(
    Bool.pick(U32, U32.is_eq(idx, 0), val, x0),
    Bool.pick(U32, U32.is_eq(idx, 1), val, x1),
    Bool.pick(U32, U32.is_eq(idx, 2), val, x2),
    Bool.pick(U32, U32.is_eq(idx, 3), val, x3),
    Bool.pick(U32, U32.is_eq(idx, 4), val, x4),
    Bool.pick(U32, U32.is_eq(idx, 5), val, x5),
    Bool.pick(U32, U32.is_eq(idx, 6), val, x6),
    Bool.pick(U32, U32.is_eq(idx, 7), val, x7),
    Bool.pick(U32, U32.is_eq(idx, 8), val, x8),
    Bool.pick(U32, U32.is_eq(idx, 9), val, x9),
    Bool.pick(U32, U32.is_eq(idx, 10), val, x10),
    Bool.pick(U32, U32.is_eq(idx, 11), val, x11),
    Bool.pick(U32, U32.is_eq(idx, 12), val, x12),
    Bool.pick(U32, U32.is_eq(idx, 13), val, x13),
    Bool.pick(U32, U32.is_eq(idx, 14), val, x14),
    Bool.pick(U32, U32.is_eq(idx, 15), val, x15)
  )

type Table32 is Data:
  T32{lo: Table16, hi: Table16}

def make_t32(lo: Table16, hi: Table16) -> Table32:
  T32{lo, hi}

def empty_t32() -> Table32:
  make_t32(empty_t16(), empty_t16())

def Table32.get(t: Table32, +idx: U32) -> U32:
  T32{lo, hi} = t
  Bool.pick(U32, U32.is_lt(idx, 16),
    Table16.get(lo, idx),
    Table16.get(hi, U32.sub(idx, 16)))

def Table32.set.step(is_lo: Bool, lo: Table16, hi: Table16, idx: U32, val: U32) -> Table32:
  match is_lo:
    case True{}: make_t32(Table16.set(lo, idx, val), hi)
    case False{}: make_t32(lo, Table16.set(hi, U32.sub(idx, 16), val))

# ATENCAO: idx >= 32 devolve a tabela INALTERADA. Faixa garantida por
# validate_input (secao 5B).
def Table32.set(t: Table32, +idx: U32, +val: U32) -> Table32:
  T32{lo, hi} = t
  Table32.set.step(U32.is_lt(idx, 16), lo, hi, idx, val)

def fill_table32(l: List<&2, U32>, +t: Table32, +cur: U32) -> Table32:
  match l:
    case Nil{}: t
    case h <> rest:
      +t_next = Table32.set(t, cur, h)
      fill_table32(rest, t_next, U32.inc(cur))

def fill_table16(l: List<&2, U32>, +t: Table16, +cur: U32) -> Table16:
  match l:
    case Nil{}: t
    case h <> rest:
      +t_next = Table16.set(t, cur, h)
      fill_table16(rest, t_next, U32.inc(cur))

# `disc_info` guarda duas coisas por disciplina numa palavra so:
#   bits 0-15  : CONJUNTO de professores (bit p-1 = o professor p da essa
#                disciplina). O Rust itera `disciplina.professores`, que e uma
#                lista; guardar so o primeiro perdia os demais.
#   bits 16-23 : agrupar * 2 + dividir
# Uma Table32 adicional para o agrupamento fazia o backend C falhar com
# "an arity over 255" (o interpretador aceitava, mas `bend -o` nao compilava
# mais). Empacotar mantem FastSpec com a mesma aridade de antes.
# `slot_unavail` e a indisponibilidade TRANSPOSTA: por slot (0..19), o conjunto
# de professores indisponiveis ali. A forma original (professor -> 20 bits de
# slot) obrigaria a colher um bit de cada professor a cada avaliacao de slot.
#
# Cabe numa Table16 porque guarda DOIS slots por palavra (16 bits cada, e a
# mascara usa no maximo 15): 20 slots -> 10 palavras. Usar uma Table32 aqui
# fazia `bend -o` falhar com "an arity over 255"; assim FastSpec fica com a
# mesma aridade de antes desta mudanca.
type FastSpec is Data:
  FSpec{disc_info: Table32, slot_unavail: Table16, u1: U32, u2: U32}

def make_fspec(disc_info: Table32, slot_unavail: Table16, u1: U32, u2: U32) -> FastSpec:
  FSpec{disc_info, slot_unavail, u1, u2}

def slot_unavail_get(+t: Table16, +slot: U32) -> U32:
  +par = U32.and(slot, 1)
  +word = Table16.get(t, U32.shrn(slot, 1n))
  U32.and(U32.shrn(word, U32.to_nat(U32.mul(par, 16))), 65535)

def disc_pmask(+t: Table32, +d: U32) -> U32:
  U32.and(Table32.get(t, d), 65535)

def disc_group(+t: Table32, +d: U32) -> U32:
  U32.shrn(Table32.get(t, d), 16n)

type Cand is Data:
  CD{q: Quadro3, spec: FastSpec}

def make_cand(q: Quadro3, spec: FastSpec) -> Cand:
  CD{q, spec}

# ------------------------------------------------------------------------------
# 3. FUNÇÃO DE AVALIAÇÃO DE APTIDÃO (1:1 COM RUST)
# ------------------------------------------------------------------------------

# Penalidade de um slot com CONJUNTOS de professores.
#
# O Rust conta, por (professor, slot), quantas turmas o querem (pass 1) e pune
# proporcional ao excesso, uma vez por turma que o usa (pass 2). Somando por
# professor em vez de por turma, isso vira
#   total = Σ_p  k(p) * max(0, k(p) - disponivel(p)) * 50
# com k(p) = quantas das 3 turmas querem p. Como k so pode ser 1, 2 ou 3, os
# cinco casos possiveis sao constantes e o conjunto de professores em cada caso
# sai de operacoes bitwise:
#   k=1: 0 se disponivel, 50 se nao
#   k=2: 100 se disponivel, 200 se nao
#   k=3: 300 se disponivel, 450 se nao
# Conferido por enumeracao contra a dupla passada do Rust nas 65536 combinacoes
# de (3 mascaras de professor) x (disponibilidade de 4 professores).
#
# `unavail` e o conjunto de professores indisponiveis NESTE slot.
def eval_prof_slot(+mA: U32, +mB: U32, +mC: U32, +unavail: U32) -> U32:
  +e3 = U32.and(mA, U32.and(mB, mC))
  +pares = U32.or(U32.and(mA, mB), U32.or(U32.and(mA, mC), U32.and(mB, mC)))
  +e2 = U32.and(pares, U32.not(e3))
  +e1 = U32.and(U32.or(mA, U32.or(mB, mC)), U32.not(U32.or(e2, e3)))
  +avail = U32.not(unavail)
  +c1u = B.popcount(U32.and(e1, unavail))
  +c2a = B.popcount(U32.and(e2, avail))
  +c2u = B.popcount(U32.and(e2, unavail))
  +c3a = B.popcount(U32.and(e3, avail))
  +c3u = B.popcount(U32.and(e3, unavail))
  (c1u * 50 + c2a * 100 + c2u * 200 + c3a * 300 + c3u * 450 : U32)

def eval_day_prof(+d0: Day4, +d1: Day4, +d2: Day4, +dia: U32, +info: Table32, +su: Table16) -> U32:
  D4{a0, a1, a2, a3} = d0
  D4{b0, b1, b2, b3} = d1
  D4{c0, c1, c2, c3} = d2
  +base_slot = U32.shln(dia, 2n)
  +s1i = U32.add(base_slot, 1)
  +s2i = U32.add(base_slot, 2)
  +s3i = U32.add(base_slot, 3)
  +s0 = eval_prof_slot(disc_pmask(info, a0), disc_pmask(info, b0), disc_pmask(info, c0), slot_unavail_get(su, base_slot))
  +s1 = eval_prof_slot(disc_pmask(info, a1), disc_pmask(info, b1), disc_pmask(info, c1), slot_unavail_get(su, s1i))
  +s2 = eval_prof_slot(disc_pmask(info, a2), disc_pmask(info, b2), disc_pmask(info, c2), slot_unavail_get(su, s2i))
  +s3 = eval_prof_slot(disc_pmask(info, a3), disc_pmask(info, b3), disc_pmask(info, c3), slot_unavail_get(su, s3i))
  (s0 + s1 + s2 + s3 : U32)

def eval_prof_penalties(+w0: Week5, +w1: Week5, +w2: Week5, +info: Table32, +su: Table16) -> U32:
  W5{a0, a1, a2, a3, a4} = w0
  W5{b0, b1, b2, b3, b4} = w1
  W5{c0, c1, c2, c3, c4} = w2
  +d0 = eval_day_prof(a0, b0, c0, 0, info, su)
  +d1 = eval_day_prof(a1, b1, c1, 1, info, su)
  +d2 = eval_day_prof(a2, b2, c2, 2, info, su)
  +d3 = eval_day_prof(a3, b3, c3, 3, info, su)
  +d4 = eval_day_prof(a4, b4, c4, 4, info, su)
  (d0 + d1 + d2 + d3 + d4 : U32)

def eval_unidas_tempo(+t0_val: U32, +t1_val: U32, +u1: U32, +u2: U32) -> U32:
  +active = Bool.and(U32.is_gt(u1, 0), U32.is_gt(u2, 0))
  Bool.pick(U32, active,
    Bool.pick(U32, Bool.xor(U32.is_eq(t0_val, u1), U32.is_eq(t1_val, u2)), 30, 0),
    0)

def eval_unidas_dia(+d0: Day4, +d1: Day4, +u1: U32, +u2: U32) -> U32:
  D4{a0, a1, a2, a3} = d0
  D4{b0, b1, b2, b3} = d1
  +u0 = eval_unidas_tempo(a0, b0, u1, u2)
  +u1_r = eval_unidas_tempo(a1, b1, u1, u2)
  +u2_r = eval_unidas_tempo(a2, b2, u1, u2)
  +u3 = eval_unidas_tempo(a3, b3, u1, u2)
  (u0 + u1_r + u2_r + u3 : U32)

def eval_unidas_week(+w0: Week5, +w1: Week5, +u1: U32, +u2: U32) -> U32:
  W5{a0, a1, a2, a3, a4} = w0
  W5{b0, b1, b2, b3, b4} = w1
  +d0 = eval_unidas_dia(a0, b0, u1, u2)
  +d1 = eval_unidas_dia(a1, b1, u1, u2)
  +d2 = eval_unidas_dia(a2, b2, u1, u2)
  +d3 = eval_unidas_dia(a3, b3, u1, u2)
  +d4 = eval_unidas_dia(a4, b4, u1, u2)
  (d0 + d1 + d2 + d3 + d4 : U32)

# Penalidade de UM bloco contiguo de `len` aulas da mesma disciplina, seguindo
# horario_genetic.rs: ideal = `g` quando a disciplina e divisivel, senao o
# multiplo de `g` mais proximo de `len`; penalidade = |len - ideal| * 20.
#
# `round(len/g)` do Rust arredonda a metade para LONGE de zero, que em inteiros
# positivos e floor(len/g + 1/2) = (2*len + g) / (2*g). (O round() do Python faz
# banker's rounding e NAO serve de referencia aqui.)
#
# `g == 0` desliga a regra (disc.agrupar <= 0 no Rust). Como Bool.pick e estrito,
# os dois ramos sao avaliados: `gs` existe so para a divisao do ramo descartado
# nao ser por zero.
# `packed` = agrupar * 2 + dividir. packed == 0 (disciplina ausente da tabela ou
# agrupar == 0) desliga a regra, como `disc.agrupar <= 0` no Rust.
def run_penalty(+len: U32, +packed: U32) -> U32:
  +g = U32.shrn(packed, 1n)
  +dividir = U32.and(packed, 1)
  +g = g
  +gs = Bool.pick(U32, U32.is_zero(g), 1, g)
  +ideal = Bool.pick(U32, U32.is_eq(dividir, 1), gs,
    U32.mul(U32.div(U32.add(U32.mul(len, 2), gs), U32.mul(gs, 2)), gs))
  +diff = Bool.pick(U32, U32.is_ge(len, ideal), U32.sub(len, ideal), U32.sub(ideal, len))
  Bool.pick(U32, U32.is_zero(g), 0, U32.mul(diff, 20))

# Varre os blocos contiguos de um dia de 4 tempos sem ramificar: len_i e o
# comprimento do bloco que TERMINA em i, e a posicao i so conta se o bloco
# realmente acaba ali (i == 3 ou o proximo tempo tem outra disciplina).
# Conferido por forca bruta contra a varredura sequencial nos 81 dias possiveis.
def eval_day_grouping(day: Day4, +gt: Table32) -> U32:
  D4{t0, t1, t2, t3} = day
  +t0 = t0; +t1 = t1; +t2 = t2; +t3 = t3
  +e01 = U32.is_eq(t0, t1)
  +e12 = U32.is_eq(t1, t2)
  +e23 = U32.is_eq(t2, t3)
  # l0 e sempre 1. Um literal ligado com `+` nao infere tipo em Bend 2 nem com
  # anotacao (`+x = (1 : U32)` => "cannot infer"), entao ele entra inline.
  +l1 = Bool.pick(U32, e01, 2, 1)
  +l2 = Bool.pick(U32, e12, U32.inc(l1), 1)
  +l3 = Bool.pick(U32, e23, U32.inc(l2), 1)
  +p0 = Bool.pick(U32, e01, 0, run_penalty(1, disc_group(gt, t0)))
  +p1 = Bool.pick(U32, e12, 0, run_penalty(l1, disc_group(gt, t1)))
  +p2 = Bool.pick(U32, e23, 0, run_penalty(l2, disc_group(gt, t2)))
  +p3 = run_penalty(l3, disc_group(gt, t3))
  (p0 + p1 + p2 + p3 : U32)

def eval_turma_grouping(w: Week5, +gt: Table32) -> U32:
  W5{d0, d1, d2, d3, d4} = w
  +p0 = eval_day_grouping(d0, gt)
  +p1 = eval_day_grouping(d1, gt)
  +p2 = eval_day_grouping(d2, gt)
  +p3 = eval_day_grouping(d3, gt)
  +p4 = eval_day_grouping(d4, gt)
  (p0 + p1 + p2 + p3 + p4 : U32)

def evaluate_quadro(q: Quadro3, spec: FastSpec) -> U32:
  Q3{t0, t1, t2} = q
  FSpec{+info, su, u1, u2} = spec
  +t0 = t0; +t1 = t1; +t2 = t2
  +g0 = eval_turma_grouping(t0, info)
  +g1 = eval_turma_grouping(t1, info)
  +g2 = eval_turma_grouping(t2, info)
  +group_total = (g0 + g1 + g2 : U32)
  +prof_total = eval_prof_penalties(t0, t1, t2, info, su)
  +unidas_total = eval_unidas_week(t0, t1, u1, u2)
  (group_total + prof_total + unidas_total : U32)

def fitness_cand(c: Cand) -> U32:
  CD{q, spec} = c
  +penalties = evaluate_quadro(q, spec)
  Bool.pick(U32, U32.is_lt(penalties, 10000), (10000 - penalties : U32), 0)

# ------------------------------------------------------------------------------
# 4. OPERADORES GENÉTICOS DINÂMICOS
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

def crossover_quadro(a: Quadro3, b: Quadro3, +mask: U32) -> Quadro3:
  Q3{t0_a, t1_a, t2_a} = a
  Q3{t0_b, t1_b, t2_b} = b
  make_q3(
    Bool.pick(Week5, U32.is_ne(U32.and(mask, 1), 0), t0_a, t0_b),
    Bool.pick(Week5, U32.is_ne(U32.and(mask, 2), 0), t1_a, t1_b),
    Bool.pick(Week5, U32.is_ne(U32.and(mask, 4), 0), t2_a, t2_b)
  )

def pick_better_cand(c: Bool, cand: Cand, +fc: U32, base: Cand, +fb: U32) -> GA.Ind<Cand>:
  match c:
    case True{}: GA.Ind{cand, fc}
    case False{}: GA.Ind{base, fb}

def reproduce_eval(parent: Cand, champ: Cand, seed: U32) -> GA.Ind<Cand>:
  CD{qp, +spec} = parent
  CD{qc, _} = champ
  +s1 = R.step(seed); +s2 = R.step(s1)
  +crossed_q = crossover_quadro(qp, qc, s1)
  +cand_q = mutate_quadro(crossed_q, s2)
  +cand = make_cand(cand_q, spec)
  +base = make_cand(crossed_q, spec)
  +fc = fitness_cand(cand)
  +fb = fitness_cand(base)
  pick_better_cand(U32.is_ge(fc, fb), cand, fc, base, fb)

def make_leaf(cand: Cand, +f: U32) -> T.PopTree<GA.Ind<Cand>>:
  T.Leaf{GA.Ind{cand, f}}

def make_node(l: T.PopTree<GA.Ind<Cand>>, r: T.PopTree<GA.Ind<Cand>>) -> T.PopTree<GA.Ind<Cand>>:
  T.Node{l, r}

def build_pop_tree(d: Nat, +base_q: Quadro3, +spec: FastSpec, +seed: U32) -> T.PopTree<GA.Ind<Cand>>:
  match d:
    case 0n:
      +shuffled = shuffle_quadro(base_q, seed)
      +cand = make_cand(shuffled, spec)
      +f = fitness_cand(cand)
      make_leaf(cand, f)
    case 1n+ +p:
      +seed = seed
      l r = build_pop_tree(p, base_q, spec, R.split.fst(seed)) build_pop_tree(p, base_q, spec, R.split.snd(seed))
      make_node(l, r)

# ------------------------------------------------------------------------------
# 5. CARGA E EXTRAÇÃO DINÂMICA DO JSON AST
# ------------------------------------------------------------------------------

type DiscEntry is Data:
  DEntry{nome: String, turma: String, aulas: U32, agrupar: U32, dividir: U32}

def load_turmas_names(items: List<&2, J.Json>) -> List<&2, String>:
  match items:
    case Nil{}: Nil{}
    case +h <> t:
      +nome = J.Json.get_str(h, "nome", "Turma")
      nome <> load_turmas_names(t)

# "dividir" vem como booleano JSON; JNum/ausente vira 0 (o default do Rust e false).
def json_bool_to_u32(m: Maybe<&2, J.Json>) -> U32:
  match m:
    case None{}: 0
    case Some{v}:
      match v:
        case J.JBool{b}: Bool.pick(U32, b, 1, 0)
        case _: 0

def load_disciplinas(items: List<&2, J.Json>) -> List<&2, DiscEntry>:
  match items:
    case Nil{}: Nil{}
    case +h <> t:
      +nome = J.Json.get_str(h, "nome", "")
      +turma = J.Json.get_str(h, "turma", "")
      +aulas = J.Json.get_num(h, "aulas", 2)
      +agrupar = J.Json.get_num(h, "agrupar", 2)
      +dividir = json_bool_to_u32(J.Json.get(h, "dividir"))
      DEntry{nome, turma, aulas, agrupar, dividir} <> load_disciplinas(t)

def load_disc_nomes(discs: List<&2, DiscEntry>) -> List<&2, String>:
  match discs:
    case Nil{}: Nil{}
    case h <> t:
      DEntry{nome, _, _, _, _} = h
      nome <> load_disc_nomes(t)

def json_is_target_num(j: J.Json, +target: U32) -> Bool:
  match j:
    case J.JNum{val}: U32.is_eq(val, target)
    case _: False{}

def list_contains_num(l: List<&2, J.Json>, +target: U32) -> Bool:
  match l:
    case Nil{}: False{}
    case h <> t:
      Bool.pick(Bool, json_is_target_num(h, target), True{}, list_contains_num(t, target))

def is_tempo_unavailable(+tempos_list: List<&2, J.Json>, +tempo_idx: U32) -> U32:
  +tempo_num = U32.inc(tempo_idx)
  +is_avail = list_contains_num(tempos_list, tempo_num)
  Bool.pick(U32, is_avail, 0, 1)

def day_unavail_mask(+day_arr: List<&2, J.Json>) -> U32:
  +b0 = is_tempo_unavailable(day_arr, 0)
  +b1 = is_tempo_unavailable(day_arr, 1)
  +b2 = is_tempo_unavailable(day_arr, 2)
  +b3 = is_tempo_unavailable(day_arr, 3)
  +m0 = b0
  +m1 = U32.shln(b1, 1n)
  +m2 = U32.shln(b2, 2n)
  +m3 = U32.shln(b3, 3n)
  U32.or(m0, U32.or(m1, U32.or(m2, m3)))

def prof_horarios_to_mask(h_obj: Maybe<&2, J.Json>) -> U32:
  match h_obj:
    case None{}:
      1048575 # 2^20 - 1
    case Some{+val}:
      +m_seg = day_unavail_mask(J.Json.get_arr(val, "seg"))
      +m_ter = day_unavail_mask(J.Json.get_arr(val, "ter"))
      +m_qua = day_unavail_mask(J.Json.get_arr(val, "qua"))
      +m_qui = day_unavail_mask(J.Json.get_arr(val, "qui"))
      +m_sex = day_unavail_mask(J.Json.get_arr(val, "sex"))
      +s0 = m_seg
      +s1 = U32.shln(m_ter, 4n)
      +s2 = U32.shln(m_qua, 8n)
      +s3 = U32.shln(m_qui, 12n)
      +s4 = U32.shln(m_sex, 16n)
      U32.or(s0, U32.or(s1, U32.or(s2, U32.or(s3, s4))))

def json_is_target_str(j: J.Json, +target: String) -> Bool:
  match j:
    case J.JStr{val}: String.eq(val, target)
    case _: False{}

def list_contains_str(l: List<&2, J.Json>, +target: String) -> Bool:
  match l:
    case Nil{}: False{}
    case h <> t:
      Bool.pick(Bool, json_is_target_str(h, target), True{}, list_contains_str(t, target))

# Conjunto de TODOS os professores que dao a disciplina, como bitmask (bit i =
# o i-esimo professor do array). A versao anterior devolvia so o primeiro id, o
# que descartava em silencio os demais — no dataset real, "Fabrica de Software
# III" tem dois professores e um deles simplesmente nao existia para a fitness.
def disc_prof_mask(+disc_nome: String, profs: List<&2, J.Json>, +bit: U32) -> U32:
  match profs:
    case Nil{}: 0
    case +h <> t:
      +discs_list = J.Json.get_arr(h, "disciplinas")
      +b = Bool.pick(U32, list_contains_str(discs_list, disc_nome), U32.shln(1, U32.to_nat(bit)), 0)
      U32.or(b, disc_prof_mask(disc_nome, t, U32.inc(bit)))

def build_disc_profs(discs: List<&2, DiscEntry>, +profs: List<&2, J.Json>) -> List<&2, U32>:
  match discs:
    case Nil{}: Nil{}
    case h <> t:
      DEntry{nome, _, _, _, _} = h
      +pm = disc_prof_mask(nome, profs, 0)
      pm <> build_disc_profs(t, profs)

# ATENCAO: satura em 4 — count >= 4 devolve 4 copias. Disciplinas com mais de 4
# aulas sao rejeitadas por validate_input (secao 5B) antes de chegar aqui.
# Mascara de professores nos bits 0-15 e (agrupar * 2 + dividir) nos bits 16-23.
# validate_input garante no maximo 15 professores e agrupar <= 127, entao os
# dois campos nunca se invadem.
def build_disc_info(discs: List<&2, DiscEntry>, pids: List<&2, U32>) -> List<&2, U32>:
  match discs:
    case Nil{}: Nil{}
    case h <> t:
      DEntry{_, _, _, agrupar, dividir} = h
      match pids:
        case Nil{}: Nil{}
        case p <> pt:
          +packed = U32.add(U32.mul(agrupar, 2), dividir)
          U32.add(p, U32.mul(packed, 65536)) <> build_disc_info(t, pt)

def repeat_val(+val: U32, +count: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(count, 0), Nil{},
    Bool.pick(List<&2, U32>, U32.is_eq(count, 1), (val <> Nil{}),
      Bool.pick(List<&2, U32>, U32.is_eq(count, 2), (val <> (val <> Nil{})),
        Bool.pick(List<&2, U32>, U32.is_eq(count, 3), (val <> (val <> (val <> Nil{}))),
          (val <> (val <> (val <> (val <> Nil{}))))))))

def collect_turma_slots(discs: List<&2, DiscEntry>, +turma_nome: String, +disc_id: U32) -> List<&2, U32>:
  match discs:
    case Nil{}: Nil{}
    case h <> t:
      DEntry{_, t_nome, aulas, _, _} = h
      +matching = String.eq(t_nome, turma_nome)
      +added = Bool.pick(List<&2, U32>, matching, repeat_val(disc_id, aulas), Nil{})
      List.append(&2, U32, added, collect_turma_slots(t, turma_nome, U32.inc(disc_id)))

def load_profs_unavail_masks(profs: List<&2, J.Json>) -> List<&2, U32>:
  match profs:
    case Nil{}: Nil{}
    case +h <> t:
      +m = prof_horarios_to_mask(J.Json.get(h, "horarios"))
      m <> load_profs_unavail_masks(t)

# Colhe o bit `slot` da mascara de cada professor e os empilha num conjunto:
# resultado[bit i] = o i-esimo professor esta indisponivel neste slot.
def transpose_slot(pmasks: List<&2, U32>, +slot: U32, +bit: U32) -> U32:
  match pmasks:
    case Nil{}: 0
    case h <> t:
      +b = U32.and(U32.shrn(h, U32.to_nat(slot)), 1)
      U32.or(U32.shln(b, U32.to_nat(bit)), transpose_slot(t, slot, U32.inc(bit)))

# Cada palavra junta os slots 2w (bits 0-15) e 2w+1 (bits 16-31).
def build_slot_unavail(n: Nat, +pmasks: List<&2, U32>, +slot: U32) -> List<&2, U32>:
  match n:
    case 0n: Nil{}
    case 1n+p:
      +lo = transpose_slot(pmasks, slot, 0)
      +hi = transpose_slot(pmasks, U32.inc(slot), 0)
      +w = U32.or(lo, U32.shln(hi, 16n))
      w <> build_slot_unavail(p, pmasks, U32.add(slot, 2))

def list_find_disc_index(l: List<&2, DiscEntry>, +target: String, +cur: U32) -> U32:
  match l:
    case Nil{}: 0
    case h <> t:
      DEntry{nome, _, _, _, _} = h
      Bool.pick(U32, String.eq(nome, target), cur, list_find_disc_index(t, target, U32.inc(cur)))

def json_to_str(j: J.Json) -> String:
  match j:
    case J.JStr{s}: s
    case _: ""

type UnidasPair is Data:
  UPair{u1: U32, u2: U32}

def load_unidas_pair.step(g_discs: List<&2, J.Json>, +discs: List<&2, DiscEntry>) -> UnidasPair:
  match g_discs:
    case d1 <> d2 <> _:
      +n1 = json_to_str(d1)
      +n2 = json_to_str(d2)
      UPair{list_find_disc_index(discs, n1, 1), list_find_disc_index(discs, n2, 1)}
    case _: UPair{0, 0}

def load_unidas_pair(unidas_arr: List<&2, J.Json>, +discs: List<&2, DiscEntry>) -> UnidasPair:
  match unidas_arr:
    case Nil{}: UPair{0, 0}
    case h <> _:
      load_unidas_pair.step(J.Json.get_arr(h, "disciplinas"), discs)

# ATENCAO: com menos de 20 slots o case _ devolve uma semana INTEIRA DE ZEROS,
# ou seja, a turma desaparece do quadro. Com mais de 20, o excedente e ignorado.
# validate_input (secao 5B) exige exatamente 20 antes de chamar esta funcao.
def slots20_to_week5(slots: List<&2, U32>) -> Week5:
  match slots:
    case s0 <> s1 <> s2 <> s3 <> s4 <> s5 <> s6 <> s7 <> s8 <> s9 <> s10 <> s11 <> s12 <> s13 <> s14 <> s15 <> s16 <> s17 <> s18 <> s19 <> _:
      make_w5(
        make_d4(s0, s1, s2, s3),
        make_d4(s4, s5, s6, s7),
        make_d4(s8, s9, s10, s11),
        make_d4(s12, s13, s14, s15),
        make_d4(s16, s17, s18, s19)
      )
    case _:
      make_w5(
        make_d4(0, 0, 0, 0),
        make_d4(0, 0, 0, 0),
        make_d4(0, 0, 0, 0),
        make_d4(0, 0, 0, 0),
        make_d4(0, 0, 0, 0)
      )

# ------------------------------------------------------------------------------
# 5B. VALIDAÇÃO DA ENTRADA
# ------------------------------------------------------------------------------
# As estruturas deste solver têm forma FIXA (Quadro3, Table16, Table32,
# repeat_val, slots20_to_week5). Fora dos limites abaixo, elas truncam ou
# devolvem zeros em silêncio — o solver produziria uma grade errada sem nenhum
# aviso. Estas checagens rodam ANTES da evolução e abortam com mensagem.
#
#   turmas          : exatamente 3        (Quadro3)
#   slots por turma : exatamente 20       (Week5 = 5 dias x 4 tempos)
#   disciplinas     : 1..31               (Table32 indexada a partir de 1)
#   professores     : 1..15               (Table16 indexada a partir de 1)
#   aulas por disc. : 1..4                (teto de repeat_val)
# ------------------------------------------------------------------------------

def err_unless(ok: Bool, msg: String) -> List<&2, String>:
  match ok:
    case True{}: Nil{}
    case False{}: msg <> Nil{}

def join_lines(l: List<&2, String>) -> String:
  match l:
    case Nil{}: ""
    case h <> t: "  - " ++ h ++ "\n" ++ join_lines(t)

def list_has_str(l: List<&2, String>, +target: String) -> Bool:
  match l:
    case Nil{}: False{}
    case +h <> t:
      Bool.pick(Bool, String.eq(h, target), True{}, list_has_str(t, target))

# Bend 2 nao aceita recursao mutua, entao cada checagem recursiva monta a
# mensagem do elemento atual com err_unless (nao recursivo) e concatena com a
# chamada recursiva direta, em vez de delegar o branch a uma funcao .step.

# Uma disciplina cujo campo "turma" nao bate com nenhuma turma declarada nunca
# entra em collect_turma_slots: ela some do quadro sem aparecer em lugar nenhum.
def check_disc_turmas(discs: List<&2, DiscEntry>, +turmas: List<&2, String>) -> List<&2, String>:
  match discs:
    case Nil{}: Nil{}
    case h <> t:
      DEntry{nome, turma, _, _, _} = h
      +turma = turma
      +e = err_unless(list_has_str(turmas, turma),
        "disciplina \"" ++ nome ++ "\" referencia a turma \"" ++ turma ++
        "\", que nao existe no array turmas")
      List.append(&2, String, e, check_disc_turmas(t, turmas))

def check_aulas(discs: List<&2, DiscEntry>) -> List<&2, String>:
  match discs:
    case Nil{}: Nil{}
    case h <> t:
      DEntry{nome, _, aulas, _, _} = h
      +aulas = aulas
      +e = err_unless(Bool.and(U32.is_ge(aulas, 1), U32.is_le(aulas, 4)),
        "disciplina \"" ++ nome ++ "\" tem aulas=" ++ U32.show(aulas) ++
        "; este solver suporta 1 a 4 (repeat_val satura em 4)")
      List.append(&2, String, e, check_aulas(t))

# agrupar ocupa os bits 8-15 de disc_info como (agrupar * 2 + dividir), entao
# precisa caber em 7 bits para nao invadir o campo vizinho.
def check_agrupar(discs: List<&2, DiscEntry>) -> List<&2, String>:
  match discs:
    case Nil{}: Nil{}
    case h <> t:
      DEntry{nome, _, _, agrupar, _} = h
      +agrupar = agrupar
      +e = err_unless(U32.is_le(agrupar, 127),
        "disciplina \"" ++ nome ++ "\" tem agrupar=" ++ U32.show(agrupar) ++
        "; o maximo empacotavel nos bits 16-23 de disc_info e 127")
      List.append(&2, String, e, check_agrupar(t))

# mascara 0 significa que a disciplina nao aparece em nenhum professor: ela
# deixa de gerar qualquer penalidade de choque ou indisponibilidade.
def check_disc_profs(discs: List<&2, DiscEntry>, pids: List<&2, U32>) -> List<&2, String>:
  match discs:
    case Nil{}: Nil{}
    case h <> t:
      DEntry{nome, _, _, _, _} = h
      match pids:
        case Nil{}: Nil{}
        case p <> pt:
          +e = err_unless(U32.is_gt(p, 0),
            "disciplina \"" ++ nome ++ "\" nao aparece em nenhum item de professores[]")
          List.append(&2, String, e, check_disc_profs(t, pt))

def check_slots(nome: String, +n: Nat) -> List<&2, String>:
  err_unless(Nat.is_eq(n, 20n),
    "turma \"" ++ nome ++ "\" soma " ++ Nat.show(n) ++
    " aulas; Week5 exige exatamente 20 (5 dias x 4 tempos)")

def validate_input(+turmas: List<&2, String>, +discs: List<&2, DiscEntry>,
                   disc_profs: List<&2, U32>, +n_turmas: Nat, +n_discs: Nat, +n_profs: Nat,
                   n0: String, n1: String, n2: String,
                   +s0: Nat, +s1: Nat, +s2: Nat) -> List<&2, String>:
  +e_turmas = err_unless(Nat.is_eq(n_turmas, 3n),
    "o array turmas tem " ++ Nat.show(n_turmas) ++ " itens; Quadro3 exige exatamente 3")
  +e_discs = err_unless(Bool.and(Nat.is_gt(n_discs, 0n), Nat.is_le(n_discs, 31n)),
    "o array disciplinas tem " ++ Nat.show(n_discs) ++ " itens; Table32 comporta 1 a 31")
  +e_profs = err_unless(Bool.and(Nat.is_gt(n_profs, 0n), Nat.is_le(n_profs, 15n)),
    "o array professores tem " ++ Nat.show(n_profs) ++ " itens; Table16 comporta 1 a 15")
  +e_s0 = check_slots(n0, s0)
  +e_s1 = check_slots(n1, s1)
  +e_s2 = check_slots(n2, s2)
  +e_aulas = check_aulas(discs)
  +e_agrup = check_agrupar(discs)
  +e_dturma = check_disc_turmas(discs, turmas)
  +e_dprof = check_disc_profs(discs, disc_profs)
  List.concat(&2, String,
    [e_turmas, e_discs, e_profs, e_s0, e_s1, e_s2, e_aulas, e_agrup, e_dturma, e_dprof])

# ------------------------------------------------------------------------------
# 6. SERIALIZAÇÃO DINÂMICA DO RESULTADO (TurmaHorarioResult[])
# ------------------------------------------------------------------------------

def get_str.step(m: Maybe<&2, String>, default: String) -> String:
  match m:
    case None{}: default
    case Some{v}: v

def list_get_str(l: List<&2, String>, +idx: U32, default: String) -> String:
  get_str.step(List.get(&2, String, l, U32.to_nat(idx)), default)

def list_get_disc_nome.step(is_gt: Bool, l: List<&2, String>, disc_id: U32) -> String:
  match is_gt:
    case False{}: "Livre"
    case True{}: get_str.step(List.get(&2, String, l, U32.to_nat(U32.sub(disc_id, 1))), "Livre")

def list_get_disc_nome(l: List<&2, String>, +disc_id: U32) -> String:
  list_get_disc_nome.step(U32.is_gt(disc_id, 0), l, disc_id)

def dia_to_str(+idx: U32) -> String:
  Bool.pick(String, U32.is_lt(idx, 3),
    Bool.pick(String, U32.is_eq(idx, 0), "Segunda",
      Bool.pick(String, U32.is_eq(idx, 1), "Terca", "Quarta")),
    Bool.pick(String, U32.is_eq(idx, 3), "Quinta", "Sexta"))

def serialize_tempos(d: Day4, +disc_nomes: List<&2, String>) -> List<&2, J.Json>:
  D4{t0, t1, t2, t3} = d
  (J.JObj{["descricao"], [J.JStr{list_get_disc_nome(disc_nomes, t0)}]} <>
  (J.JObj{["descricao"], [J.JStr{list_get_disc_nome(disc_nomes, t1)}]} <>
  (J.JObj{["descricao"], [J.JStr{list_get_disc_nome(disc_nomes, t2)}]} <>
  (J.JObj{["descricao"], [J.JStr{list_get_disc_nome(disc_nomes, t3)}]} <> Nil{}))))

def serialize_dia(+idx: U32, d: Day4, +disc_nomes: List<&2, String>) -> J.Json:
  J.JObj{
    ["dia", "tempos"],
    [J.JStr{dia_to_str(idx)}, J.JArr{serialize_tempos(d, disc_nomes)}]
  }

def serialize_turma(nome: String, w: Week5, +disc_nomes: List<&2, String>) -> J.Json:
  W5{d0, d1, d2, d3, d4} = w
  J.JObj{
    ["turma", "horario"],
    [
      J.JStr{nome},
      J.JArr{[
        serialize_dia(0, d0, disc_nomes),
        serialize_dia(1, d1, disc_nomes),
        serialize_dia(2, d2, disc_nomes),
        serialize_dia(3, d3, disc_nomes),
        serialize_dia(4, d4, disc_nomes)
      ]}
    ]
  }

def serialize_resultado(q: Quadro3, +turmas: List<&2, String>, +disc_nomes: List<&2, String>) -> J.Json:
  Q3{t0, t1, t2} = q
  +n0 = list_get_str(turmas, 0, "Turma 1")
  +n1 = list_get_str(turmas, 1, "Turma 2")
  +n2 = list_get_str(turmas, 2, "Turma 3")
  J.JArr{[
    serialize_turma(n0, t0, disc_nomes),
    serialize_turma(n1, t1, disc_nomes),
    serialize_turma(n2, t2, disc_nomes)
  ]}

# ------------------------------------------------------------------------------
# 7. EXECUÇÃO DA OTIMIZAÇÃO E ENTRADA PRINCIPAL
# ------------------------------------------------------------------------------

def run_evolution(+base_q: Quadro3, +spec: FastSpec, +generations: Nat, +seed: U32) -> Cand:
  +pop0 = build_pop_tree(5n, base_q, spec, seed)
  +pop_final = GA.run_generations_eval(~Cand, ~reproduce_eval, generations, pop0, R.step(seed))
  +best_fin = GA.best_ind(Cand, pop_final)
  GA.Ind.gene(Cand, best_fin)

def solve_from_form_data.report(champion_cand: Cand, +turmas: List<&2, String>, +disc_nomes: List<&2, String>, +n_profs: Nat, +generations: Nat) -> IO(Unit):
  CD{+champion_q, spec_res} = champion_cand
  +penalties = evaluate_quadro(champion_q, spec_res)
  +fit_val = Bool.pick(U32, U32.is_lt(penalties, 10000), (10000 - penalties : U32), 0)
  +json_result = serialize_resultado(champion_q, turmas, disc_nomes)
  +json_str = J.Json.stringify(json_result)

  IO.print(
    "================================================================\n" ++
    "  SOLVER DE HORÁRIO ESCOLAR EM BEND 2 (dados via HORARIO_JSON)\n" ++
    "================================================================\n" ++
    "Turmas Identificadas: " ++ Nat.show(List.length(&2, String, turmas)) ++ "\n" ++
    "Disciplinas Mapeadas: " ++ Nat.show(List.length(&2, String, disc_nomes)) ++ "\n" ++
    "Professores Mapeados: " ++ Nat.show(n_profs) ++ "\n" ++
    "Melhor Aptidão:       " ++ U32.show(fit_val) ++ " / 10000 pts\n" ++
    "Penalidades Finais:   " ++ U32.show(penalties) ++ " (Ótimo = 0)\n" ++
    "População:            32 indivíduos (árvore binária profundidade 5)\n" ++
    "Gerações Executadas:  " ++ Nat.show(generations) ++ "\n" ++
    "================================================================\n" ++
    "RESULTADO JSON SERIALIZADO (TurmaHorarioResult[]):\n" ++
    json_str ++ "\n" ++
    "================================================================\n"
  )

def solve_from_form_data.run(base_q: Quadro3, spec: FastSpec, turmas: List<&2, String>,
                             disc_nomes: List<&2, String>, +n_profs: Nat,
                             +generations: Nat, +seed: U32) -> IO(Unit):
  +champion = run_evolution(base_q, spec, generations, seed)
  solve_from_form_data.report(champion, turmas, disc_nomes, n_profs, generations)

# Se validate_input achou qualquer problema, aborta ANTES de evoluir: uma grade
# produzida a partir de entrada truncada seria silenciosamente errada.
def solve_from_form_data.guard(errs: List<&2, String>, base_q: Quadro3, spec: FastSpec,
                               turmas: List<&2, String>, disc_nomes: List<&2, String>,
                               +n_profs: Nat, +generations: Nat, +seed: U32) -> IO(Unit):
  match errs:
    case Nil{}:
      solve_from_form_data.run(base_q, spec, turmas, disc_nomes, n_profs, generations, seed)
    case h <> t:
      IO.print(
        "================================================================\n" ++
        "ERRO: a entrada nao cabe na forma fixa deste solver.\n" ++
        "================================================================\n" ++
        join_lines(h <> t) ++
        "================================================================\n" ++
        "Nenhuma evolucao foi executada. Os limites estao documentados na\n" ++
        "secao 5B deste arquivo e no README.md da raiz.\n" ++
        "================================================================\n"
      )

def solve_from_form_data.step(u_pair: UnidasPair, +turmas: List<&2, String>, +discs: List<&2, DiscEntry>,
                              disc_nomes: List<&2, String>, +disc_profs: List<&2, U32>,
                              prof_masks: List<&2, U32>, +n_profs: Nat, +generations: Nat, +seed: U32) -> IO(Unit):
  UPair{u1, u2} = u_pair
  +n0 = list_get_str(turmas, 0, "Turma 1")
  +n1 = list_get_str(turmas, 1, "Turma 2")
  +n2 = list_get_str(turmas, 2, "Turma 3")
  +t0_slots = collect_turma_slots(discs, n0, 1)
  +t1_slots = collect_turma_slots(discs, n1, 1)
  +t2_slots = collect_turma_slots(discs, n2, 1)
  +errs = validate_input(turmas, discs, disc_profs,
                         List.length(&2, String, turmas),
                         List.length(&2, DiscEntry, discs),
                         n_profs, n0, n1, n2,
                         List.length(&2, U32, t0_slots),
                         List.length(&2, U32, t1_slots),
                         List.length(&2, U32, t2_slots))
  +base_q = make_q3(slots20_to_week5(t0_slots), slots20_to_week5(t1_slots), slots20_to_week5(t2_slots))
  +info_table = fill_table32(build_disc_info(discs, disc_profs), empty_t32(), 1)
  # slot_unavail e indexada de 0 (slots 0..19), nao de 1 como as tabelas de
  # disciplina/professor.
  +su_table = fill_table16(build_slot_unavail(10n, prof_masks, 0), empty_t16(), 0)
  +spec = make_fspec(info_table, su_table, u1, u2)
  solve_from_form_data.guard(errs, base_q, spec, turmas, disc_nomes, n_profs, generations, seed)

def solve_from_form_data(+fd: J.Json, +generations: Nat, +seed: U32) -> IO(Unit):
  +turmas_arr = J.Json.get_arr(fd, "turmas")
  +discs_arr = J.Json.get_arr(fd, "disciplinas")
  +profs_arr = J.Json.get_arr(fd, "professores")
  +unidas_arr = J.Json.get_arr(fd, "disciplinas_unidas")

  +turmas = load_turmas_names(turmas_arr)
  +discs = load_disciplinas(discs_arr)
  +disc_nomes = load_disc_nomes(discs)
  +disc_profs = build_disc_profs(discs, profs_arr)
  +prof_masks = load_profs_unavail_masks(profs_arr)
  +n_profs = List.length(&2, J.Json, profs_arr)
  +u_pair = load_unidas_pair(unidas_arr, discs)
  solve_from_form_data.step(u_pair, turmas, discs, disc_nomes, disc_profs, prof_masks, n_profs, generations, seed)

def main.handle_form_data(form_data: Maybe<&2, J.Json>) -> IO(Unit):
  match form_data:
    case None{}:
      IO.print("Erro: formData ausente no JSON fornecido.\n")
    case Some{+fd}:
      solve_from_form_data(fd, 400n, 88442211)

def main.handle_root(root: J.Json) -> IO(Unit):
  main.handle_form_data(J.Json.get(root, "formData"))

def main.handle_parse(res: J.ParseRes) -> IO(Unit):
  match res:
    case J.PFail{err}:
      IO.print("Falha ao analisar JSON: " ++ err ++ "\n")
    case J.POk{root}:
      main.handle_root(root)

def main.dispatch(env_res: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match env_res:
    case Fail{_}:
      IO.print("Aviso: HORARIO_JSON nao encontrado no ambiente. Forneça o JSON via env HORARIO_JSON.\n")
    case Done{json_str}:
      main.handle_parse(J.parse_json(json_str))

def main() -> IO(Unit):
  do IO<Unit>:
    env_res : Result<&1, &1, U32 & String, String> <- IO.get_env("HORARIO_JSON")
    main.dispatch(env_res)
