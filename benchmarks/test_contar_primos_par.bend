import Base

def eh_div(n: U32, d: U32) -> Bool:
  U32.is_zero((n % d : U32))

def eh_primo_loop(+fuel: Nat, +i: U32, +n: U32) -> Bool:
  match fuel:
    case 0n:
      True{}
    case 1n+p:
      Bool.pick(Bool, (i > n / i : U32),
        True{},
        Bool.pick(Bool, eh_div(n, i),
          False{},
          eh_primo_loop(p, (i + 2 : U32), n)))

def eh_primo(+n: U32) -> Bool:
  Bool.pick(Bool, U32.is_le(n, 1),
    False{},
    Bool.pick(Bool, U32.is_eq(n, 2),
      True{},
      Bool.pick(Bool, eh_div(n, 2),
        False{},
        eh_primo_loop(U32.to_nat(n), 3, n))))

# Conta quantos primos há em [ini, fim] sequencialmente
def contar_seq(+fuel: Nat, +ini: U32, +fim: U32, +acc: U32) -> U32:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      Bool.pick(U32, (ini > fim : U32),
        acc,
        contar_seq(p, (ini + 1 : U32), fim, (acc + Bool.pick(U32, eh_primo(ini), 1, 0) : U32)))

# Conta primos em [ini, fim] em árvore paralela de profundidade d
def contar_par(+d: Nat, +ini: U32, +fim: U32) -> U32:
  match d:
    case 0n:
      contar_seq(U32.to_nat((fim - ini + 1 : U32)), ini, fim, 0)
    case 1n+p:
      +meio = ((ini + fim) / 2 : U32)
      esq dir = contar_par(p, ini, meio) contar_par(p, (meio + 1 : U32), fim)
      (esq + dir : U32)

def limite() -> U32:
  30000

def main() -> IO(Unit):
  # Divide o intervalo [2, 30000] em 2^6 = 64 subintervalos paralelos
  total = contar_par(6n, 2, limite())
  IO.print("Primos até " ++ U32.show(limite()) ++ ": " ++ U32.show(total))
