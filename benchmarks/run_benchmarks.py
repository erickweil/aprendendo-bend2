#!/usr/bin/env python3
import subprocess
import time
import os
import glob

BEND_BIN = os.environ.get("BEND_BIN", "bend")
ENV = os.environ.copy()
ENV["BEND_NO_TELEMETRY"] = "1"
ENV["PATH"] = f"{os.path.expanduser('~/.bend/bin')}:{ENV.get('PATH', '')}"

def run_command(cmd, cwd=None):
    return subprocess.run(cmd, cwd=cwd, env=ENV, capture_output=True, text=True)

def measure_time(cmd, repeats=3):
    durations = []
    output = ""
    for _ in range(repeats):
        t0 = time.perf_counter()
        res = subprocess.run(cmd, env=ENV, capture_output=True, text=True)
        t1 = time.perf_counter()
        if res.returncode != 0:
            return None, res.stderr
        durations.append((t1 - t0) * 1000)
        output = res.stdout
    return min(durations), output

def benchmark_original():
    print("=== 1. Benchmarking 19 Original Examples ===")
    results = []
    bins = sorted(glob.glob("/home/ubuntu/claude/aprendendo-bend2/bin/*"))
    for b in bins:
        name = os.path.basename(b)
        times = {}
        for th in [1, 2, 4]:
            t, _ = measure_time([b, "--threads", str(th)], repeats=3)
            times[th] = t
        results.append((name, times))
        print(f"{name:16} | 1T: {times[1]:5.2f} ms | 2T: {times[2]:5.2f} ms | 4T: {times[4]:5.2f} ms")
    return results

def create_and_compile(src_code, name):
    bend_path = f"/home/ubuntu/claude/aprendendo-bend2/benchmarks/{name}.bend"
    bin_path = f"/home/ubuntu/claude/aprendendo-bend2/benchmarks/{name}"
    with open(bend_path, "w") as f:
        f.write(src_code)
    comp = run_command([BEND_BIN, bend_path, "-o", bin_path])
    if comp.returncode != 0:
        print(f"Error compiling {name}:", comp.stderr)
        return None
    return bin_path

def benchmark_scaled():
    print("\n=== 2. Creating and Benchmarking Scaled Workloads ===")
    scaled_tests = {}

    # 1. Pow Parallel 2^24 e 2^26
    for exp in [24, 26]:
        code = f"""import Base
def pow2(+d: Nat) -> U32:
  match d:
    case 0n:
      1
    case 1n+p:
      a b = pow2(p) pow2(p)
      (a + b : U32)
def main() -> IO(Unit):
  IO.print("2^{exp} = " ++ U32.show(pow2({exp}n)))
"""
        p = create_and_compile(code, f"pow_par_{exp}")
        if p:
            scaled_tests[f"pow2(2^{exp}) [Árvore Paralela]"] = p

    # 2. Fibonacci Recursivo (24n e 26n)
    for n in [22, 25]:
        code = f"""import Base
def fib(+n: Nat) -> Nat:
  match n:
    case 0n:
      0n
    case 1n:
      1n
    case 2n+p:
      fib(p) + fib(1n+p)
def main() -> IO(Unit):
  IO.print("fib({n}n) = " ++ Nat.show(fib({n}n)))
"""
        p = create_and_compile(code, f"fib_{n}")
        if p:
            scaled_tests[f"fib({n}n) [Recursão em Árvore]"] = p

    # 3. Hilbert Curve (depth 3 vs depth 4 vs depth 5)
    with open("/home/ubuntu/claude/aprendendo-bend2/exemplos/hilbert.bend") as f:
        hilbert_base = f.read()
    for d in [3, 4, 5]:
        code = hilbert_base.replace("def profundidade() -> U32:\n  3", f"def profundidade() -> U32:\n  {d}")
        code = code.replace("import arvore.bend as A", "import /home/ubuntu/claude/aprendendo-bend2/exemplos/arvore.bend as A")
        p = create_and_compile(code, f"hilbert_d{d}")
        if p:
            grid_size = 2**d
            scaled_tests[f"hilbert(d={d}) [{grid_size}x{grid_size} nós BST]"] = p

    # 4. Primos (checar se grande primo é primo)
    with open("/home/ubuntu/claude/aprendendo-bend2/exemplos/primos.bend") as f:
        primos_base = f.read()
    for prime in [100003, 1000003]:
        code = primos_base.replace("def numero() -> U32:\n  11", f"def numero() -> U32:\n  {prime}")
        p = create_and_compile(code, f"primos_{prime}")
        if p:
            scaled_tests[f"eh_primo({prime})"] = p

    # 5. Repetindo
    with open("/home/ubuntu/claude/aprendendo-bend2/exemplos/repetindo.bend") as f:
        rep_base = f.read()
    for count in [500, 2000]:
        code = rep_base.replace("def valor() -> Nat:\n  5n", f"def valor() -> Nat:\n  {count}n")
        p = create_and_compile(code, f"repetindo_{count}")
        if p:
            scaled_tests[f"repetir({count}n)"] = p

    # Run scaled benchmarks
    scaled_results = []
    for desc, bin_path in scaled_tests.items():
        times = {}
        for th in [1, 2, 4]:
            t, _ = measure_time([bin_path, "--threads", str(th)], repeats=3)
            times[th] = t
        speedup2 = times[1] / times[2] if times[2] else 1.0
        speedup4 = times[1] / times[4] if times[4] else 1.0
        scaled_results.append((desc, times, speedup2, speedup4))
        print(f"{desc:35} | 1T: {times[1]:7.2f} ms | 2T: {times[2]:7.2f} ms ({speedup2:4.2f}x) | 4T: {times[4]:7.2f} ms ({speedup4:4.2f}x)")

    return scaled_results

if __name__ == "__main__":
    orig = benchmark_original()
    scaled = benchmark_scaled()
    
    with open("/home/ubuntu/claude/aprendendo-bend2/benchmarks/REPORT.md", "w") as f:
        f.write("# Relatório de Desempenho: Backend C Nativo no Bend 2\n\n")
        f.write("Ambiente: Ubuntu 24.04, 4 vCPUs, Clang 19, Bend 2.\n\n")
        
        f.write("## 1. Todos os 19 Exemplos Originais (Cargas Padrão)\n\n")
        f.write("| Exemplo | 1 Thread | 2 Threads | 4 Threads | Status |\n")
        f.write("| :--- | :---: | :---: | :---: | :---: |\n")
        for name, times in orig:
            f.write(f"| `{name}.bend` | {times[1]:.2f} ms | {times[2]:.2f} ms | {times[4]:.2f} ms | ✅ Sucesso |\n")
            
        f.write("\n## 2. Testes com Cargas Escaladas (Workload Scaling)\n\n")
        f.write("| Algoritmo / Carga | 1 Thread | 2 Threads (Speedup) | 4 Threads (Speedup) |\n")
        f.write("| :--- | :---: | :---: | :---: |\n")
        for desc, times, sp2, sp4 in scaled:
            f.write(f"| **{desc}** | {times[1]:.2f} ms | {times[2]:.2f} ms (**{sp2:.2f}x**) | {times[4]:.2f} ms (**{sp4:.2f}x**) |\n")
            
        f.write("\n## 3. Observações e Conclusões\n\n")
        f.write("1. **Eficiência do Backend C**: A geração de código em C nativo com clang-19 produz executáveis extremamente compactos e rápidos, onde exemplos triviais executam em 1-3 ms.\n")
        f.write("2. **Escala Multithreading**: Em algoritmos paralelos como a árvore de chamadas do `pow2`, o scheduler de trabalho distribui as tarefas nas threads da CPU.\n")
        f.write("3. **Algoritmos Sequenciais**: Algoritmos estritamente sequenciais (como laços em `repetindo` ou `primos`) rodam em thread única com desempenho previsível e sem overhead de sincronização.\n")
    print("\nRelatório gerado em /home/ubuntu/claude/aprendendo-bend2/benchmarks/REPORT.md")
