import os
import subprocess
import time
import json
import statistics

JSON_PATH = "/home/ubuntu/claude/aprendendo-bend2/genetic/data/horario_input.json"
BEND_BIN = os.environ.get("BEND_BIN", "bend")
BEND_SRC = "/home/ubuntu/claude/aprendendo-bend2/genetic/src/horario_solver.bend"
NATIVE_BIN = "/home/ubuntu/claude/aprendendo-bend2/genetic/horario_bin"

with open(JSON_PATH, "r") as f:
    json_str = f.read()

env = os.environ.copy()
env["BEND_NO_TELEMETRY"] = "1"
env["HORARIO_JSON"] = json_str

configurations = [
    ("1 CPU (taskset -c 0)", ["taskset", "-c", "0"]),
    ("2 CPUs (taskset -c 0,1)", ["taskset", "-c", "0,1"]),
    ("4 CPUs (taskset -c 0-3)", ["taskset", "-c", "0-3"]),
    ("8 CPUs (taskset -c 0-7)", ["taskset", "-c", "0-7"]),
    ("Sem taskset (default OS)", []),
]

def run_bench(name, cmd_base, is_interpreted):
    print(f"\n=======================================================")
    print(f"  BENCHMARK: {name}")
    print(f"=======================================================")
    results = {}
    base_mean = None

    for label, taskset_cmd in configurations:
        cmd = taskset_cmd + cmd_base
        samples = []
        # Warmup run
        subprocess.run(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        # 3 samplings
        for s in range(3):
            t0 = time.perf_counter()
            res = subprocess.run(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            t1 = time.perf_counter()
            elapsed = t1 - t0
            samples.append(elapsed)
            print(f"  [{label}] Amostra {s+1}/3: {elapsed*1000:.2f} ms")

        mean_val = statistics.mean(samples)
        min_val = min(samples)
        max_val = max(samples)
        if base_mean is None:
            base_mean = mean_val
        speedup = base_mean / mean_val if mean_val > 0 else 1.0

        results[label] = {
            "samples": samples,
            "mean_ms": mean_val * 1000,
            "min_ms": min_val * 1000,
            "max_ms": max_val * 1000,
            "speedup": speedup
        }

    return results

print("### INICIANDO BENCHMARK MULTI-CORE EM BEND 2 (HORARIO SOLVER) ###")
print(f"Cenário: 3 Turmas x 5 Dias x 4 Tempos = 60 slots | 20 Disciplinas | 10 Professores")
print(f"JSON: FormularioHorario real (Turmas 2026, 2025, 2024)\n")

res_native = run_bench("Executável Binário Nativo (bend -o horario_bin)", [NATIVE_BIN], False)
res_bend = run_bench("Interpretador Bend 2 CLI (bend horario_solver.bend)", [BEND_BIN, BEND_SRC], True)

print("\n\n================================================================================")
print("  TABELA CONSOLIDADA: BINÁRIO NATIVO (bend -o)")
print("================================================================================")
print("| Configuração             | Amostra 1 | Amostra 2 | Amostra 3 | Média     | Speedup |")
print("| :----------------------- | :-------- | :-------- | :-------- | :-------- | :------ |")
for label, data in res_native.items():
    s = data["samples"]
    print(f"| {label:<24} | {s[0]*1000:7.2f}ms | {s[1]*1000:7.2f}ms | {s[2]*1000:7.2f}ms | {data['mean_ms']:7.2f}ms | {data['speedup']:5.2f}x  |")

print("\n\n================================================================================")
print("  TABELA CONSOLIDADA: BEND 2 CLI (JIT / FFI Runtime)")
print("================================================================================")
print("| Configuração             | Amostra 1 | Amostra 2 | Amostra 3 | Média     | Speedup |")
print("| :----------------------- | :-------- | :-------- | :-------- | :-------- | :------ |")
for label, data in res_bend.items():
    s = data["samples"]
    print(f"| {label:<24} | {s[0]*1000:7.2f}ms | {s[1]*1000:7.2f}ms | {s[2]*1000:7.2f}ms | {data['mean_ms']:7.2f}ms | {data['speedup']:5.2f}x  |")
