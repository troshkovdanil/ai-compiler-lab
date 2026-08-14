# Experiment 02 — Ascend NPU

Goal: understand Ascend AI Core compilation and execution using Ascend C/CANN.

Progression:

1. Hello World
2. Vector Add
3. GEMM 128x128x128
4. GEMM tiling
5. Cube/MTE pipelining
6. Cube + Vector synchronization

Initial target:
- Host: x86_64 Ubuntu
- Development: CANN / Ascend C
- Execution: CPU debug or simulator
- Hardware execution later if Ascend NPU becomes available

For a fresh machine the setup becomes:
```
./scripts/install-cann.sh
./scripts/fetch-ascendnpu-ir.sh
```

Then we can verify:
```
source ~/Ascend/cann/set_env.sh
bishengir-opt --version
git -C third_party/ascendnpu-ir rev-parse HEAD
```

Both should point to:
```
0e81fb9f843e
```

Links:

https://llvm.org/devmtg/2026-04/slides/tutorial/tutorial_tarasov.pdf

https://www.hiascend.com/cann/download?versionId=779&ids=d802%2Ch0502%2Ch0602%2Ch0703

https://github.com/Ascend/AscendNPU-IR/blob/master/docs/source/en/introduction/quick_start/installing_guide.md

https://github.com/Ascend/AscendNPU-IR/blob/master/docs/source/en/introduction/quick_start/examples.md

