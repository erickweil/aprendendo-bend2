# Aprendendo Bend2

A linguagem Bend2 promete ser tipo que um Haskell, com a sintaxe do Python, com capacidade provas de teoremas como o Lean/Coq, capaz de competir em velocidade com o C, e que permite execução paralela de forma nativa, com suporte a CPU multi-core ou até mesmo GPU.

Veja para mais informações:
- https://bend-lang.com/ Página oficial da linguagem Bend2, landing page
- https://x.com/bendlang Conta oficial do X da linguagem Bend2
- https://github.com/bendlang/bend Projeto oficial no github
- https://x.com/VictorTaelin Principal desenvolvedor da linguagem Bend2, que posta atualizações sobre o desenvolvimento da linguagem.
- https://bend2.dev/ Site que reporta o status atual e informações (como se já foi lançada ou não.)
- https://github.com/VictorTaelin/ Github do desenvolvedor da linguagem Bend2
- https://higherorderco.com/ Site oficial do projeto HigherOrderCO, que é o projeto que está desenvolvendo a linguagem Bend2.
- https://github.com/HigherOrderCO/ Repositório do projeto HigherOrderCO, onde será lançada a linguagem Bend2, e onde você pode acompanhar o desenvolvimento da linguagem.

## Instalando o Bend2

Seguindo as instruções em https://bend-lang.com/ é muito fácil instalar o Bend2
```bash
curl -fsSL https://bend-lang.com/install.sh | sh
```

> Siga as intruções para adicionar o bend ao PATH

Então para rodar o código basta utilizar o `bend` (Isso utilizará o interpretador, que é TS + bun)

```bash
bend exemplos/ola.bend
```

Utilize o guia para ter uma introdução inicial e agentes de IA terem um ponto de partida
```bash
bend guide > GUIDE.md
```

## Compilando o código

Também é possível compilar para nativo c (requer clang instalado)

```bash
bend exemplos/ola.bend -o bin/ola

# CPU single core
./bin/ola

# CPU multi thread
./bin/ola --threads 16

# GPU CUDA ou Apple Metal
./bin/ola --gpu 1GB

# As opções do runtime (um `--help` vai para o programa)
./bin/ola --bend-help
```

## Verificando provas

`bend arquivo.bend` sempre verifica o arquivo antes de rodar, inclusive as leis e provas
(veja `exemplos/provas.bend`). Para só verificar, sem rodar:

```bash
bend exemplos/provas.bend --check-only
```

## Inspecionando código

Gera o código nativo sem compilar ou executar

```bash
bend exemplos/ola.bend -o app.c
bend exemplos/ola.bend -o app.js
```

## Exemplos

Cada arquivo em `exemplos/` mostra um recurso da linguagem, do mais simples ao mais
elaborado. Quase todos aceitam argumentos (tamanho, semente...) e os que medem desempenho
imprimem o tempo; os números nos comentários foram medidos no binário nativo, variando
`--threads`.

```bash
bend exemplos/primos.bend -o bin/primos
./bin/primos 20000000 --threads 1
./bin/primos 20000000 --threads 12
```

| Exemplo | O que mostra |
|---|---|
| `ola`, `io` | `main`, o bloco `do`, `IO.print`, `show`, `<-` e `=` dentro do `do` |
| `bindings`, `tipos` | bindings afins e `+`, os tipos básicos e conversões, anotações |
| `funcoes`, `condicoes` | defs, `match` (Nat, U32, String, Bool), `Bool.pick` e por que ele é estrito |
| `repetindo`, `contando` | recursão, terminação com `Nat`, tail call, laço de IO |
| `lambda` | closures (afins) vs templates `~` |
| `listas`, `strings` | `List` e `String` com a Base: `foldl`, `filter`, `sort`, `split`, `join`... |
| `monad` | `do` com `Maybe`, `Result` e uma mônada própria (sorteios puros) |
| `mapas` | `Map` e `Set` da Base (contagem de palavras) |
| `provas` | `law`, provas por indução, reescrita com `%`, `?objetivo` |
| `sort_insertion` | parar uma recursão no meio sem `Bool.pick` (padrão da condição como parâmetro) |
| `arvore` | árvore de busca genérica, descer por um lado só, chamadas paralelas |
| `expressoes` | calculadora RPN: tipos-soma, `match` em String, pilha com `List.foldl` |
| `pow`, `fibonacci` | a chamada paralela `a b = f(x) g(y)`, `!` para GPU, escala com threads |
| `primos`, `crivo` | paralelismo e equilíbrio de carga; o algoritmo certo contra o paralelismo |
| `sort_merge` | merge sort paralelo: granularidade e localidade de memória |
| `monte_carlo` | aleatoriedade pura com fluxos independentes por tarefa (`utils/random`); `!` com tarefas para uma GPU |
| `histograma` | `Array.fork` + `Array.atomic.*` contra um array por tarefa |
| `arrays`, `arquivos` | `Array` (leitura devolve o array junto), `utils/arrays`, arquivos em blocos |
| `bmp`, `mandelbrot` | imagens BMP com `utils/bmp`; Mandelbrot paralelo (zoom, `!`, cor suave com estimativa de distância) gravado em BMP |
| `hilbert`, `hilbert_detalhe` | percurso genérico com callback; um codec de imagem pela curva de Hilbert |
| `json` | `utils/json`: ler, consultar e escrever JSON |
| `concorrencia` | `IO.fork`/`IO.join`, `IO.sleep`, canais (produtor/consumidor) |
| `servidor` | um servidor HTTP mínimo com TCP |
| `janela` | uma esfera quicando numa janela de largura x altura: `Image` em quadrantes, `App.loop` |
| `mandelbrot_janela` | importa `mandelbrot.bend` e desenha numa janela; clique esquerdo aproxima 2×, direito afasta |

O motor genético em `genetic/` é um projeto maior, com o próprio README.
