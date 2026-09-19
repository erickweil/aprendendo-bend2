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
  - Verificação de provas e teoremas: `timeout 60s bend PROOF.bend` (o `--checkup` falha nesse par, veja a seção 4).
  - Inspeção do código gerado: `timeout 60s bend <arquivo.bend> -o saida.c` (emite o fonte C sem compilar).

---

## 2. As Armadilhas Críticas da Linguagem Bend 2

Compreender estas armadilhas é fundamental para programar em Bend 2 sem travar o compilador ou estourar a memória da VM:

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

### 🔴 Armadilha 3: Acesso Indexado em Laço Quente (e o que NÃO é problema)
> **Conceito:** A HVM não possui coletor de lixo convencional baseado em tracing; ela opera por aniquilação e duplicação de nós em grafos de interação. Isso gera um medo justificado de estruturas encadeadas — mas o medo precisa mirar no alvo certo.

* **O que MEDIMOS que não é problema:** uma `List<&2, U32>` como genoma, duplicada a cada geração.
  - 1024 indivíduos × 400 gerações × genoma de 64 genes (26 milhões de cruzamentos de gene): **1,3 s e 4,2 MB** de residente no binário nativo.
  - A duplicação `+` de uma lista é preguiçosa: os nós `dup` só se dividem conforme são consumidos. Passar `+champ_g` para a população inteira, ou `+pop` para sortear pais por torneio, **não explode**.
* **O que É problema:** `List.get(&2, T, list, U32.to_nat(idx))` dentro do laço de aptidão.
  - `U32.to_nat(20)` aloca 20 nós de Peano para CADA leitura, e `List.get` ainda percorre a lista.
  - 60 slots × 32 indivíduos × 400 gerações = dezenas de milhões de alocações que não deveriam existir.
* **A Solução:**
  - Escreva os operadores como **varreduras estruturais** dos genomas (é assim que crossover e mutação são definidos de qualquer forma), não como laços de índice.
  - Quando precisar mesmo de índice, indexe com `U32` e recursão sobre a própria lista (veja `genetic/utils/genes.bend`): nenhum `Nat` é alocado.
  - Reserve `Nat` para contadores de laço que o verificador de terminação exige, e prefira que eles venham como literal do problema (`12n`), não de `U32.to_nat`.

---

### 🔴 Armadilha 3b: `Array<T>` é `Type`, não `Data`
> **Conceito:** Bend 2 tem `Array<T>` com escrita in-place em O(1), mas ele é um `Type`: tem exatamente um dono a qualquer momento.

* **A consequência:** um `Array` **não pode** receber `+`, nem ser campo de um tipo `Data`, nem morar dentro de uma estrutura polimórfica sobre `Data`:
  ```bend
  type Box<-G: Data> is Data:
    Box{g: G}

  b = {Box{[0 : U32*4n]} : Box<Array<U32>>}  # ❌ "expected: Data, observed: Type"
  ```
* **Quando isso morde:** qualquer estado que precise ser clonado — genomas de um algoritmo genético, nós de uma busca com backtracking, snapshots. `Array.clone` existe, mas devolve duas arrays soltas, não resolve a restrição de kind.
* **A Solução:** para dados duplicáveis use `List<&2, A>` ou uma árvore `Data` própria. Reserve `Array` para buffers de dono único dentro de uma função.

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

  def is_positive(+x: U32) -> String:
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

### 🔴 Armadilha 7: Restrições dos Parâmetros Template `~`
> **Conceito:** Um parâmetro `~f` é substituído em tempo de compilação, o que dá abstração de custo zero — mas o preço é que ele não é um valor de primeira classe.

* **Templates vêm ANTES de tudo na assinatura.** Se um `-A: Data` (ou qualquer outro parâmetro) aparecer antes, passar o template numa chamada recursiva falha com `expected: a term, observed: '~'`:
  ```bend
  def cross.go(-A: Data, ~pred: U32 -> Bool, ...)   # ❌ quebra na chamada recursiva
  def cross.go(~pred: U32 -> Bool, -A: Data, ...)   # ✔️
  ```
* **Um `~` não pode aninhar dentro de outro `~`.** Não existe forma de compor templates:
  ```bend
  breed_tree_eval(~G, ~(p => c => s => f(p, c, s)), ...)   # ❌ expected: a term
  breed_tree_eval(~G, ~eval_child(~G, ~repro, ~fit), ...)  # ❌ expected: a term
  ```
  Consequência prática: duas funções que só diferem no tipo de retorno do template (`G` vs `Ind<G>`) **não podem** ser unificadas numa só — têm de ser escritas em duplicata.
* **O template exige a assinatura exata, inclusive quantidades.** Uma função com `+` nos parâmetros não serve para um template declarado sem `+`:
  ```bend
  def popcount(+x: U32) -> U32: ...
  # ~fit: U32 -> U32   ❌ expected @_:U32 -> U32, observed @+x:U32 -> U32
  def fit(g: U32) -> U32: popcount(g)   # ✔️ envolva antes de passar
  ```

---

### 🔴 Armadilha 8: O que o `match` múltiplo não deixa fazer
> **Conceito:** `match a b:` escrutina vários valores de uma vez, mas é rígido.

* **Não existe caso coringa.** Todas as combinações têm de ser escritas — três listas viram oito casos. `case outro:` é rejeitado com `expected: N patterns (one per scrutinee)`.
* **Não se aninha `match` sobre um campo ligado por um `match` múltiplo:**
  ```bend
  match l hit:
    case Con{h, t} True{}:
      match t:              # ❌ "this name is a def or a consumed binder"
  ```
  E o auxiliar óbvio (`def f.pair(t) -> ...` que volta a chamar `f`) esbarra na falta de recursão mútua. **A saída** é um auxiliar **não recursivo** aplicado ao resultado que a recursão já produziu:
  ```bend
  # Em vez de abrir a cauda antes de recursar, recursa primeiro e conserta depois
  def push_after_head(-A: Data, h: A, l: List<&2, A>) -> List<&2, A>:
    match l:
      case Nil{}: Con{h, Nil{}}
      case Con{h2, rest}: Con{h2, Con{h, rest}}
  ```
* **`do` é palavra reservada** (do bloco `do IO<T>:`) e não pode ser nome de parâmetro.

---

### 🔴 Armadilha 9: `split.fst` é literalmente `step`
> **Conceito:** Em `utils/random.bend`, `split.fst(seed)` é definido como `step(seed)` — são a mesma função.

* **O Erro:** usar `R.step(seed)` para avançar a semente de uma iteração cujo corpo já bifurca com `split.fst`/`split.snd`:
  ```bend
  +next_seed = R.step(seed)                     # ❌ == split.fst(seed)
  breed_tree(..., seed, ...)                    #    o ramo esquerdo recebe split.fst(seed)
  ```
  A iteração seguinte reusa exatamente a sub-árvore de sementes do ramo esquerdo da anterior: metade do fluxo aleatório é reciclada a cada passo, silenciosamente.
* **A Solução:** avance o laço externo por um caminho que os ramos não usam — `R.split.trd` / `R.split.fth` existem exatamente para isso.

---

## 3. Estrutura do Código no Repositório

```text
aprendendo-bend2/
├── AGENTS.md                  # Este guia
├── README.md                  # Visão geral e introdução ao Bend 2
├── GUIDE.md                   # Gerado por `bend guide` (regenere ao atualizar o bend)
├── bin/                       # Binários compilados (ignorado pelo git)
├── exemplos/                  # Exemplos de código em Bend 2 para aprendizado
├── utils/                     # Helpers gerais: random, math, vec4, io, json
└── genetic/                   # Motor genético (veja genetic/README.md)
    ├── ga.bend                # Motor polimórfico: população, elitismo, torneio
    ├── operators.bend         # Operadores para genoma U32
    ├── stats.bend             # Estatísticas de população
    ├── LAWS.bend / PROOF.bend # Leis formais e suas provas
    ├── utils/                 # poptree, bits, genes
    └── exemplos/              # onemax, sorting, tsp
```


---

## 4. Checklist de Verificação Antes de Enviar Commits

```bash
# 1. Verificar provas formais (Não permita a utilização de @unsafe pois são ignorados pelo verificador)
timeout 60s bend nome-do-arquivo.bend --checkup
# ATENÇÃO ao par LAWS.bend / PROOF.bend: `LAWS.bend` sozinho SEMPRE reporta
# TODOs (é só o enunciado), então `--checkup` falha nele — ele checa cada
# import isoladamente. Para esse par, verifique `bend PROOF.bend` direto.

# 2. Executar testes caso existam
timeout 60s bend nome-do-arquivo_test.bend

# 3. Verificar se a compilação nativa funciona sem erros
timeout 60s bend nome-do-arquivo.bend -o ./bin/nome-do-arquivo

# 4. Commit e Push imediato (na branch de feature, nunca na main e nunca faça merge)
git commit -am "tipo(escopo): mensagem descritiva"
git push origin feature/nome-da-feature
```
