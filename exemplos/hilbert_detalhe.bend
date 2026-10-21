import Base
import ./../utils/io.bend as IOU
import ./../utils/math.bend as M
import ./../utils/arquivos.bend as Arq
import ./../utils/bmp.bend as Bmp
import ./../utils/aritmetico.bend as A
import hilbert.bend as H

# ================================================================
# ACHATA O QUE É SUAVE, GUARDA O QUE É BRUSCO
# ================================================================
# A curva vira uma sequência de trechos. O que corta um trecho é o que acontece
# entre dois pixels SEGUIDOS na curva, e não a distância até a primeira cor:
#
#   - um degradê muda pouco a cada passo: vira um trecho só;
#   - uma borda (de letra, entre duas frutas) muda muito num passo: corta;
#   - uma textura (grama, casca, pelo) OSCILA: o passo inverte de direção
#     seguidamente, e isso também corta, mesmo com passos pequenos.
#
# Três critérios de corte:
#
#   salto   a DIFERENÇA PERCEBIDA entre dois pixels seguidos passou do limite.
#           A diferença é a "redmean" (compuphase): distância RGB com pesos
#           que mudam com o vermelho médio, aproximando como o olho compara
#           cores. Só inteiros, e enxerga mudança de matiz com a mesma luz,
#           que o máximo entre canais deixava passar (o limão "derretia" no
#           repolho).
#   faixa   a cor derivou demais da primeira cor do trecho (mesma distância).
#   textura dois passos seguidos acima do ruído (`textura`, no maior canal)
#           apontando em sentidos opostos (produto escalar negativo em RGB):
#           isso é oscilação. Um degradê não inverte; uma textura, sim.
#
# Cada trecho vai para o codificador aritmético (utils/aritmetico.bend):
#   - comprimento - 1;
#   - cor inicial, como diferença para a cor final do trecho anterior;
#   - se o trecho tem 16+ pixels, a cor final, como diferença para a inicial.
#     O decodificador interpola entre as duas ao longo da curva: um degradê
#     vira uma rampa em vez de faixas. As duas pontas vêm do ajuste por
#     mínimos quadrados (a reta que melhor passa pelas cores do trecho).
# Cores com verde primeiro; contexto = tamanho do trecho anterior.
#
# PÓS-FILTRO (só no decodificador, opcional): suaviza os pixels de trechos
# lisos (3+ pixels) com a média dos vizinhos em 2D que também são lisos e de
# cor próxima. Detalhe (trechos de 1-2 pixels) nunca é tocado, e a cor não
# vaza por bordas. A classe do pixel vai no byte alto do próprio pixel.
#
# Arquivo: "HIL4", ordem, salto, faixa, textura, largura e altura (u32),
# depois a saída do codificador aritmético.
#
#   ../bin/hilbert_detalhe codifica foto.bmp foto.hil4 [salto=24] [faixa=48] [textura=6] [ordem=0]
#   ../bin/hilbert_detalhe decodifica foto.hil4 foto2.bmp [raio=2]

def Cab.tamanho() -> U32: 16

# Maior trecho: mantém as somas do ajuste da reta dentro de 32 bits (ver
# `bi`), e o comprimento - 1 cabe no Exp-Golomb do codificador (até 511).
def Trecho.maximo() -> U32: 256

# A partir de quantos pixels o trecho grava também a cor final
def Trecho.linear() -> U32: 16

# O pixel reconstruído carrega no byte alto se veio de um trecho liso
def Liso.bit() -> U32: 16777216

type Cfg is Data:
  Cfg{largura: U32, altura: U32, salto: U32, faixa: U32, textura: U32}

def Cfg.largura(+cfg: Cfg) -> U32:
  Cfg{w, h, s, f, t} = cfg
  w

def Cfg.altura(+cfg: Cfg) -> U32:
  Cfg{w, h, s, f, t} = cfg
  h

def Cfg.salto(+cfg: Cfg) -> U32:
  Cfg{w, h, s, f, t} = cfg
  s

def Cfg.faixa(+cfg: Cfg) -> U32:
  Cfg{w, h, s, f, t} = cfg
  f

def Cfg.textura(+cfg: Cfg) -> U32:
  Cfg{w, h, s, f, t} = cfg
  t

def Cfg.dentro(+cfg: Cfg, +x: U32, +y: U32) -> Bool:
  Cfg{w, h, s, f, t} = cfg
  U32.is_lt(x, w) && U32.is_lt(y, h)

def Cfg.indice(+cfg: Cfg, +x: U32, +y: U32) -> U32:
  (y * Cfg.largura(cfg) + x : U32)

# 0: trecho de 1 pixel (detalhe), 1: curto (2..8), 2: longo
def classe(+n: U32) -> U32:
  Bool.pick(U32, U32.is_le(n, 1), 0, Bool.pick(U32, U32.is_le(n, 8), 1, 2))

# Um valor com sinal saturado em 0..255
def satura(+v: U32) -> U32:
  Bool.pick(U32, A.neg(v), 0, U32.min(v, 255))

# Capacidade da saída: 4 bytes por pixel (ruído puro sem perdas gasta ~3,5);
# `grava` confere no fim.
def capacidade(+np: U32) -> U32:
  (np * 4 + 1024 : U32)

# ----------------------------------------------------------------
# PERCURSO: Hilbert (ordem 0) ou linha a linha (1), com a mesma callback
# ----------------------------------------------------------------
# A curva cobre o quadrado 2^n que contém a imagem; quem visita pula as
# posições de fora (`Cfg.dentro`), e o decodificador pula as mesmas.

def linhas(~S: Type, ~f: S -> H.Vec2 -> H.Dir -> H.Dir -> S, k: Nat, +w: U32, +p: U32, acc: S) -> S:
  match k:
    case 0n:
      f(acc, H.Vec2{(p % w : U32), (p / w : U32)}, H.Leste{}, H.Leste{})
    case 1n+q:
      linhas(~S, ~f, q, w, (p + 1 : U32), f(acc, H.Vec2{(p % w : U32), (p / w : U32)}, H.Leste{}, H.Leste{}))

def percorre(~S: Type, ~f: S -> H.Vec2 -> H.Dir -> H.Dir -> S, +ordem: U32, +w: U32, +h: U32, acc: S) -> S:
  match ordem:
    case 0: H.hilbert(~S, ~f, M.log2_ceil(U32.max(w, h)), acc)
    case _: linhas(~S, ~f, U32.to_nat((w * h - 1 : U32)), w, 0, acc)

# ----------------------------------------------------------------
# DIFERENÇA PERCEBIDA ENTRE DUAS CORES
# ----------------------------------------------------------------

# redmean ao quadrado: ((2 + r̄/256)·ΔR² + 4·ΔG² + (2 + (255-r̄)/256)·ΔB²)·256
def dist2(+a: U32, +b: U32) -> U32:
  +rm = ((Bmp.vermelho(a) + Bmp.vermelho(b)) / 2 : U32)
  +dr = A.sabs((Bmp.vermelho(a) - Bmp.vermelho(b) : U32))
  +dg = A.sabs((Bmp.verde(a) - Bmp.verde(b) : U32))
  +db = A.sabs((Bmp.azul(a) - Bmp.azul(b) : U32))
  (U32.shrn(((512 + rm) * dr * dr : U32), 8n) + 4 * dg * dg + U32.shrn(((767 - rm) * db * db : U32), 8n) : U32)

# Mais longe que `lim`? A escala é metade da raiz do redmean: num cinza, uma
# diferença d em cada canal vale ~1,5·d; só no verde, d; só no vermelho, ~0,8·d.
def longe(+a: U32, +b: U32, +lim: U32) -> Bool:
  +r = (2 * lim + 1 : U32)
  U32.is_ge(dist2(a, b), (r * r : U32))

# ----------------------------------------------------------------
# O TRECHO EM CONSTRUÇÃO
# ----------------------------------------------------------------
# n; âncora (primeira cor); soma de cada canal; soma de i·canal (i = posição
# no trecho), para o ajuste da reta; o último passo acima do ruído (com sinal)
# e quantas inversões seguidas houve.
type Tr is Data:
  Tr{n: U32, anc: U32, sr: U32, sg: U32, sb: U32, ir: U32, ig: U32, ib: U32, pr: U32, pg: U32, pb: U32, inv: U32}

def Tr.vazio() -> Tr:
  Tr{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}

def Tr.n(+tr: Tr) -> U32:
  Tr{n, anc, sr, sg, sb, ir, ig, ib, pr, pg, pb, inv} = tr
  n

def Tr.anc(+tr: Tr) -> U32:
  Tr{n, anc, sr, sg, sb, ir, ig, ib, pr, pg, pb, inv} = tr
  anc

def Tr.novo(+c: U32) -> Tr:
  Tr{1, c, Bmp.vermelho(c), Bmp.verde(c), Bmp.azul(c), 0, 0, 0, 0, 0, 0, 0}

def Tr.inv(+tr: Tr) -> U32:
  Tr{n, anc, sr, sg, sb, ir, ig, ib, pr, pg, pb, inv} = tr
  inv

# O passo c - p é "significativo" se algum canal mudou mais que o ruído
def significativo(+p: U32, +c: U32, +ruido: U32) -> Bool:
  +dr = A.sabs((Bmp.vermelho(c) - Bmp.vermelho(p) : U32))
  +dg = A.sabs((Bmp.verde(c) - Bmp.verde(p) : U32))
  +db = A.sabs((Bmp.azul(c) - Bmp.azul(p) : U32))
  U32.is_ne(ruido, 0) && U32.is_gt(U32.max(dr, U32.max(dg, db)), ruido)

# O passo c - p aponta para o lado oposto do último passo significativo?
# (produto escalar negativo; sem passo guardado, o produto é 0)
def inverte(+tr: Tr, +p: U32, +c: U32) -> Bool:
  Tr{n, anc, sr, sg, sb, ir, ig, ib, pr, pg, pb, inv} = tr
  A.neg((pr * (Bmp.vermelho(c) - Bmp.vermelho(p)) + pg * (Bmp.verde(c) - Bmp.verde(p)) +
          pb * (Bmp.azul(c) - Bmp.azul(p)) : U32))

def Tr.estende.soma(+tr: Tr, +c: U32, +sig: Bool, +inv2: U32, +dr: U32, +dg: U32, +db: U32) -> Tr:
  Tr{+n, anc, sr, sg, sb, ir, ig, ib, pr, pg, pb, inv} = tr
  Tr{(n + 1 : U32), anc,
     (sr + Bmp.vermelho(c) : U32), (sg + Bmp.verde(c) : U32), (sb + Bmp.azul(c) : U32),
     (ir + n * Bmp.vermelho(c) : U32), (ig + n * Bmp.verde(c) : U32), (ib + n * Bmp.azul(c) : U32),
     Bool.pick(U32, sig, dr, pr), Bool.pick(U32, sig, dg, pg), Bool.pick(U32, sig, db, pb), inv2}

# Mais um pixel no trecho: somas, soma ponderada pela posição, e o estado da
# detecção de textura (guarda o passo se for significativo; conta inversões
# seguidas, zera numa não inversão).
def Tr.estende(+tr: Tr, +p: U32, +c: U32, +ruido: U32) -> Tr:
  +sig = significativo(p, c, ruido)
  +inv = Bool.pick(U32, sig, Bool.pick(U32, inverte(tr, p, c), (Tr.inv(tr) + 1 : U32), 0), Tr.inv(tr))
  Tr.estende.soma(tr, c, sig, inv, (Bmp.vermelho(c) - Bmp.vermelho(p) : U32),
    (Bmp.verde(c) - Bmp.verde(p) : U32), (Bmp.azul(c) - Bmp.azul(p) : U32))

# Corta antes de `c`? Um trecho vazio nunca corta. (`maximo` é ligado antes
# do `||`: no 2.0.29 uma comparação com def constante dentro de um `||` sai
# sempre `True` no nativo, e todo pixel virava um trecho; Armadilha 12.)
def corta(+cfg: Cfg, +tr: Tr, +p: U32, +c: U32) -> Bool:
  +n = Tr.n(tr)
  +maximo = Trecho.maximo()
  U32.is_ne(n, 0) && (
    U32.is_ge(n, maximo) ||
    longe(p, c, Cfg.salto(cfg)) ||
    longe(Tr.anc(tr), c, Cfg.faixa(cfg)) ||
    (significativo(p, c, Cfg.textura(cfg)) && inverte(tr, p, c) && U32.is_ge(Tr.inv(tr), 1)))

# ----------------------------------------------------------------
# AS PONTAS DO TRECHO (ajuste da reta por mínimos quadrados)
# ----------------------------------------------------------------
# Para as cores c_i (i = 0..n-1) de um canal, a reta c(i) = média + b·(i - ī)
# tem pontas média ∓ b·ī, e
#   b·ī = 6·(n·Σic - Σi·Σc) / (n² (n+1))       (Σi = n(n-1)/2)
# Com n <= 256, n·Σic e Σi·Σc ficam abaixo de 2^31: a diferença cabe num U32
# com sinal. Dividir por n primeiro evita estourar no 6·.

# x / d arredondado, com x com sinal e d > 0
def sdiv(+x: U32, +d: U32) -> U32:
  +q = ((A.sabs(x) + d / 2) / d : U32)
  Bool.pick(U32, A.neg(x), (0 - q : U32), q)

def bi(+s: U32, +si: U32, +n: U32) -> U32:
  +num = (n * si - (n * (n - 1) / 2) * s : U32)
  sdiv((6 * sdiv(num, n) : U32), (n * (n + 1) : U32))

# Ponta de um canal: lado 0 = início, 1 = fim. Trecho curto: a média.
def ponta(+s: U32, +si: U32, +n: U32, +lado: U32) -> U32:
  +m = ((s + n / 2) / n : U32)
  +d = Bool.pick(U32, U32.is_ge(n, Trecho.linear()), bi(s, si, n), 0)
  satura(Bool.pick(U32, U32.is_zero(lado), (m - d : U32), (m + d : U32)))

def Tr.cor(+tr: Tr, +lado: U32) -> U32:
  Tr{+n, anc, +sr, +sg, +sb, +ir, +ig, +ib, pr, pg, pb, inv} = tr
  Bmp.rgb(ponta(sr, ir, n, lado), ponta(sg, ig, n, lado), ponta(sb, ib, n, lado))

# ----------------------------------------------------------------
# CONTEXTOS (no array de 2048 probabilidades do codificador)
# ----------------------------------------------------------------
# cor inicial: um bloco de 128 por (canal, classe do trecho anterior), 0..1151
# comprimento: um bloco por classe do trecho anterior, 1152..1535
# cor final: um bloco por canal, 1536..1919

def ctx.cor(+canal: U32, +cls: U32) -> U32:
  ((canal * 3 + cls) * 128 : U32)

def ctx.comp(+cls: U32) -> U32:
  (1152 + cls * 128 : U32)

def ctx.fim(+canal: U32) -> U32:
  (1536 + canal * 128 : U32)

# ----------------------------------------------------------------
# CODIFICADOR
# ----------------------------------------------------------------

# Uma cor como diferença de outra, verde primeiro
def emite.cor(e: A.Enc, +cor: U32, +ant: U32, +b0: U32, +b1: U32, +b2: U32) -> A.Enc:
  +kg = (Bmp.verde(cor) - Bmp.verde(ant) : U32)
  e = A.enc.k(e, b0, kg)
  e = A.enc.k(e, b1, (Bmp.vermelho(cor) - Bmp.vermelho(ant) - kg : U32))
  A.enc.k(e, b2, (Bmp.azul(cor) - Bmp.azul(ant) - kg : U32))

def emite.fim(linear: Bool, e: A.Enc, +c0: U32, +c1: U32) -> A.Enc:
  match linear:
    case False{}: e
    case True{}: emite.cor(e, c1, c0, ctx.fim(0), ctx.fim(1), ctx.fim(2))

# Grava um trecho: comprimento - 1, cor inicial e, se for longo, a final
def emite(e: A.Enc, +tr: Tr, +ant: U32, +cls: U32) -> A.Enc:
  +n = Tr.n(tr)
  +c0 = Tr.cor(tr, 0)
  e = A.enc.k(e, ctx.comp(cls), (n - 1 : U32))
  e = emite.cor(e, c0, ant, ctx.cor(0, cls), ctx.cor(1, cls), ctx.cor(2, cls))
  emite.fim(U32.is_ge(n, Trecho.linear()), e, c0, Tr.cor(tr, 1))

# tr: o trecho aberto; prev: o último pixel ORIGINAL visto na curva; ant/cls:
# cor final e classe do último trecho gravado; nt: trechos gravados
type Cod is Type:
  Cod{cfg: Cfg, img: Array<U32>, e: A.Enc, tr: Tr, prev: U32, ant: U32, cls: U32, nt: U32}

def cod.decide(quebra: Bool, +cfg: Cfg, img: Array<U32>, e: A.Enc, +tr: Tr, +prev: U32, +ant: U32, +cls: U32, +nt: U32, +c: U32) -> Cod:
  match quebra:
    case False{}:
      Cod{cfg, img, e, Tr.estende(tr, prev, c, Cfg.textura(cfg)), c, ant, cls, nt}
    case True{}:
      Cod{cfg, img, emite(e, tr, ant, cls), Tr.novo(c), c, Tr.cor(tr, 1), classe(Tr.n(tr)), (nt + 1 : U32)}

# O primeiro pixel da imagem abre o primeiro trecho
def cod.pixel.vazio(vazio: Bool, +cfg: Cfg, img: Array<U32>, e: A.Enc, +tr: Tr, +prev: U32, +ant: U32, +cls: U32, +nt: U32, +c: U32) -> Cod:
  match vazio:
    case True{}: Cod{cfg, img, e, Tr.novo(c), c, ant, cls, nt}
    case False{}: cod.decide(corta(cfg, tr, prev, c), cfg, img, e, tr, prev, ant, cls, nt, c)

def cod.pixel(r: Array<U32> & U32, +cfg: Cfg, e: A.Enc, +tr: Tr, +prev: U32, +ant: U32, +cls: U32, +nt: U32) -> Cod:
  (img, +c) = r
  cod.pixel.vazio(U32.is_zero(Tr.n(tr)), cfg, img, e, tr, prev, ant, cls, nt, c)

def cod.le(c: Cod, +i: U32) -> Cod:
  Cod{+cfg, img, e, +tr, +prev, +ant, +cls, +nt} = c
  cod.pixel(Array.get(U32, img, i), cfg, e, tr, prev, ant, cls, nt)

def cod.visita(ok: Bool, c: Cod, +i: U32) -> Cod:
  match ok:
    case False{}: c
    case True{}: cod.le(c, i)

def cod(c: Cod, pos: H.Vec2, chegada: H.Dir, dir: H.Dir) -> Cod:
  Cod{+cfg, img, e, tr, prev, ant, cls, nt} = c
  H.Vec2{+x, +y} = pos
  cod.visita(Cfg.dentro(cfg, x, y), Cod{cfg, img, e, tr, prev, ant, cls, nt}, Cfg.indice(cfg, x, y))

# Grava o último trecho; devolve os bytes e quantos trechos foram gravados
def cod.fim(c: Cod) -> (Array<U32> & U32) & U32:
  Cod{cfg, img, e, +tr, prev, +ant, +cls, +nt} = c
  (A.Enc.fim(emite(e, tr, ant, cls)), (nt + 1 : U32))

def cabecalho(a: Array<U32>, +ordem: U32, +salto: U32, +faixa: U32, +textura: U32, +w: U32, +h: U32) -> Array<U32>:
  a = Array.set(U32, a, 0, 72)   # H
  a = Array.set(U32, a, 1, 73)   # I
  a = Array.set(U32, a, 2, 76)   # L
  a = Array.set(U32, a, 3, 52)   # 4
  a = Array.set(U32, a, 4, ordem)
  a = Array.set(U32, a, 5, salto)
  a = Array.set(U32, a, 6, faixa)
  a = Array.set(U32, a, 7, textura)
  a = Arq.set_u32(a, 8, w)
  Arq.set_u32(a, 12, h)

def codifica(img: Bmp.Imagem, +salto: U32, +faixa: U32, +textura: U32, +ordem: U32) -> (Array<U32> & U32) & U32:
  Bmp.Imagem{+w, +h, px} = img
  out = cabecalho([0 : U32^M.log2_ceil(capacidade((w * h : U32)))], ordem, salto, faixa, textura, w, h)
  cod.fim(percorre(~Cod, ~cod, ordem, w, h,
    Cod{Cfg{w, h, salto, faixa, textura}, px, A.Enc.novo(out, Cab.tamanho()), Tr.vazio(), 0, 0, 0, 0}))

# ----------------------------------------------------------------
# DECODIFICADOR
# ----------------------------------------------------------------

# cores inicial e final do trecho atual, tamanho, posição dentro dele, classe
type Dco is Type:
  Dco{cfg: Cfg, img: Array<U32>, d: A.Dec, c0: U32, c1: U32, n: U32, i: U32, cls: U32}

# Interpola um canal entre a e b na posição i de n (sem sinal: a·(n-1-i) + b·i)
def interp.canal(+a: U32, +b: U32, +i: U32, +n: U32) -> U32:
  +m = U32.max((n - 1 : U32), 1)
  ((a * (n - 1 - i) + b * i + m / 2) / m : U32)

def interp(+c0: U32, +c1: U32, +i: U32, +n: U32) -> U32:
  Bool.pick(U32, U32.is_le(n, 1), c0,
    Bmp.rgb(interp.canal(Bmp.vermelho(c0), Bmp.vermelho(c1), i, n), interp.canal(Bmp.verde(c0), Bmp.verde(c1), i, n),
            interp.canal(Bmp.azul(c0), Bmp.azul(c1), i, n)))

# A cor lida como diferença de `ant` (verde primeiro)
def soma_cor(+ant: U32, +kg: U32, +kr: U32, +kb: U32) -> U32:
  Bmp.rgb(U32.and((Bmp.vermelho(ant) + kg + kr : U32), 255), U32.and((Bmp.verde(ant) + kg : U32), 255),
          U32.and((Bmp.azul(ant) + kg + kb : U32), 255))

# --- cor final (só trechos longos) ---
def fim.b(r: A.Dec & U32, +cfg: Cfg, img: Array<U32>, +c0: U32, +n: U32, +kg: U32, +kr: U32) -> Dco:
  (d, +kb) = r
  Dco{cfg, img, d, c0, soma_cor(c0, kg, kr, kb), n, 0, classe(n)}

def fim.r(r: A.Dec & U32, +cfg: Cfg, img: Array<U32>, +c0: U32, +n: U32, +kg: U32) -> Dco:
  (d, +kr) = r
  fim.b(A.dec.k(d, ctx.fim(2)), cfg, img, c0, n, kg, kr)

def fim.g(r: A.Dec & U32, +cfg: Cfg, img: Array<U32>, +c0: U32, +n: U32) -> Dco:
  (d, +kg) = r
  fim.r(A.dec.k(d, ctx.fim(1)), cfg, img, c0, n, kg)

def fim.se(linear: Bool, +cfg: Cfg, img: Array<U32>, d: A.Dec, +c0: U32, +n: U32) -> Dco:
  match linear:
    case False{}: Dco{cfg, img, d, c0, c0, n, 0, classe(n)}
    case True{}: fim.g(A.dec.k(d, ctx.fim(0)), cfg, img, c0, n)

# --- cor inicial ---
def ini.b(r: A.Dec & U32, +cfg: Cfg, img: Array<U32>, +ant: U32, +n: U32, +kg: U32, +kr: U32) -> Dco:
  (d, +kb) = r
  fim.se(U32.is_ge(n, Trecho.linear()), cfg, img, d, soma_cor(ant, kg, kr, kb), n)

def ini.r(r: A.Dec & U32, +cfg: Cfg, img: Array<U32>, +ant: U32, +cls: U32, +n: U32, +kg: U32) -> Dco:
  (d, +kr) = r
  ini.b(A.dec.k(d, ctx.cor(2, cls)), cfg, img, ant, n, kg, kr)

def ini.g(r: A.Dec & U32, +cfg: Cfg, img: Array<U32>, +ant: U32, +cls: U32, +n: U32) -> Dco:
  (d, +kg) = r
  ini.r(A.dec.k(d, ctx.cor(1, cls)), cfg, img, ant, cls, n, kg)

def ini.comp(r: A.Dec & U32, +cfg: Cfg, img: Array<U32>, +ant: U32, +cls: U32) -> Dco:
  (d, +k) = r
  ini.g(A.dec.k(d, ctx.cor(0, cls)), cfg, img, ant, cls, (k + 1 : U32))

# Se o trecho atual acabou, lê o próximo (a cor final dele é a referência)
def carrega.se(acabou: Bool, +cfg: Cfg, img: Array<U32>, d: A.Dec, +c0: U32, +c1: U32, +n: U32, +i: U32, +cls: U32) -> Dco:
  match acabou:
    case False{}: Dco{cfg, img, d, c0, c1, n, i, cls}
    case True{}: ini.comp(A.dec.k(d, ctx.comp(cls)), cfg, img, c1, cls)

def dco.carrega(s: Dco) -> Dco:
  Dco{+cfg, img, d, +c0, +c1, +n, +i, +cls} = s
  carrega.se(U32.is_ge(i, n), cfg, img, d, c0, c1, n, i, cls)

# Pinta o pixel `p` com a cor da posição atual do trecho, marcando se é liso
def pixel(s: Dco, +p: U32) -> Dco:
  Dco{+cfg, img, d, +c0, +c1, +n, +i, +cls} = s
  +cor = U32.or(interp(c0, c1, i, n), Bool.pick(U32, U32.is_ge(n, 3), Liso.bit(), 0))
  Dco{cfg, Array.set(U32, img, p, cor), d, c0, c1, n, (i + 1 : U32), cls}

def dco.visita(ok: Bool, s: Dco, +p: U32) -> Dco:
  match ok:
    case False{}: s
    case True{}: pixel(dco.carrega(s), p)

def dco(s: Dco, pos: H.Vec2, chegada: H.Dir, dir: H.Dir) -> Dco:
  Dco{+cfg, img, d, c0, c1, n, i, cls} = s
  H.Vec2{+x, +y} = pos
  dco.visita(Cfg.dentro(cfg, x, y), Dco{cfg, img, d, c0, c1, n, i, cls}, Cfg.indice(cfg, x, y))

# ----------------------------------------------------------------
# PÓS-FILTRO (só no decodificador)
# ----------------------------------------------------------------
# Média, numa janela de 2·raio+1 pixels numa direção, dos vizinhos que também
# são lisos e têm cor próxima (maior canal <= Filtro.limite()). Detalhe não é
# tocado, e uma borda entre duas regiões lisas não vaza. Duas passadas:
# horizontal (passo 1) e vertical (passo = largura), de um array para outro.

def Filtro.limite() -> U32: 12

def eh_liso(+v: U32) -> Bool: U32.is_ne(U32.and(v, Liso.bit()), 0)

def perto(+a: U32, +b: U32) -> Bool:
  U32.is_le(A.sabs((Bmp.vermelho(a) - Bmp.vermelho(b) : U32)), Filtro.limite()) &&
    U32.is_le(A.sabs((Bmp.verde(a) - Bmp.verde(b) : U32)), Filtro.limite()) &&
    U32.is_le(A.sabs((Bmp.azul(a) - Bmp.azul(b) : U32)), Filtro.limite())

# Um passo da janela: j = 0..2·raio; o vizinho está a (j - raio) passos.
# Parâmetros da passada: p (o pixel), q (coordenada dele no eixo), lim (tamanho
# do eixo), st (passo no array). `r` traz o valor lido para o j atual.
type Soma is Data:
  Soma{r: U32, g: U32, b: U32, n: U32}

def Soma.mais(+s: Soma, +v: U32, +usa: Bool) -> Soma:
  Soma{r, g, b, n} = s
  +k = Bool.to_u32(usa)
  Soma{(r + k * Bmp.vermelho(v) : U32), (g + k * Bmp.verde(v) : U32), (b + k * Bmp.azul(v) : U32), (n + k : U32)}

def Soma.cor(+s: Soma) -> U32:
  Soma{+r, +g, +b, +n} = s
  U32.or(Bmp.rgb(((r + n / 2) / n : U32), ((g + n / 2) / n : U32), ((b + n / 2) / n : U32)), Liso.bit())

# índice do vizinho a (j - raio) passos, ou o próprio p se cair fora do eixo
def viz(+p: U32, +q: U32, +lim: U32, +st: U32, +j: U32, +raio: U32) -> U32:
  +o = (j - raio : U32)
  Bool.pick(U32, U32.is_lt((q + o : U32), lim), (p + o * st : U32), p)

def dentro_eixo(+q: U32, +lim: U32, +j: U32, +raio: U32) -> Bool:
  U32.is_lt((q + j - raio : U32), lim)

def janela(k: Nat, r: Array<U32> & U32, +centro: U32, +p: U32, +q: U32, +lim: U32, +st: U32, +raio: U32, +j: U32, +s: Soma) -> Array<U32> & U32:
  match k:
    case 0n:
      (src, +v) = r
      (src, Soma.cor(Soma.mais(s, v, dentro_eixo(q, lim, j, raio) && eh_liso(v) && perto(v, centro))))
    case 1n+t:
      (src, +v) = r
      +s2 = Soma.mais(s, v, dentro_eixo(q, lim, j, raio) && eh_liso(v) && perto(v, centro))
      +j2 = (j + 1 : U32)
      janela(t, Array.get(U32, src, viz(p, q, lim, st, j2, raio)), centro, p, q, lim, st, raio, j2, s2)

# A cor filtrada do pixel p (ou ele mesmo, se não for liso)
def filtra.px.c(liso: Bool, src: Array<U32>, +centro: U32, +p: U32, +q: U32, +lim: U32, +st: U32, +raio: U32) -> Array<U32> & U32:
  match liso:
    case False{}: (src, centro)
    case True{}: janela(U32.to_nat((2 * raio : U32)), Array.get(U32, src, viz(p, q, lim, st, 0, raio)), centro, p, q, lim, st, raio, 0, Soma{0, 0, 0, 0})

def filtra.px.le(r: Array<U32> & U32, +p: U32, +q: U32, +lim: U32, +st: U32, +raio: U32) -> Array<U32> & U32:
  (src, +centro) = r
  filtra.px.c(eh_liso(centro), src, centro, p, q, lim, st, raio)

# vert = 0: horizontal (eixo x, passo 1); vert = 1: vertical (eixo y, passo w)
def filtra.px(src: Array<U32>, +p: U32, +w: U32, +h: U32, +vert: U32, +raio: U32) -> Array<U32> & U32:
  +q = Bool.pick(U32, U32.is_zero(vert), (p % w : U32), (p / w : U32))
  +lim = Bool.pick(U32, U32.is_zero(vert), w, h)
  +st = Bool.pick(U32, U32.is_zero(vert), 1, w)
  filtra.px.le(Array.get(U32, src, p), p, q, lim, st, raio)

# Uma passada: `r` traz (src, cor filtrada do pixel p); grava em dst e segue
def passada(k: Nat, r: Array<U32> & U32, dst: Array<U32>, +p: U32, +w: U32, +h: U32, +vert: U32, +raio: U32) -> Array<U32> & Array<U32>:
  match k:
    case 0n:
      (src, +cor) = r
      (src, Array.set(U32, dst, p, cor))
    case 1n+t:
      (src, +cor) = r
      +p2 = (p + 1 : U32)
      passada(t, filtra.px(src, p2, w, h, vert, raio), Array.set(U32, dst, p, cor), p2, w, h, vert, raio)

def passada.ini(src: Array<U32>, dst: Array<U32>, +w: U32, +h: U32, +vert: U32, +raio: U32) -> Array<U32> & Array<U32>:
  passada(U32.to_nat((w * h - 1 : U32)), filtra.px(src, 0, w, h, vert, raio), dst, 0, w, h, vert, raio)

def filtro.fim(r: Array<U32> & Array<U32>) -> Array<U32>:
  (b, a) = r
  a

# horizontal de A para B, vertical de B de volta para A
def filtro.v(r: Array<U32> & Array<U32>, +w: U32, +h: U32, +raio: U32) -> Array<U32>:
  (a, b) = r
  filtro.fim(passada.ini(b, a, w, h, 1, raio))

def filtro(+raio: U32, img: Array<U32>, +w: U32, +h: U32) -> Array<U32>:
  match raio:
    case 0: img
    case _: filtro.v(passada.ini(img, [0 : U32^M.log2_ceil((w * h : U32))], w, h, 0, raio), w, h, raio)

def dco.fim(s: Dco, +raio: U32) -> Bmp.Imagem:
  Dco{+cfg, img, d, c0, c1, n, i, cls} = s
  Cfg{+w, +h, sl, f, t} = cfg
  Bmp.Imagem{w, h, filtro(raio, img, w, h)}

def decodifica.imagem(inp: Array<U32>, +hd: List<&2, U32>, +raio: U32) -> Bmp.Imagem:
  +w = Arq.u32(hd, 8n)
  +h = Arq.u32(hd, 12n)
  dco.fim(percorre(~Dco, ~dco, Arq.byte(hd, 4n), w, h,
    Dco{Cfg{w, h, 0, 0, 0}, [0 : U32^M.log2_ceil((w * h : U32))], A.Dec.novo(inp, Cab.tamanho()), 0, 0, 0, 0, 0}), raio)

def decodifica.valida(ok: Bool, inp: Array<U32>, +hd: List<&2, U32>, +raio: U32) -> IO(Bmp.Imagem):
  match ok:
    case True{}: IO.pure(Bmp.Imagem, decodifica.imagem(inp, hd, raio))
    case False{}: IO.die(Bmp.Imagem, 1, "não é um arquivo HIL4")

def decodifica.cab(r: Array<U32> & List<&2, U32>, +raio: U32) -> IO(Bmp.Imagem):
  (inp, +hd) = r
  decodifica.valida(
    U32.is_eq(Arq.byte(hd, 0n), 72) && U32.is_eq(Arq.byte(hd, 1n), 73) &&
      U32.is_eq(Arq.byte(hd, 2n), 76) && U32.is_eq(Arq.byte(hd, 3n), 52),
    inp, hd, raio)

def decodifica(r: Array<U32> & U32, +raio: U32) -> IO(Bmp.Imagem):
  (inp, n) = r
  decodifica.cab(Arq.array_para_lista(inp, 0, Cab.tamanho()), raio)

# ----------------------------------------------------------------
# PROGRAMA
# ----------------------------------------------------------------

# Em milésimos, sem estourar o U32: `parte * 1000` passa de 2^32 quando parte
# passa de ~4M, então imagens grandes dividem por `todo / 1000`.
def permil(pequeno: Bool, +parte: U32, +todo: U32) -> U32:
  match pequeno:
    case True{}: ((parte * 1000 + todo / 2) / todo : U32)
    case False{}: ((parte + todo / 2000) / (todo / 1000) : U32)

def porcento(+parte: U32, +todo: U32) -> String:
  +pm = permil(U32.is_lt(todo, 3000000), parte, todo)
  U32.show((pm / 10 : U32)) ++ "," ++ U32.show((pm % 10 : U32)) ++ "%"

# média com uma casa decimal
def por_trecho(+np: U32, +nt: U32) -> String:
  +d = (np * 10 / nt : U32)
  U32.show((d / 10 : U32)) ++ "," ++ U32.show((d % 10 : U32))

def grava.cabe(ok: Bool, out: Array<U32>, destino: String, +n: U32, +nt: U32, +w: U32, +h: U32) -> IO(Unit):
  match ok:
    case False{}: IO.die(Unit, 1, "saída maior que a capacidade reservada")
    case True{}:
      +bruto = (w * h * 3 : U32)
      do IO<Unit>:
        Arq.gravar_bytes(destino, out, n)
        IO.print(U32.show(w) ++ "x" ++ U32.show(h) ++ ": " ++ U32.show(bruto) ++ " bytes de pixels -> " ++
          U32.show(n) ++ " bytes (" ++ porcento(n, bruto) ++ "), " ++ U32.show(nt) ++ " trechos, " ++
          por_trecho((w * h : U32), nt) ++ " pixels por trecho")

def grava.par(r: Array<U32> & U32, +nt: U32, destino: String, +w: U32, +h: U32) -> IO(Unit):
  (out, +n) = r
  grava.cabe(U32.is_le(n, capacidade((w * h : U32))), out, destino, n, nt, w, h)

def grava(r: (Array<U32> & U32) & U32, destino: String, +w: U32, +h: U32) -> IO(Unit):
  (bytes, +nt) = r
  grava.par(bytes, nt, destino, w, h)

def cmd.codifica(img: Bmp.Imagem, destino: String, +salto: U32, +faixa: U32, +textura: U32, +ordem: U32) -> IO(Unit):
  Bmp.Imagem{+w, +h, px} = img
  grava(codifica(Bmp.Imagem{w, h, px}, salto, faixa, textura, ordem), destino, w, h)

def cmd.codifica_args(+ts: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    img : Bmp.Imagem <- Bmp.ler(IOU.text_at(ts, 1n, "entrada.bmp"))
    cmd.codifica(img, IOU.text_at(ts, 2n, "saida.hil4"),
      U32.min(IOU.text_num_at(ts, 3n, 24), 255),     # salto
      U32.min(IOU.text_num_at(ts, 4n, 48), 255),     # faixa
      U32.min(IOU.text_num_at(ts, 5n, 6), 255),      # textura
      IOU.text_num_at(ts, 6n, 0))                    # ordem

def cmd.decodifica_args(+ts: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    r : Array<U32> & U32 <- Arq.ler_bytes(IOU.text_at(ts, 1n, "entrada.hil4"))
    img : Bmp.Imagem <- decodifica(r, U32.min(IOU.text_num_at(ts, 3n, 2), 16))
    Bmp.gravar(IOU.text_at(ts, 2n, "saida.bmp"), img)

def cmd(modo: String, +ts: List<&2, String>) -> IO(Unit):
  match modo:
    case "codifica": cmd.codifica_args(ts)
    case "decodifica": cmd.decodifica_args(ts)
    case _:
      IO.print("uso: hilbert_detalhe codifica entrada.bmp saida.hil4 [salto=24] [faixa=48] [textura=6] [ordem=0 hilbert|1 linhas]\n" ++
               "     hilbert_detalhe decodifica entrada.hil4 saida.bmp [raio=2]\n" ++
               "     (textura=0 desliga o corte por textura; raio=0 desliga o pós-filtro)")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +ts : List<&2, String> = IOU.texts(args)
    cmd(IOU.text_at(ts, 0n, ""), ts)
