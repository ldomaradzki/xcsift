#!/usr/bin/env bash

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/.." && pwd)
benchmark_root=$(mktemp -d "${TMPDIR:-/tmp}/xcsift-large-log.XXXXXX")
trap 'rm -rf -- "$benchmark_root"' EXIT

if [ -n "${XCSIFT_BENCHMARK_BINARY:-}" ]; then
  xcsift_binary=$XCSIFT_BENCHMARK_BINARY
else
  (cd "$repository_root" && swift build -c release >/dev/null)
  xcsift_binary="$repository_root/.build/release/xcsift"
fi

if [ ! -x "$xcsift_binary" ]; then
  echo "error: xcsift binary is not executable: $xcsift_binary" >&2
  exit 1
fi

if [ "$#" -gt 0 ]; then
  sizes_mib="$*"
else
  sizes_mib="10 100 500"
fi

profile=${XCSIFT_BENCHMARK_PROFILE:-phase}

generate_input() {
  local requested_bytes=$1
  local generated_path=$2

  case "$profile" in
    phase)
      yes "CompileSwiftSources normal arm64 /tmp/Foo.swift (in target 'VideoGo' from project 'VideoGo')" \
        | head -c "$requested_bytes" >"$generated_path"
      ;;
    fast-reject)
      yes "    cd /Users/runner/work/VideoGo/VideoGo && /usr/bin/touch /private/tmp/DerivedData/VideoGo/Build/Intermediates.noindex/stamp" \
        | head -c "$requested_bytes" >"$generated_path"
      ;;
    fast-reject-unicode)
      yes "    cd /Users/runner/work/VideoGo/构建路径 && /usr/bin/touch /private/tmp/DerivedData/VideoGo/Build/Intermediates.noindex/stamp" \
        | head -c "$requested_bytes" >"$generated_path"
      ;;
    warning-duplicate)
      yes "/tmp/VideoGo/Sources/Foo.swift:42:7: warning: immutable value 'value' was never used" \
        | head -c "$requested_bytes" >"$generated_path"
      ;;
    warning-unique)
      awk -v target="$requested_bytes" '
        BEGIN {
          bytes = 0
          for (i = 1; bytes < target; i++) {
            line = sprintf("/tmp/VideoGo/Sources/File%d.swift:%d:7: warning: unique diagnostic number %d", i % 10000, i % 500 + 1, i)
            print line
            bytes += length(line) + 1
          }
        }
      ' >"$generated_path"
      ;;
    fixture-mixed)
      while :; do
        sed '$d' "$repository_root/Tests/XCSiftCoreTests/Fixtures/build.txt"
      done | head -c "$requested_bytes" >"$generated_path"
      ;;
    video-go-shaped)
      awk -v target="$requested_bytes" '
        BEGIN {
          bytes = 0
          quote = sprintf("%c", 39)
          for (i = 0; bytes < target; i++) {
            slot = i % 10000
            if (slot < 13) {
              line = "CompileSwiftSources normal arm64 /tmp/Foo.swift (in target " \
                quote "VideoGo" quote " from project " quote "VideoGo" quote ")"
            } else if (slot < 956) {
              line = sprintf("/tmp/VideoGo/Sources/File%d.swift:%d:7: warning: repeated diagnostic group %d", i % 1024, i % 500 + 1, i % 1024)
            } else {
              line = "    cd /Users/runner/work/VideoGo/VideoGo && /usr/bin/touch " \
                "/private/tmp/DerivedData/VideoGo/Build/Intermediates.noindex/generated-stamp"
            }
            print line
            bytes += length(line) + 1
          }
        }
      ' >"$generated_path"
      ;;
    *)
      echo "error: unknown benchmark profile: $profile" >&2
      exit 1
      ;;
  esac

  printf '\n** BUILD SUCCEEDED **\n' >>"$generated_path"
}

printf 'profile,size_mib,bytes,elapsed_seconds,throughput_mib_per_second,peak_rss_mib\n'

for size_mib in $sizes_mib; do
  input_path="$benchmark_root/input-${size_mib}m.log"
  output_path="$benchmark_root/output-${size_mib}m.toon"
  metrics_path="$benchmark_root/metrics-${size_mib}m.txt"
  requested_bytes=$((size_mib * 1024 * 1024))

  generate_input "$requested_bytes" "$input_path"

  if [ "$(uname -s)" = "Darwin" ]; then
    /usr/bin/time -lp "$xcsift_binary" -f toon <"$input_path" >"$output_path" 2>"$metrics_path"
    elapsed_seconds=$(awk '$1 == "real" { print $2 }' "$metrics_path")
    peak_rss_bytes=$(awk '/maximum resident set size/ { print $1 }' "$metrics_path")
    peak_rss_mib=$(awk -v bytes="$peak_rss_bytes" 'BEGIN { printf "%.2f", bytes / 1048576 }')
  else
    /usr/bin/time -f 'elapsed_seconds=%e\npeak_rss_kib=%M' \
      "$xcsift_binary" -f toon <"$input_path" >"$output_path" 2>"$metrics_path"
    elapsed_seconds=$(awk -F= '$1 == "elapsed_seconds" { print $2 }' "$metrics_path")
    peak_rss_kib=$(awk -F= '$1 == "peak_rss_kib" { print $2 }' "$metrics_path")
    peak_rss_mib=$(awk -v kib="$peak_rss_kib" 'BEGIN { printf "%.2f", kib / 1024 }')
  fi

  if ! grep -q '^status: success$' "$output_path"; then
    echo "error: benchmark output did not report success for ${size_mib} MiB" >&2
    exit 1
  fi

  actual_bytes=$(wc -c <"$input_path" | tr -d ' ')
  throughput=$(awk -v bytes="$actual_bytes" -v seconds="$elapsed_seconds" \
    'BEGIN { if (seconds > 0) printf "%.2f", (bytes / 1048576) / seconds; else printf "n/a" }')

  printf '%s,%s,%s,%s,%s,%s\n' \
    "$profile" "$size_mib" "$actual_bytes" "$elapsed_seconds" "$throughput" "$peak_rss_mib"
done
