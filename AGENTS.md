# AGENTS.md — Guia de Engenharia e Operação em Bend 2

> Verificado contra o **bend 2.0.26**. Ao atualizar o bend, regenere o GUIDE.md (`bend guide > GUIDE.md`), leia o CHANGELOG (`curl -sL https://raw.githubusercontent.com/bendlang/bend/main/CHANGELOG.md`) e reverifique as armadilhas com sondas curtas compiladas para nativo. A versão instalada sai de `bend version`.

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
* **Performance só se mede no NATIVO.** `bend arquivo.bend` faz duas coisas diferentes conforme o `main`: um `main` que devolve **valor** é *normalizado pelo verificador* (preguiçoso: um `Bool.pick` ali não avalia o ramo descartado); um `main` que devolve **`IO`** roda *compilado*, mas numa trilha muito mais lenta que o binário — e já estrito. Medido no 2.0.26: 10⁹ passos de xorshift levam 57 s com `bend arquivo.bend` e 1,1 s com `-o`. Nenhum argumento de performance vale se não vier de um binário `-o`. E há erros que **só o backend nativo acusa** (ex.: "an open Array element type") — compile também o que só foi checado.
* **Ao medir código paralelo, varie as threads** (`--threads 1 2 4 8 12`) e compare com o teto real da máquina: um benchmark de tarefas **idênticas e independentes** com trabalho contínuo de CPU (neste i5-1245U de 15 W: 8 tarefas escalam só 1,7×, 64 tarefas 2,6×, nada melhora além de 4 threads). O `pow2` do GUIDE, com tarefas minúsculas, dá 3,2× e é uma referência otimista. Um platô antes do número de tarefas independentes indica parte sequencial ou desbalanceamento; um platô que piora conforme o volume de dados cresce indica limite de banda de memória.
* **Compilação e Verificação Estática:**
  - Checar sem rodar: `timeout 60s bend <arquivo.bend> --check-only` (checa o arquivo e os imports).
  - Verificação de provas e teoremas: `timeout 60s bend PROOF.bend` (veja a seção 4 sobre o par LAWS/PROOF).
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
> **Conceito:** Na HVM, `Bool.pick(T, cond, then_branch, else_branch)` avalia **ambos os ramos** incondicionalmente. Só é preguiçoso quando o `main` devolve um valor e o verificador o normaliza (veja 1.1). Reverificado no 2.0.26, no nativo e em `bend arquivo.bend` com `main` de IO: o ramo pesado custa o mesmo tempo com a condição verdadeira ou falsa.
* **Pega também quem usa árvores:** um `inserir`/`buscar` de árvore binária escrito como `Bool.pick(..., No{v, inserir(esq), dir}, No{v, esq, inserir(dir)})` desce pelos **dois** lados a cada nível, e passa a visitar a árvore inteira: O(n) por operação em vez de O(log n). Medido em `exemplos/hilbert.bend` (que usa `exemplos/arvore.bend`): o tempo cresce 16× por nível da curva (4× mais pontos), ou seja, O(n²) — 2,74 s na profundidade 6. Escreva o desvio com `match` num auxiliar `.step` sobre o `Cmp`.

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
  A condição do passo **anterior** entra como parâmetro, então o ramo `True{}` retorna sem nunca mencionar a chamada recursiva. (Versões anteriores recusavam o açúcar `h <> t` em `match` com vários escrutinados; no 2.0.26 `case h <> t True{}:` compila e roda no nativo.)

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
* **Um registro `Data` compartilhado só pode conter ESCALARES se for lido por tarefas.** É o caso mais fácil de errar, porque o tipo parece inofensivo. Um contexto de problema `Data` que guarda uma `List` (ou qualquer estrutura de heap) paga contagem de referência COMPARTILHADA a cada duplicação `+`, e o motor duplica o contexto em toda callback de toda tarefa. Medido no sudoku (8 demes, 8 E-cores homogêneos, 5000 gerações): com uma `List` de 81 elementos no contexto, 6,61 s → 4,18 s (**1,58×**); trocando por dois `U32`, 5,61 s → 0,95 s (**5,91×**). O paralelismo quase quadruplicou e o caso de um núcleo ainda ficou mais rápido. Se o caminho frio precisar da estrutura, reconstrua-a lá dentro a partir de um escalar — uma alocação local por chamada fria é muito mais barata que um atômico contestado por leitura.
* **Descer uma árvore compartilhada é caro mesmo com tudo na cache.** Abrir um nó `+` com `match` entrega os campos como `+` (contagem de referência). Medido: ~25 ns por nível, ~170 ns para achar uma folha entre 64, contra ~3 ns para ler um `Array` local. Para MUITAS leituras aleatórias da mesma estrutura, copie o que precisa para um `Array` local numa travessia só e leia dali: foi o que tirou o torneio do GA da árvore (−11% a −30% no sudoku, conforme o tamanho do torneio).
* **Balanceie.** O fork-join não rouba trabalho: se um lado termina antes, aquele núcleo fica ocioso. Numa CPU híbrida (núcleos P + E) a tarefa mais lenta dita o tempo. E nunca haverá mais tarefas pesadas simultâneas do que folhas na árvore de chamadas paralelas (8 ilhas ⇒ platô em 8 threads).
* **Passadas sequenciais contam (Amdahl).** O `diversity_check` do motor é uma passada sequencial por ilha: com uma ilha só, 12 threads não ganham nada. Com várias ilhas, cada passada roda na tarefa da sua ilha.
* **Desde o 2.0.22 dá para COMPARTILHAR um `Array` entre tarefas**, o que antes era impossível (`Array<T>` tem um dono só). `Array.fork(T, a)` devolve dois handles para o MESMO bloco, `Array.join(T, l, r)` junta de volta, e `Array.atomic.*` (`add sub and or xor min max cas exch`, mais `fadd` em `Array<F32>`) escrevem do jeito certo quando duas tarefas batem no mesmo slot. Verificado no nativo: duas tarefas somando 100 mil vezes no MESMO slot dão exatamente 200000 com `--threads 4` e com `--threads 1`.
  - **`Array.fork`/`Array.join` são `@unsafe`** (nada garante que as escritas não se cruzem): o veredito do `--check-only` passa a nomear as defs que dependem deles, então isso aparece na revisão. Um `match` num handle forkado **copia** a parte, como um `Array.clone` — percorrer estruturalmente um array compartilhado continua proibido.
  - **Custo medido** (10M operações, 1 thread, array de 2^10 na cache): `Array.atomic.add` **4,5 ns**, contra **0,55 ns** de um `Array.get` + `Array.set` comum. São ~8×: o atômico serve para o ponto de encontro (um acumulador, um contador, um histograma), não para o laço quente.
  - Isso é a saída para o caso "tarefas que compartilham uma estrutura grande não escalam" acima: em vez de um `+pop` que paga um atômico por leitura e só é liberado no fim, um `fork` dá leitura direta ao bloco.

* **Volume de dados limita.** O mesmo GA, mesma forma, mesmo trabalho total: 3,16× com genomas de 10 mil genes (cabem em cache), 1,45× com 1 milhão (500 MB, limitado por banda de memória).
* **Quando os dados vivos passam da cache, o custo por iteração CRESCE com o tempo.** O alocador nativo reaproveita os nós liberados numa pilha LIFO por thread (`heap_alloc` no C gerado): depois de muitas gerações, as listas novas nascem espalhadas pelo heap e percorrê-las vira acesso aleatório à memória. Medido no onemax com 8 ilhas × 64 × 1000 genes (~15 MB, acima dos 12 MB de L3): 44 ms por geração no início, 105 ms na geração 300, com a memória constante (não é vazamento); com uma ilha só (cabe na cache), 4,5 → 6 ms. Consequências: compare versões com a mesma semente e o mesmo número de gerações, meça trechos longos e não só o começo, e desconfie de ganho "superlinear" com threads nesse regime (8× com 16 threads no onemax de 3 mil genes): ele vem de mais acessos à memória em paralelo, não de mais CPU.

---

### 🔴 Armadilha 3b: `Array<T>` é `Type`, não `Data` — mas é ótimo como rascunho local
> **Conceito:** `Array<T>` tem exatamente um dono. No nativo é um buffer plano: 40 milhões de get/set aleatórios em 0,09 s.

* **Não pode ser duplicado:** não recebe `+`, não pode ser campo de tipo `Data`, nem morar numa estrutura polimórfica sobre `Data`:
  ```bend
  b = {Box{[0 : U32*4n]} : Box<Array<U32>>}  # ❌ "expected: Data, observed: Type"
  ```
  Um campo de registro **`Type`** aceita, sim (veja a Armadilha 3c): `type Individual<-G: Type> is Type` guarda um `Array`. O que não existe é `Array` dentro de `Data`.
* **Genéricos sobre o elemento precisam ser template.** Com `-G: Data` (apagado) o verificador aceita, mas o backend nativo recusa com **"an open Array element type"**: ele precisa do tipo concreto. Use `~G: Data`, que especializa em tempo de compilação. **Revalidado no 2.0.26** (o changelog mexeu no layout da célula no 2.0.22, #893, e nas intrínsecas de array no 2.0.25, #955, mas isto não mudou): `def first(-T: Data, a: Array<T>) -> Array<T> & T: Array.get(T, a, 0)` dá `All terms check.` no `--check-only` e morre com `an open Array element type` no `-o`. É o exemplo mínimo de por que o passo 3 do checklist (compilar para nativo) não é opcional.
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

### 🔴 Armadilha 3c: o `Array` é uma árvore no TIPO e um buffer plano na MEMÓRIA
> **Conceito:** `Array<T>` é declarado como árvore (`ALeaf`/`ANode`) e o `match` nela é legal, mas no nativo os dados vivem num buffer plano. **Abrir um nó com `match` materializa/copia a sub-árvore.** Toda a diferença de desempenho entre as formas de percorrer um array vem daí. Tudo abaixo foi medido no nativo com `utils/arrays.bend` (i5-1245U, n = 2^20, 100 passadas).

* **A tabela que decide como escrever:**

  | operação | custo por elemento | como é feita |
  |---|---|---|
  | `reduce` / `fold_rot` (laço por índice) | **0,4 ns** | `Array.get`/`Array.swap` |
  | `for_each_rot` (1 swap por elemento) | **0,58 ns** | `Array.swap` |
  | `for_each` (get + set) | 0,78 ns | `Array.get` + `Array.set` |
  | `for_each_hole` (2 swaps) | 1,30 ns | `Array.swap` × 2 |
  | `zip_with` (2 get + 1 set) | 1,5 ns | por índice |
  | `reduce_consume` (percurso em árvore) | **18,8 ns** | `match ALeaf/ANode` |
  | `reduce` antigo em árvore, com `with` por nó | **65 ns** | `match` + closure por elemento |

* **Regra:** percorra sempre por ÍNDICE; nunca com `match` na estrutura. Um `match` estrutural é 20× a 160× mais caro.
* **`Array.map` da Base segue a regra desde o 2.0.23:** lê cada célula e escreve num array novo, em vez de dividir e remontar a árvore (16M `U32` em 15 ms contra 176 ms, segundo o changelog). O preço é que os elementos agora têm de ser `Data`; um map sobre elemento `Type` continua escrito à mão.
* **`with`/closure por elemento é veneno:** a mesma travessia custa 1,5 ns por elemento com auxiliar nomeado e **38 ns** com um `with` por elemento (25×). Use `with` só na borda (abrir o `Array.size` no começo, montar o IO no fim) — veja `utils/tuples.bend`.
* **`U32.shln(1, k)` com `k >= 32` devolve 0, não dá a volta.** Medido: `shln(1,32) = 0` e `shln(1,33) = 0`. Uma máscara de bits usada como conjunto (o truque óbvio para "esta chave já apareceu") portanto **falha em silêncio** assim que o alfabeto passa de 32: toda chave alta responde "ausente" e o algoritmo produz duplicatas sem erro nenhum. Para conjuntos de chaves sem teto, use uma faixa de rascunho do próprio `Array` (uma posição por chave) — é o que `genetic/operators.bend` faz no OX1, ao custo de um `Array.get` (0,55 ns) por consulta.
* **`[v : T*n]` é CONTAGEM, `[v : T^d]` é PROFUNDIDADE.** A contagem tem de ser potência de 2 ou o compilador responde `a power of two count (^d takes a depth)`. `[0 : U32*8n]` e `[0 : U32^3n]` são o mesmo array de 8 slots; `[0 : U32*20n]` não compila (20 não é potência de 2) — o que se queria ali era `[0 : U32^20n]`, com 2^20 slots.
* **`Array.size` é grátis** (O(log n)): 100 mil chamadas num array de 2^20 em menos de 10 ms. Não precisa carregar o tamanho na mão por medo dele.
* **Elemento `Data` vs elemento `Type`.** `Array.get` exige `-T: Data` (ele copia o valor). Para elemento `Type` (um `Array` dentro de `Array`, ou um registro linear) **só existe `Array.swap`**, que é o `mem::replace` do Rust: para tirar um valor é preciso pôr outro no lugar — um **buraco**.
  - O buraco **circula**: entra no slot, e quando o valor volta o buraco reaparece na mão. Uma única alocação no programa inteiro.
  - **Não existe swap de duas posições sem buraco em O(1).** Dá para escrever sem buraco descendo a estrutura (`match` até os dois `ALeaf` e reconstruir trocados — funciona, e `i == j` fica no-op de graça), mas custa **O(n)**: 1M trocas num array de 2^12 levam 15,65 s contra 0,01 s da versão com buraco (3 swaps, ~10 ns cada). **Falta um `Array.swap2(a, i, j)` na Base** (o `slice::swap` do Rust) — vale abrir issue.
  - **Percorrer com 1 swap por elemento (`for_each_rot`/`fold_rot`) é a forma mais rápida de todas**, inclusive mais rápida que get+set em elemento `Data`: o valor devolvido ao array é o elemento já processado do passo anterior, então o buraco só entra uma vez. **Preço:** o array termina rotacionado uma posição. Ótimo para uma população (saco de indivíduos), **inaceitável para dados posicionais** como os genes de um genoma.
  - `swap_at_hole(i, j)` com `i == j` **corromperia** o array (o buraco ficaria dentro) — checar antes é obrigatório, e índices dão a volta, então normalize com `U32.and(i, n-1)` antes de comparar.
* **Registro `Type` polimórfico funciona**: `type Individual<-G: Type> is Type: Individual{gene: G, fit: U32, hash: U32}` guarda um `Array` num campo, e `Array<Individual<Array<U32>>>` é uma população válida. Ler um campo é O(1): `Array.swap` empresta, desestrutura, reconstrói o registro, devolve — **medido 3 ns por leitura**, igual a ler de um `Array<U32>` espelho.
* **Dividir a população em paralelo é barato; dividir um genoma não.** `match ANode` num `Array<Individual>` copia só os *handles* (n = número de indivíduos), então demes em paralelo custam quase nada: 128 indivíduos × 16 384 genes, 100 gerações, 8 demes → 0,55 s com 1 thread e 0,38 s com 2, memória constante. O mesmo `match` num genoma de 1M genes copia 1M palavras.
* **Um argumento template não captura valor de runtime:** `Arr.from_fn(~U32, ~(k => (j * 10 + k : U32)), 2n)` com `j` vindo de parâmetro falha com *"a template applied to closed ~ arguments (a def parameter is not comptime)"*. É por isso que toda callback do motor recebe o contexto `P` como parâmetro comum. Arrays de elemento `Type` também não podem ser criados com `Array.new` (que exige `Data`): construa o esqueleto com recursão comum devolvendo `ALeaf`/`ANode`.

---

### 🔴 Armadilha 3d: aleatoriedade — o `IO.random_u32` não serve para o laço quente
> **Conceito:** desde a 2.0.x existe `IO.random_u32() -> IO(Result<...>)`, que é uma **syscall `getrandom()` por chamada**, dentro do IO.

* **Medido no nativo:** `IO.random_u32` custa **11 µs por chamada** (100 mil chamadas em 1,10 s) — 5500× o xorshift puro. E sendo IO, não pode ser chamado de dentro de código puro nem de tarefa paralela.
* **Use-o só para a semente inicial** (uma chamada no `main`), como o `fastrand` do Rust: aleatório seguro só na semente, xorshift determinístico daí em diante.
* **Custos do gerador puro** (`utils/random.bend`, 50M sorteios): `R.step` (xorshift) **2,0 ns**; `R.range` (step + `mix` + mod) **3,6 ns**; `R.hash32` (lowbias32 completo) 3,0 ns.
---

### 🔴 Armadilha 3e: arquivos — a Base troca bytes como `List`, um nó por byte
> **Conceito:** `File.read_bytes`, `File.read_at` e `File.write_bytes` recebem e devolvem `List<&2, U32>` (um byte por elemento). Todo efeito sobre um `File` devolve `IO(File & Result<.., A>)`: o handle afim volta junto com o resultado.

* **Leia e grave em blocos, nunca o arquivo inteiro numa lista.** Medido (64 MB, nativo, 2.0.26): a lista inteira custa **1,8 GB** de pico (~28 bytes por byte do arquivo) e 1,15 s; em blocos de 1 MB via `read_at`, **290 MB** e 0,78 s. Gravar: ~1,1 s e 1,9 GB contra ~0,55 s e 290 MB. O custo fica em ~10 ns por byte, dominado pela construção da lista na Base. Pronto em `utils/arquivos.bend` (`ler_bytes`/`gravar_bytes` usam blocos de 1 MB).
* **`File.read_*` fazem UMA syscall `read()`**: num arquivo regular vem tudo, mas não há laço de leitura parcial por baixo.
* **Um arquivo vazio pede tratamento à parte:** a conta de blocos `ceil(n / bloco) - 1` dá a volta para 4 bilhões com `n = 0`.
* **Imagens:** não há decodificador de PNG/JPEG. `utils/bmp.bend` lê BMP de 24/32 bits sem compressão (de baixo para cima ou de cima para baixo) e grava 24 bits; `exemplos/hilbert_imagem.bend` é um codec que usa isso.

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


### 🟢 Armadilha 5b (corrigida): chamada local dentro de anotação vira `Tipo.nome` (só quando o módulo é importado)
> **Não reproduz no 2.0.26.** A sonda abaixo (um `unit` local dentro de `(p * unit(seed) : F32)`, importado tanto por `./m.bend` quanto por `./../m.bend`) checa e roda. O changelog do 2.0.22 (#903: "an operator is the name whose only dot leads it") e o do 2.0.23 (#915) mexeram exatamente nisso. A forma de contornar abaixo continua válida e não custa nada; o código do repositório pode ficar como está.

> **Conceito (histórico):** desde o 2.0.17 o operador pega o tipo da anotação `( .. : T)` em volta dele. O efeito colateral era que um nome LOCAL chamado dentro dessa anotação podia ser resolvido no namespace do tipo.

* **O erro:**
  ```bend
  +p2 = (p * unit(seed) : F32)     # ❌ expected: a defined name, observed: F32.../utils/random.unit
  ```
  O nome local `unit` virou `F32.unit`, que não existe.
* **Só aparece quando o módulo é IMPORTADO por outro.** Checando o arquivo sozinho, `--check-only` diz `All terms check` — o erro só surge no arquivo que o importa. Um módulo "verificado" isoladamente pode estar quebrado.
* **A solução** é tirar a chamada de dentro da anotação:
  ```bend
  +u = unit(seed)
  +p2 = (p * u : F32)              # ✔️
  ```
* Mordeu duas vezes neste repositório: `utils/random.bend` (`unit`, `gap`, `poisson.go`) e `genetic/ga.bend` (`call_seed`).

---

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
* **Let tipado (desde o 2.0.22):** `x : T = v` é açúcar para `x = {v : T}`, e aceita `+`. É a forma mais legível, dentro e fora de `do`:
  ```bend
  +x : U32 = 1        # ✔️ verificado no nativo (2.0.26)
  ```
  Um let com padrão não leva tipo: `(a, b) : T = v` não existe; desestruture no corpo.

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

* **Templates vêm ANTES de tudo na assinatura.** No 2.0.26 a própria declaração é recusada com `expected: a plain binder (only leading binders take ~)` (antes falhava só na chamada recursiva, com `expected: a term, observed: '~'`):
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
* **Dois binders `~` com o mesmo nome são recusados** (2.0.23): `expected: a fresh ~ binder name`.
* **Uma instância que chama de volta uma instância em verificação é recusada** (2.0.21): `loop(~k, u) = bounce(~loop(~k), u)` com `bounce(~f, u) = f(u)` é lido como auto-chamada que não decresce. Se precisar desse formato, quebre a recursão num parâmetro comum (não template).
* **O template exige a assinatura exata, inclusive quantidades.** Uma função com `+` nos parâmetros não serve para um template declarado sem `+`:
  ```bend
  def bit_count(+x: U32) -> U32: ...
  # ~fit: U32 -> U32   ❌ expected @_:U32 -> U32, observed @+x:U32 -> U32
  def fit(g: U32) -> U32: bit_count(g)   # ✔️ envolva antes de passar
  ```
* **Callback com estado = template + acumulador.** Uma closure não serve para ser chamada várias vezes (Armadilha 1), e um template não captura nada. O estado vai num parâmetro a mais, que a callback recebe e devolve: `~f: S -> Vec2 -> Dir -> Dir -> S`. Três detalhes fazem funcionar (veja `exemplos/hilbert_callback.bend`):
  - declare `~S: Type` (não `Data`): assim o acumulador pode ser um `Array`, por exemplo uma tela com uma célula por posição;
  - guarde o acumulador **no mesmo registro** que o resto do estado do laço (`type Tart<-S: Type> is Type: Tart{pos, dir, chegada, acc: S}`), para que cada passo receba e devolva um valor só; com um par `Estado & S` seria preciso desestruturar o retorno de uma chamada (proibido);
  - a callback de topo usa parâmetros sem `+`, exatamente como o tipo do template; quem precisa de `+` é um auxiliar que ela chama.

---

### 🔴 Armadilha 8: O que o `match` múltiplo não deixa fazer
> **Conceito:** `match a b:` escrutina vários valores de uma vez, mas é rígido.

* **O coringa é um `_` por escrutinado:** `case _ _:` (dois escrutinados), `case Nil{} _ _:` etc. Um único nome para todos (`case outro:`) é rejeitado com `expected: N patterns (one per scrutinee)` — versões anteriores deste guia concluíram errado, a partir dessa forma, que não havia coringa. Use-o para cortar os casos degenerados de um `match` múltiplo.
* **(Corrigido) Desestruturar, dentro de um `match` múltiplo, um parâmetro que NÃO é escrutinado.** Até o 2.0.22, `match k flag:` com `(a, v) = r` num caso passava no verificador mas o `-o` recusava com "a match on a parameter or field (this name is a def or a consumed binder)". **No 2.0.26 compila e roda no nativo.** O formato antigo de contornar (`match` simples no argumento que encolhe, desestruturar o par e só então um `match` aninhado sobre as flags) continua válido e é o que o motor usa:
  ```bend
  match k:
    case 0n: ...
    case 1n+p:
      (a, +v) = r
      match on_fit stop:
        case _ True{}: ...
        case True{} False{}: ...
  ```
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
* **Não há referência para a frente: uma def só enxerga o que já foi definido ACIMA dela no arquivo.** Chamar um auxiliar declarado mais abaixo dá `expected: a defined name, observed: <nome>`. Some isso à falta de recursão mútua (Armadilha 5) e a ordem do arquivo passa a ser parte do projeto: auxiliar primeiro, laço depois.
* **O tipo de um template não pode citar um tipo declarado depois dele.** `def f(~key: G -> U32, -G: Data, ...)` passa no verificador mas falha no nativo com "expected: a defined name, observed: G". Declare o tipo primeiro, como template: `def f(~G: Data, ~key: G -> U32, ...)`.
* **(Corrigido no 2.0.26) Dois nomes que só diferem em maiúsculas colidiam no backend nativo.** `def CHECK()` e `def check()` no mesmo arquivo faziam o `-o` morrer com `two names mangle to FID_CHECK`; no 2.0.26 compila e cada um devolve o seu valor.
* **`match` depois de um `let` é rejeitado** ("this name is a def or a consumed binder"; reverificado no 2.0.26). Faça o `match` primeiro e os `let`s dentro de cada caso — inclusive `(a, v) = par`, que também é um `match`.
* **`+x = x` dentro de um caso de `match` funciona** (verificado no 2.0.16). O que falha é um `let` seguido de um `match` ou de uma desestruturação `(a, v) = par` no mesmo bloco; nesse caso use o `+` direto no padrão: `case Con{+h, t}:`.
* **`IO.args` é `List<&1, String>`, afim:** só pode ser percorrida uma vez e não aceita `+`. Converta de uma vez para uma lista `Data` (`utils/io.bend`: `numbers` + `num_at` para números, `texts` + `text_at` para caminhos e nomes).
* **Uma lambda não desestrutura o próprio parâmetro.** `r => (a, b) = r ...` é recusado ("a match on a parameter or field"). Num laço de IO, onde o bind entrega um `File & X`, torne esse par um **parâmetro da próxima chamada** do laço e abra-o lá (`gravar_blocos.go` em `utils/arquivos.bend`). Um auxiliar que abre o par e chama o laço de volta seria recursão mútua.
* **Dentro de `do` não há `match` nem desestruturação.** Um `match` solto dá "a match heads a def body, not a term", e `K{a, b} = x` dá "expected: a pattern". Leve a decisão para uma def e chame-a do bloco.
* **Anotação como argumento pede parênteses duplos:** `U32.show(pm / 10 : U32)` falha com `expected: a term, observed: ':'`; escreva `U32.show((pm / 10 : U32))`.
* **`parte * 1000` estoura o `U32` em silêncio** (acima de ~4,3M). Contas de porcentagem sobre tamanhos de arquivo precisam de outra ordem de operações (veja `permil` em `exemplos/hilbert_imagem.bend`).

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
├── utils/                     # Helpers gerais:
│   ├── arrays.bend            #   percursos e trocas de Array (custos na Armadilha 3c)
│   ├── tuples.bend            #   `A & B`: pair/with/fst/snd/map_* (leia o aviso sobre closure)
│   ├── arquivos.bend          #   ler/gravar texto e bytes, em blocos (Armadilha 3e)
│   ├── bmp.bend               #   BMP 24/32 bits <-> `Imagem` (um `0xRRGGBB` por pixel)
│   └── random, math, vec4, io, json
└── genetic/                   # Motor genético (veja genetic/README.md)
```

---

## 4. Checklist de Verificação Antes de Enviar Commits

```bash
# 1. Checar o arquivo e seus imports SEM rodar. O veredito nomeia as defs que
#    dependem de `@unsafe` ou de código estrangeiro; não permita `@unsafe` EXPLÍCITO
timeout 60s bend nome-do-arquivo.bend --check-only
# ATENÇÃO ao par LAWS.bend / PROOF.bend: `LAWS.bend` falha, verifique `bend PROOF.bend` direto.

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
