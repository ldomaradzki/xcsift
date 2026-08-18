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

Select a workload with `XCSIFT_BENCHMARK_PROFILE` (the default is `phase`):

```bash
XCSIFT_BENCHMARK_PROFILE=video-go-shaped Benchmarks/large-log.sh 10 100 500
```

| Profile | Purpose |
| --- | --- |
| `phase` | Phase-heavy parser stress case |
| `fast-reject` | ASCII build-command noise with no reportable event |
| `fast-reject-unicode` | The same rejection path with Unicode input |
| `warning-duplicate` | Repeated compiler warning and deduplication path |
| `warning-unique` | Distinct warning identities and retained-state growth |
| `fixture-mixed` | Repeated sections of the checked-in real build fixture |
| `video-go-shaped` | 0.13% phases, 9.43% warnings, and otherwise build-command noise |

The CSV output is intended for comparison on the same machine. Hosted CI timing and RSS vary too
much for a strict wall-clock gate, so normal XCTest coverage asserts bounded framing and output
correctness instead.

Every profile appends a successful terminal marker. The synthetic profiles isolate specific parser
paths; they are not substitutes for checking output equivalence on real build logs. Reader
buffering is bounded, but retained errors and unique-warning deduplication state still scale with
the number of distinct diagnostics.

## Reference results

Recorded on 2026-08-07 using the release build on an arm64 Mac with macOS 26.6 and Swift 6.3.3.
The primary results are medians of three runs:

| Profile | Nominal input | Elapsed | Throughput | Peak RSS |
| --- | ---: | ---: | ---: | ---: |
| `phase` | 10 MiB | 0.02 s | 500.00 MiB/s | 8.70 MiB |
| `phase` | 100 MiB | 0.18 s | 555.56 MiB/s | 8.75 MiB |
| `phase` | 500 MiB | 0.87 s | 574.71 MiB/s | 8.75 MiB |
| `video-go-shaped` | 10 MiB | 0.02 s | 500.00 MiB/s | 10.28 MiB |
| `video-go-shaped` | 100 MiB | 0.23 s | 434.78 MiB/s | 20.45 MiB |
| `video-go-shaped` | 500 MiB | 1.10 s | 454.55 MiB/s | 20.47 MiB |

Additional single-run 500 MiB checks measured 0.72 s for `fast-reject`, 0.94 s for
`fast-reject-unicode`, 0.63 s for `fixture-mixed`, and 3.41 s for `warning-duplicate`. The
`warning-unique` profile measured 1.36 s and 265.92 MiB RSS at 100 MiB, illustrating that exact
deduplication state grows with distinct diagnostics even though input framing remains bounded.

For comparison, the initial streaming implementation processed the same 500 MiB `phase` workload
in 226.97 s at 2.20 MiB/s with 8.92 MiB peak RSS. The optimized parser completes it in 0.87 s at
574.71 MiB/s with 8.75 MiB peak RSS: about 261 times faster with the same bounded-memory behavior.
Treat these numbers as a reference snapshot rather than a portable performance threshold.
