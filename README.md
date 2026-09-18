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
```

## Verificando provas

Se o arquivo possui law e provas pode verificar se estão válidas

```bash
bend exemplos/ola.bend --checkup
```

## Inspecionando código

Gera o código nativo sem compilar ou executar

```bash
bend exemplos/ola.bend -o app.c
bend exemplos/ola.bend -o app.js
```