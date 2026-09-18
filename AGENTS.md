# AGENTS.md — Guia de Engenharia e Operação em Bend 2

## 1. Como Orquestrar a Execução do Bend 2 com Segurança

O Bend 2 é construído sobre a HVM — High-order Virtual Machine, o runtime reduz redes de interação (*interaction combinators*) de forma preguiçosa e paralela. Se o código for mal projetado, ele pode entrar em ciclos de reescrita infinita ou expansão exponencial de nós de duplicação (`dup`), **consumindo 100% de CPU em todos os núcleos e gerando Out-Of-Memory (OOM)** que pode levar o kernel Linux a matar o processo.

Para aprender sobre o BEND2, leia o GUIDE.md gerado pelo comando `bend guide > GUIDE.md`. Ele contém exemplos de código, explicações sobre a linguagem e boas práticas de programação. Veja os exemplos deste projeto ou então explore o repositório oficial da linguagem bend https://github.com/bendlang/bend que possui vários demos e documentação além de todo o código da linguagem em si (Verifique se já não está clonado no worktree)

### 1.1 Comandos de Execução Segura

* **Sempre utilize `timeout`:** Nunca execute `bend` diretamente sem um limite de tempo.
  ```bash
  timeout 60s bend <arquivo.bend>
  ```
* **Controle de Threads na Compilação C:**
  Para cargas maiores de tabalho, priorize rodar o Bend compilado para nativo via `-o`:
  ```bash
  timeout 60s bend arquivo.bend -o ./bin/arquivo
  timeout 60s ./bin/arquivo --threads 1     # Single core
  timeout 60s ./bin/arquivo --threads 4     # Multi core
  ```
* **Compilação e Verificação Estática:**
  - Verificação de provas e teoremas: `timeout 60s bend <arquivo.bend> --checkup` ou `bend PROOF.bend`.
  - Inspeção do código gerado: `timeout 60s bend <arquivo.bend> -o saida.c` (emite o fonte C sem compilar).

---

## 2. As Armadilhas Críticas da Linguagem Bend 2

Compreender estas 6 armadilhas é fundamental para programar em Bend 2 sem travar o compilador ou estourar a memória da VM:

### 🔴 Armadilha 1: Closures são Afins (*Affine Closures*)
> **Conceito:** Em Bend 2, uma função anônima que captura variáveis do escopo (`x => f(x, capturado)`) é **afim** (*affine*): ela só pode ser chamada **no máximo uma vez**.

* **O Erro:** Passar uma closure com estado capturado para uma função que repete chamadas (como um loop genético `run_generations`, um fold ou map). O compilador rejeitará com erro de afinidade ou travará em tempo de compilação.
* **A Solução:**
  1. Use apenas definições de topo (*top-level definitions*) como funções de ordem superior.
  2. Passe os dados capturados explicitamente como parte do genoma/indivíduo (`Cand`), ou empacote parâmetros em registros puros unboxed.

---

### 🔴 Armadilha 2: `Bool.pick` é Estrito (*Strict Evaluation*)
> **Conceito:** Na HVM, `Bool.pick(T, cond, then_branch, else_branch)` avalia **ambos os ramos** incondicionalmente. (No interpretador é lazy, mas no compilado nativo sim.)

* **Quando isso é aceitável:** se o ramo recursivo for uma recursão **estrutural sobre um argumento que encolhe**, o `Bool.pick` termina — ele apenas deixa de fazer short-circuit e paga o custo da lista inteira:
  ```bend
  def list_contains_str(l: List<&2, J.Json>, +target: String) -> Bool:
    match l:
      case Nil{}: False{}
      case h <> t:
        Bool.pick(Bool, json_is_target_str(h, target), True{}, list_contains_str(t, target))
  ```
* **Quando é fatal:** quando o ramo não tomado tem custo ilimitado ou exponencial — recursão que não encolhe, expansão de árvore, ou um `Bool.pick` aninhado dentro de um laço quente. Aí a HVM avalia trabalho que seria descartado e a memória explode.

* **Como obter short-circuit de verdade.** É preciso que o `match` recaia sobre um **parâmetro**, e o Bend 2 impõe três restrições simultâneas que eliminam quase todas as alternativas óbvias:

  1. **Não existe recursão mútua.** `f.step` não pode chamar `f` — o compilador responde `expected: a defined name`.
  2. **`match` não escrutina binder local.** `+c = U32.is_eq(...)` seguido de `match c:` é rejeitado com *"a match cannot scrutinize a local binder: give it its own def"*.
  3. **Escrutínio segue a ordem dos binders** e o verificador de terminação **lê os argumentos da esquerda para a direita**, exigindo que um deles encolha antes que qualquer outro mude.

  O padrão que satisfaz as três é o **acumulador de condição com escrutínio múltiplo**, com o argumento que encolhe **primeiro** na lista de parâmetros:

  ```bend
  # ✔️ CORRETO e verificado: recursão direta, match sobre parâmetros,
  #    `l` (que encolhe) antes de `is_match` (que muda).
  def find.go(l: List<&2, U32>, is_match: Bool, +target: U32) -> U32:
    match l is_match:
      case Nil{} True{}: 1
      case Nil{} False{}: 0
      case Con{h, t} True{}: 1                                  # para aqui: sem recursão
      case Con{h, t} False{}: find.go(t, U32.is_eq(h, target), target)

  def find(l: List<&2, U32>, +target: U32) -> U32:
    find.go(l, False{}, target)
  ```
  A condição do passo **anterior** entra como parâmetro, então o ramo `True{}` retorna sem nunca mencionar a chamada recursiva. Note `Con{h, t}` em vez de `h <> t`: o açúcar `<>` não é aceito em `match` com múltiplos escrutinados.

* **Alternativa mais simples:** quando o resultado é uma lista de mensagens ou um acumulador, dispense o branch — use um auxiliar **não recursivo** que devolve `Nil{}` ou um singleton e concatene com a recursão direta.

*(Nota: `Bool.pick` entre números primitivos escalares `U32` é seguro e extremamente rápido, funcionando como um `cmov` em hardware).*

* **Closures só executam quando chamadas:** é possível desenvolver um 'or_else' do rust por passar closures `x => ...` para cada ramo, porém isso não é 0-cost, exige um custo de indireção, (lembrando que para poder passar closure assim que captura estado ela só pode ser chamada uma vez)

---

### 🔴 Armadilha 3: Explosão de Nós DUP em Redes de Interação (Causa de OOM)
> **Conceito:** A HVM não possui coletor de lixo convencional baseado em tracing; ela opera por aniquilação e duplicação de nós em grafos de interação.

* **O Erro:** Colocar estruturas de dados baseadas em ponteiros (como `List<&2, String>`, `List<&2, U32>`, ou árvores profundas) dentro de tipos que sofrem clonagem repetida (como genomas ou indivíduos dentro de um loop de 400 gerações).
  - Cada crossover, mutação ou seleção de elite duplica a lista encadeada inteira, gerando árvores exponenciais de nós `dup`.
  - A RAM é consumida rapidamente em poucos segundos até acionar o OOM Killer.
* **A Solução:**
  - O **genoma quente** de um algoritmo genético deve conter **exclusivamente números primitivos unboxed** (`U32`) agrupados em structs planas.
  - Metadados, strings e nomes devem residir fora do loop evolutivo, sendo consumidos na entrada (parsing) e na saída (serialização).
---

### 🔴 Armadilha 4: O Custo Oculto de `Nat` e `U32.to_nat`
> **Conceito:** Em Bend 2, `Nat` é um número de Peano indutivo (`0n`, `1n+p`).

* **O Erro:** Chamar `List.get(&2, T, list, U32.to_nat(idx))` repetidamente dentro de um loop quente de fitness.
  - `U32.to_nat(20)` aloca 20 nós de Peano na memória para CADA leitura.
  - Multiplicado por 60 slots $\times$ 32 indivíduos $\times$ 400 gerações = dezenas de milhões de alocações desnecessárias.
* **A Solução:** Use vetores/tabelas planas com acesso bitwise $O(1)$ nativo em `U32`.

---

### 🔴 Armadilha 5: Restrições de Scrutinee no `match`
> **Conceito:** Em Bend 2, a instrução `match` só pode analisar diretamente **parâmetros de função ou campos desestruturados**.

* **O Erro:**
  ```bend
  match U32.is_gt(x, 0): # ❌ Erro: match cannot scrutinize a computed value
  ```
* **A Solução:** Passe a expressão computada para uma função `.step`:
  ```bend
  def is_positive.step(cond: Bool, x: U32) -> String:
    match cond:
      case True{}: "Positivo"
      case False{}: "Zero ou Negativo"

  def is_positive(x: U32) -> String:
    is_positive.step(U32.is_gt(x, 0), x)
  ```
* **Duas restrições que acompanham esta:**
  - O auxiliar `.step` **não pode chamar de volta** a função que o invocou: Bend 2 não tem recursão mútua. Para casos recursivos, use o padrão da Armadilha 2.
  - `match` também **não aceita binder local**: `+c = f(x)` seguido de `match c:` falha com *"a match cannot scrutinize a local binder: give it its own def"*.

A solução geralmente está em usar Bool.pick ou criar funções auxiliares que retornam o atributo desejado.


### 🔴 Armadilha 6: Inferência de Tipos em Construtores
> **Conceito:** O sistema de tipos bidirecional do Bend 2 exige contexto de tipo para construtores ADT.

* **O Erro:**
  ```bend
  +cand = CD{q, spec}   # ❌ Erro: "expected: an annotated term (cannot infer)"
  ```
* **A Solução:** Crie pequenas funções construtoras com anotação explícita de retorno:
  ```bend
  def make_cand(q: Quadro3, spec: FastSpec) -> Cand:
    CD{q, spec}

  +cand = make_cand(q, spec)  # ✔️ O compilador infere perfeitamente
  ```
* **Literais exigem anotação com chaves `{}`:**
  ```bend
  x = 1            # ❌ "expected: an annotated term (cannot infer)"
  x = (1 : U32)    # ❌ anotação com parênteses NÃO resolve para binder +
  x = {1 : U32}    # ✔️ CORRETO: sintaxe de anotação com chaves!
  n = {1n : Nat}   # ✔️ CORRETO: funciona para Nat também
  ```
  Anotação com chaves `{valor : Tipo}` é a sintaxe exata reconhecida pelo verificador bidirecional para binders. Alternativamente, em posições de argumento ou dentro de funções nulárias tipadas (`def one() -> U32: 1`), o tipo é inferido normalmente.

* **Marcadores `+` diretos nos padrões de `match`:**
  Em desestruturações de `match`, você pode colocar o quantificador `+` diretamente nos binders do padrão, tornando-os reutilizáveis imediatamente e dispensando o antigo padrão de re-ligação local (`+var = var`):
  ```bend
  # ✔️ Padrão moderno com + no próprio match:
  match n:
    case 0n: 0n
    case 1n+ +p: p + p

  match lista:
    case Nil{}: Nil{}
    case Con{h, +t}: Con{h, t}   # t é duplicável diretamente

  match shape:
    case Circle{+r}: (3 * r * r : U32)
  ```

---

## 4. Estrutura do Código no Repositório

```text
aprendendo-bend2/
├── AGENTS.md                  # Este guia
├── README.md                  # Visão geral e introdução ao Bend 2
├── exemplos/                  # Exemplos de código em Bend 2 para aprendizado
├── genetic/                   # Projeto do solver genético
├── utils/                     # Funções utilitárias e helpers
```

---

## 5. Checklist de Verificação Antes de Enviar Commits

```bash
# 1. Verificar provas formais (Não permita a utilização de @unsafe pois são ignorados pelo verificador)
timeout 60s bend nome-do-arquivo.bend --checkup

# 2. Executar testes caso existam
timeout 60s bend nome-do-arquivo_test.bend

# 3. Verificar se a compilação nativa funciona sem erros
timeout 60s bend nome-do-arquivo.bend -o ./bin/nome-do-arquivo

# 4. Commit e Push imediato (na branch de feature, nunca na main e nunca faça merge)
git commit -am "tipo(escopo): mensagem descritiva"
git push origin feature/nome-da-feature
```
