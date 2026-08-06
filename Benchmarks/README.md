# Large-log benchmark

`large-log.sh` measures the release CLI against deterministic synthetic Xcode build logs. It
records elapsed time, throughput, and peak resident memory while also verifying that the TOON
summary reports a successful build.

Run the 10 MiB pull-request smoke benchmark:

```bash
Benchmarks/large-log.sh 10
```

Run the full size progression used for large-log regression analysis:

```bash
Benchmarks/large-log.sh 10 100 500
```

To benchmark an existing binary without rebuilding, set `XCSIFT_BENCHMARK_BINARY`:

```bash
XCSIFT_BENCHMARK_BINARY=/path/to/xcsift Benchmarks/large-log.sh 10
```

The CSV output is intended for comparison on the same machine. Hosted CI timing and RSS vary too
much for a strict wall-clock gate, so normal XCTest coverage asserts bounded framing and output
correctness instead.

The fixture repeats a representative `CompileSwiftSources` line and appends a successful terminal
marker. This isolates parser throughput; it is not a substitute for checking output equivalence on
a real build log. Reader buffering is bounded, but retained errors and unique-warning deduplication
state still scale with the number of distinct diagnostics.

## Reference results

Recorded on 2026-08-06 using the release build on an arm64 Mac with macOS 26.6 and Swift 6.3.3:

| Nominal input | Elapsed | Throughput | Peak RSS |
| ---: | ---: | ---: | ---: |
| 10 MiB | 4.80 s | 2.08 MiB/s | 8.75 MiB |
| 100 MiB | 44.58 s | 2.24 MiB/s | 8.92 MiB |
| 500 MiB | 226.97 s | 2.20 MiB/s | 8.92 MiB |

For comparison, the pre-streaming `master` binary processed the same 10 MiB fixture in 8.60 s at
1.16 MiB/s with 61.44 MiB peak RSS. On this single-machine run, streaming reduced elapsed time by
44.2% and peak RSS by 85.8%. Treat these numbers as a reference snapshot rather than a portable
performance threshold.
