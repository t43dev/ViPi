#!/usr/bin/env bash
# Tests of the HarmonyOS keyboard on Linux, no device needed: KeyboardController.ets and Board.ets run in Node with
# the real Rust core (same NAPI bridge source, built with napi-rs) and a fake text field (harmony/test/mocks).
#   scripts/harmony-test.sh           pipeline tests
#   scripts/harmony-test.sh render    also draw the keyboard into harmony/test/out/*.png
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
t="$here/harmony/test"
cd "$t"
[ -d node_modules/esbuild ] || npm install --no-audit --no-fund >/dev/null
cargo build --release --manifest-path node-addon/Cargo.toml --quiet
mkdir -p out files
cp node-addon/target/release/libvipi.so out/vipi.node
ln -sfn "$here/Resources" files/res-1000
bundle() {
  ./node_modules/.bin/esbuild "$1" --bundle --platform=node --format=cjs --outfile="out/$2" --log-level=warning \
    --resolve-extensions=.ets,.ts,.js --loader:.ets=ts --external:@napi-rs/canvas \
    --alias:@kit.IMEKit=./mocks/ime.ts --alias:@kit.ArkUI=./mocks/arkui.ts --alias:@kit.AbilityKit=./mocks/ability.ts \
    --alias:@kit.BasicServicesKit=./mocks/basic.ts --alias:@kit.InputKit=./mocks/input.ts \
    --alias:@kit.SensorServiceKit=./mocks/sensor.ts --alias:@kit.CoreFileKit=./mocks/file.ts \
    --alias:@kit.PerformanceAnalysisKit=./mocks/perf.ts --alias:@kit.ArkData=./mocks/data.ts \
    --alias:libvipi.so=./mocks/libvipi.ts
}
bundle pipeline.test.ts pipeline.js
VIPI_NODE="$t/out/vipi.node" FILES_DIR="$t/files" node out/pipeline.js
if [ "${1:-}" = render ]; then
  bundle render.ts render.js
  (cd out && VIPI_NODE="$t/out/vipi.node" node render.js)
fi
