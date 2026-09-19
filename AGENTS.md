# AGENTS.md — Guia de Engenharia e Operação em Bend 2

> Verificado contra o **bend 2.0.16**. Ao atualizar o bend, regenere o GUIDE.md e reverifique as armadilhas com sondas curtas compiladas para nativo.

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
* **Performance só se mede no NATIVO.** O interpretador (`bend arquivo.bend`) não é um nativo mais lento: ele tem um comportamento fundamentalmente diferente (ex.: `Bool.pick` é preguiçoso nele e estrito no nativo). Nenhum argumento de performance vale se não vier de um binário `-o`. E há erros que **só o backend nativo acusa** (ex.: "an open Array element type") — compile também o que só foi checado.
* **Ao medir código paralelo, varie as threads** (`--threads 1 2 4 8 12`) e compare com o teto real da máquina: um benchmark de tarefas **idênticas e independentes** com trabalho contínuo de CPU (neste i5-1245U de 15 W: 8 tarefas escalam só 1,7×, 64 tarefas 2,6×, nada melhora além de 4 threads). O `pow2` do GUIDE, com tarefas minúsculas, dá 3,2× e é uma referência otimista. Um platô antes do número de tarefas independentes indica parte sequencial ou desbalanceamento; um platô que piora conforme o volume de dados cresce indica limite de banda de memória.
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

*(Nota: `Bool.pick` entre escalares é seguro, mas o `bend guide shaders` do 2.0.16 avisa que o `Bool.pick` genérico **encaixota** as palavras, e sobre árvores faz o valor ser compartilhado (contagens de referência). Prefira seletores tipados escritos com `match`, como `def word(c: Bool, a: U32, b: U32) -> U32`. E ao testar a estritez, use uma condição de runtime: com `True{}` literal o compilador dobra o `Bool.pick` e o ramo pesado some.)*

* **Closures só executam quando chamadas:** é possível desenvolver um 'or_else' do rust por passar closures `x => ...` para cada ramo, porém isso não é 0-cost, exige um custo de indireção, (lembrando que para poder passar closure assim que captura estado ela só pode ser chamada uma vez)

---

### 🔴 Armadilha 3: Paralelismo Só Existe Onde Você Escreve
> **Conceito:** O Bend não paraleliza sozinho. O único primitivo de paralelismo é a **chamada paralela** `a b = f(x) g(y)`, e o escalonador é fork-join binário: cada tarefa vai para um núcleo uma vez e nunca é movida.

* **O Erro:** escrever a recursão sobre uma árvore em duas linhas.
  ```bend
  gl = breed(left)           # ❌ sequencial: roda tudo num núcleo só
  gr = breed(right)
  gl gr = breed(left) breed(right)   # ✔️ duas tarefas independentes
  ```
  Medido no motor genético: com as duas linhas, 12 threads rodavam na mesma velocidade que 1.
* **Tarefas que compartilham uma estrutura grande não escalam.** Seleção por torneio sobre a população inteira faz toda tarefa segurar uma cópia `+pop` da geração anterior; ela só é liberada quando a última tarefa termina, e por uma thread só. Medido: 1,0× com 12 threads. O mesmo torneio **dentro de ilhas** independentes (`run_archipelago_tourney`) escala 2,8× — perto do teto da máquina.
* **Um valor `+` lido por todas as tarefas custa um atômico por leitura** (GUIDE, desde o 2.0.16). Contexto, configuração e população compartilhados entre tarefas pagam isso. O `bend guide shaders` recomenda passar constantes como argumento template `~` (uma def como `Tela.w()`), não como parâmetro: "um parâmetro viaja em toda tarefa".
* **Balanceie.** O fork-join não rouba trabalho: se um lado termina antes, aquele núcleo fica ocioso. Numa CPU híbrida (núcleos P + E) a tarefa mais lenta dita o tempo. E nunca haverá mais tarefas pesadas simultâneas do que folhas na árvore de chamadas paralelas (8 ilhas ⇒ platô em 8 threads).
* **Passadas sequenciais contam (Amdahl).** O `diversity_check` do motor é uma passada sequencial por ilha: com uma ilha só, 12 threads não ganham nada. Com várias ilhas, cada passada roda na tarefa da sua ilha.
* **Volume de dados limita.** O mesmo GA, mesma forma, mesmo trabalho total: 3,16× com genomas de 10 mil genes (cabem em cache), 1,45× com 1 milhão (500 MB, limitado por banda de memória).
* **Quando os dados vivos passam da cache, o custo por iteração CRESCE com o tempo.** O alocador nativo reaproveita os nós liberados numa pilha LIFO por thread (`heap_alloc` no C gerado): depois de muitas gerações, as listas novas nascem espalhadas pelo heap e percorrê-las vira acesso aleatório à memória. Medido no onemax com 8 ilhas × 64 × 1000 genes (~15 MB, acima dos 12 MB de L3): 44 ms por geração no início, 105 ms na geração 300, com a memória constante (não é vazamento); com uma ilha só (cabe na cache), 4,5 → 6 ms. Consequências: compare versões com a mesma semente e o mesmo número de gerações, meça trechos longos e não só o começo, e desconfie de ganho "superlinear" com threads nesse regime (8× com 16 threads no onemax de 3 mil genes): ele vem de mais acessos à memória em paralelo, não de mais CPU.

---

### 🔴 Armadilha 3b: `Array<T>` é `Type`, não `Data` — mas é ótimo como rascunho local
> **Conceito:** `Array<T>` tem exatamente um dono. No nativo é um buffer plano: 40 milhões de get/set aleatórios em 0,09 s.

* **Não pode ser duplicado:** não recebe `+`, não pode ser campo de tipo `Data`, nem morar numa estrutura polimórfica sobre `Data`:
  ```bend
  b = {Box{[0 : U32*4n]} : Box<Array<U32>>}  # ❌ "expected: Data, observed: Type"
  ```
  Logo, não serve como genoma de um GA (o campeão é duplicado para a população inteira).
* **Serve muito bem como rascunho local de um operador**, onde tem um dono só do começo ao fim. O OX1 marca genes num `Array<U32>`; a troca aleatória converte a lista em `Array`, troca in-place e converte de volta (`genetic/utils/genes.bend`: `to_array`/`from_array`).
* **Genéricos sobre o elemento precisam ser template.** Com `-G: Data` (apagado) o verificador aceita, mas o backend nativo recusa com **"an open Array element type"**: ele precisa do tipo concreto. Use `~G: Data`, que especializa em tempo de compilação.
* **Ler um `Array` num laço:** `Array.get` devolve o par `(array, valor)`, e desestruturar o retorno de uma chamada é um `match` proibido; o auxiliar óbvio cairia em recursão mútua. A saída é fazer do par o **estado do laço** e desestruturá-lo como parâmetro, dentro de cada caso:
  ```bend
  def read(k: Nat, r: Array<U32> & U32, +acc: U32, +s: U32) -> U32:
    match k:
      case 0n:
        (a, v) = r
        (acc + v : U32)
      case 1n+p:
        (a, v) = r
        read(p, Array.get(U32, a, s), (acc + v : U32), R.step(s))
  ```

---

### 🔴 Armadilha 4: `Nat` NÃO é caro no nativo (corrigido)
> **Conceito:** `Nat` é Peano no nível dos tipos e das provas, mas no binário nativo é uma palavra de máquina (o próprio GUIDE diz: "a `Nat` is still a machine word at runtime").

* **Medido:** 10 mil chamadas de `U32.to_nat(1000000)` custam 0,00 s no nativo. Versões anteriores deste guia afirmavam que `U32.to_nat(20)` alocava 20 nós — isso não vale para o binário.
* **Consequência:** use `Nat` como combustível de laço sem medo (`U32.to_nat(n)` é O(1)). O que continua caro é **acesso indexado a lista** (`List.get`, `nth`) dentro de laço quente: é O(n) por leitura por causa da lista, não do `Nat`. Escreva os operadores como varreduras, ou use um `Array` local.

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
* **Templates aninhados FUNCIONAM desde o 2.0.16** (no 2.0.9 falhavam com `expected: a term, observed: '~'`). Verificado no nativo:
  ```bend
  ap(~(x => (x + 10 : U32)), 1)                          # ✔️ lambda como template
  use(~U32, ~eval_child(~U32, ~rp, ~ft), 1, 2)            # ✔️ aplicação parcial de função com templates
  def outer(~h: U32 -> U32, x: U32) -> U32: ap(~twice(~h), x)   # ✔️ capturando um template externo
  ```
  Isso permite compor operadores (ex.: um `mutation_combine` que monta uma mutação a partir de outras) sem duplicar código.
* **Cada especialização de template conta como uma "unsafe annotation"** no 2.0.16: `ap(~inc, 1)` sozinho já faz o checker dizer `All terms check, with 1 unsafe annotation`. A cópia especializada não é reverificada (o corpo genérico já foi). Não confunda com `@unsafe` explícito — veja o checklist.
* **O template exige a assinatura exata, inclusive quantidades.** Uma função com `+` nos parâmetros não serve para um template declarado sem `+`:
  ```bend
  def popcount(+x: U32) -> U32: ...
  # ~fit: U32 -> U32   ❌ expected @_:U32 -> U32, observed @+x:U32 -> U32
  def fit(g: U32) -> U32: popcount(g)   # ✔️ envolva antes de passar
  ```

---

### 🔴 Armadilha 8: O que o `match` múltiplo não deixa fazer
> **Conceito:** `match a b:` escrutina vários valores de uma vez, mas é rígido.

* **O coringa é um `_` por escrutinado:** `case _ _:` (dois escrutinados), `case Nil{} _ _:` etc. Um único nome para todos (`case outro:`) é rejeitado com `expected: N patterns (one per scrutinee)` — versões anteriores deste guia concluíram errado, a partir dessa forma, que não havia coringa. Use-o para cortar os casos degenerados de um `match` múltiplo.
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
* **Devolver DOIS resultados de uma recursão** usa o mesmo truque: a recursão devolve o par e um auxiliar não recursivo o recebe como PARÂMETRO (`def cons2(x, y, r: A & B): (p, q) = r ...`) e põe as duas cabeças. Funciona, mas **meça no uso real**: para montar os dois filhos de um cruzamento numa varredura só, um microbenchmark (filhos somados e descartados na hora) mostrou 2× mais rápido que duas varreduras, e dentro do GA, onde os filhos vivem gerações e são percorridos de novo, deixou o motor 1,6× (1 ponto) a 3,4× (uniforme) mais LENTO. Os cruzamentos do motor usam duas varreduras.
* **`do` é palavra reservada** (do bloco `do IO<T>:`) e não pode ser nome de parâmetro.

---

### 🔴 Armadilha 9: Fluxos de semente que se sobrepõem
> **Conceito:** Sem estado global, a aleatoriedade é uma semente passada adiante. Dois consumidores que avançam pela MESMA sequência de estados usam os mesmos números.

* **O Erro:** avançar um laço externo com `R.step(seed)` quando o corpo também consome `R.step(seed)` — a iteração seguinte começa exatamente onde a atual continua, e as duas se sobrepõem. Numa versão antiga de `utils/random.bend`, `split.fst` era literalmente `step`, o que tornava isso fácil de cometer sem perceber.
* **Onde já mordeu:** no laço de gerações do motor (metade do fluxo aleatório reciclado), e duas vezes em testes estatísticos (Poisson com λ=10 e taxa de mutação saíam fora da faixa porque as amostras não eram independentes).
* **A Solução:** avance o laço externo com um `split.*` que o corpo não usa (`R.split.trd` é o convencional aqui). Os `split.*` atuais usam constantes distintas e nunca coincidem com `step`.

---

### 🔴 Armadilha 10: Ordem dos Parâmetros e dos Bindings
* **O tipo de um template não pode citar um tipo declarado depois dele.** `def f(~key: G -> U32, -G: Data, ...)` passa no verificador mas falha no nativo com "expected: a defined name, observed: G". Declare o tipo primeiro, como template: `def f(~G: Data, ~key: G -> U32, ...)`.
* **`match` depois de um `let` é rejeitado** ("this name is a def or a consumed binder"). Faça o `match` primeiro e os `let`s dentro de cada caso — inclusive `(a, v) = par`, que também é um `match`.
* **`+x = x` dentro de um caso de `match` funciona** (verificado no 2.0.16). O que falha é um `let` seguido de um `match` ou de uma desestruturação `(a, v) = par` no mesmo bloco; nesse caso use o `+` direto no padrão: `case Con{+h, t}:`.
* **`IO.args` é `List<&1, String>`, afim:** só pode ser percorrida uma vez e não aceita `+`. Converta de uma vez para uma lista `Data` (`utils/io.bend`: `numbers` + `num_at`).

---

### 🔴 Armadilha 11: Gerador sem estado absorvente e semente pequena
> **Conceito:** xorshift32 tem um ponto fixo: `xorshift(0) = 0`. Se um fluxo chega a 0, todo número dali em diante é 0.

* **O bug que existiu:** `split.snd(s) = step(step(s) xor K)` dava exatamente 0 para `s = 3783986154`, e uma semente 0 vinda da linha de comando também prendia o fluxo. `R.step` agora desvia o 0 para uma constante; não há estado absorvente (testado em `utils/random_test.bend`).
* **Semente pequena não é um número uniforme:** o xorshift a partir de uma semente pequena produz números pequenos nos primeiros passos. Nunca use a semente direto como probabilidade ou índice: `R.hit`, `R.range`, `R.unit` passam por `R.mix` (meio `lowbias32`, que também espalha os bits altos para os baixos que o `mod` usa).
* **Custo medido:** um hash completo por passo custaria o dobro do xorshift, e o gerador é chamado em quase toda operação — por isso o hash só entra no `mix`.

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
    ├── ga.bend                # Motor polimórfico: população, elitismo, torneio, ilhas
    ├── operators.bend         # Cruzamentos (genéricos sobre G, qualquer N)
    ├── mutations.bend         # Mutações (genéricas sobre G, qualquer N)
    ├── stats.bend             # Estatísticas de população
    ├── LAWS.bend / PROOF.bend # Leis formais e suas provas
    ├── utils/                 # poptree, genes (núcleo do vetor de genes)
    └── exemplos/              # onemax, sorting, tsp, sudoku
```


---

## 4. Checklist de Verificação Antes de Enviar Commits

```bash
# 1. Verificar provas formais. Não permita `@unsafe` EXPLÍCITO (a terminação dessa def não é verificada).
#    As "unsafe annotations" que o 2.0.16 conta por especialização de template (`~`) são outra coisa:
#    contam as cópias especializadas, que não são reverificadas, e aparecem em qualquer código com templates.
timeout 60s bend nome-do-arquivo.bend --checkup
# ATENÇÃO ao par LAWS.bend / PROOF.bend: `LAWS.bend` sozinho SEMPRE reporta
# TODOs (é só o enunciado), então `--checkup` falha nele — ele checa cada
# import isoladamente. Para esse par, verifique `bend PROOF.bend` direto.

# 2. Executar testes caso existam
timeout 60s bend nome-do-arquivo_test.bend

# 3. Verificar se a compilação nativa funciona sem erros — e RODAR o binário:
#    há erros que só o backend nativo acusa, e performance só vale medida nele
timeout 60s bend nome-do-arquivo.bend -o ./bin/nome-do-arquivo
timeout 60s ./bin/nome-do-arquivo --threads 1
timeout 60s ./bin/nome-do-arquivo --threads 12

# 4. Commit e Push imediato (na branch de feature, nunca na main e nunca faça merge)
git commit -am "tipo(escopo): mensagem descritiva"
git push origin feature/nome-da-feature
```
