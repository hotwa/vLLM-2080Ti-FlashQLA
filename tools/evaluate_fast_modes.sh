#!/usr/bin/env bash
set -euo pipefail

ROOT=${ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}
REMOTE_HOST=${REMOTE_HOST:-root@192.168.1.40}
REMOTE_ROOT=${REMOTE_ROOT:-/data/stable/vllm-sm75-tp2-cu128}
REMOTE_USER=${REMOTE_USER:-dietpi}
GPU_DEVICES=${GPU_DEVICES:-1,2}
PORT=${PORT:-19447}
PROMPT_TOKENS=${PROMPT_TOKENS:-4096}
GEN_TOKENS=${GEN_TOKENS:-128}
WARMUPS=${WARMUPS:-1}
MEASURED_RUNS=${MEASURED_RUNS:-3}
FAST_MARGIN=${FAST_MARGIN:-1.0}
FAST_ONLY=${FAST_ONLY:-1}
BASELINE_RESULT_DIR=${BASELINE_RESULT_DIR:-}
CASE_FILTER=${CASE_FILTER:-}
SPEC_SYNC_OVERRIDE=${SPEC_SYNC_OVERRIDE:-}
MTP_OVERRIDE=${MTP_OVERRIDE:-}
FAST_COMPARE_REQUIRED=${FAST_COMPARE_REQUIRED:-1}
RESULT_STAMP=${RESULT_STAMP:-$(date +%Y%m%d-%H%M%S)}
REMOTE_RESULT_DIR=${REMOTE_RESULT_DIR:-$REMOTE_ROOT/results/fast_mode_evaluator_$RESULT_STAMP}

FP8_MODEL_DIR=${FP8_MODEL_DIR:-/data/models/vllm/qwen-family-27b-fp8}
INT4_MODEL_DIR=${INT4_MODEL_DIR:-/data/models/vllm/qwen-family-27b-gptq-int4}

if [[ "$(id -u)" == "0" ]]; then
  SSH=(runuser -u max -- ssh)
  RSYNC=(runuser -u max -- rsync)
else
  SSH=(ssh)
  RSYNC=(rsync)
fi

run_ssh() {
  "${SSH[@]}" -o ConnectTimeout=10 "$REMOTE_HOST" "$@"
}

sync_runtime() {
  if [[ "${EVAL_SYNC:-1}" != "1" ]]; then
    return 0
  fi

  "${RSYNC[@]}" -a --delete "$ROOT/profiles/" "$REMOTE_HOST:$REMOTE_ROOT/profiles/"
  "${RSYNC[@]}" -a --delete "$ROOT/tools/" "$REMOTE_HOST:$REMOTE_ROOT/tools/"
  (
    cd "$ROOT"
    "${RSYNC[@]}" -aR \
      launcher.sh \
      build.sh \
      vllm/config/compilation.py \
      vllm/envs.py \
      vllm/v1/attention/ops/triton_unified_attention.py \
      vllm/v1/worker/gpu_model_runner.py \
      "$REMOTE_HOST:$REMOTE_ROOT/"
  )

  run_ssh "chown -R $REMOTE_USER:$REMOTE_USER '$REMOTE_ROOT/profiles' '$REMOTE_ROOT/tools' '$REMOTE_ROOT/launcher.sh' '$REMOTE_ROOT/build.sh' '$REMOTE_ROOT/vllm/config/compilation.py' '$REMOTE_ROOT/vllm/envs.py' '$REMOTE_ROOT/vllm/v1/attention/ops/triton_unified_attention.py' '$REMOTE_ROOT/vllm/v1/worker/gpu_model_runner.py'"

  run_ssh "REMOTE_ROOT='$REMOTE_ROOT' REMOTE_USER='$REMOTE_USER' bash -s" <<'REMOTE_SYNC'
set -euo pipefail
site_packages=$(runuser -u "$REMOTE_USER" -- "$REMOTE_ROOT/.venv/bin/python" - <<'PY'
import sysconfig
print(sysconfig.get_paths()["purelib"])
PY
)
site_vllm="$site_packages/vllm"
if [[ -d "$site_vllm" ]]; then
  install -o "$REMOTE_USER" -g "$REMOTE_USER" -m 0644 \
    "$REMOTE_ROOT/vllm/config/compilation.py" \
    "$site_vllm/config/compilation.py"
  install -o "$REMOTE_USER" -g "$REMOTE_USER" -m 0644 \
    "$REMOTE_ROOT/vllm/envs.py" \
    "$site_vllm/envs.py"
  install -o "$REMOTE_USER" -g "$REMOTE_USER" -m 0644 \
    "$REMOTE_ROOT/vllm/v1/attention/ops/triton_unified_attention.py" \
    "$site_vllm/v1/attention/ops/triton_unified_attention.py"
  install -o "$REMOTE_USER" -g "$REMOTE_USER" -m 0644 \
    "$REMOTE_ROOT/vllm/v1/worker/gpu_model_runner.py" \
    "$site_vllm/v1/worker/gpu_model_runner.py"
fi
REMOTE_SYNC
}

sync_runtime

run_ssh \
  "REMOTE_ROOT='$REMOTE_ROOT' REMOTE_USER='$REMOTE_USER' GPU_DEVICES='$GPU_DEVICES' PORT='$PORT' PROMPT_TOKENS='$PROMPT_TOKENS' GEN_TOKENS='$GEN_TOKENS' WARMUPS='$WARMUPS' MEASURED_RUNS='$MEASURED_RUNS' FAST_MARGIN='$FAST_MARGIN' FAST_ONLY='$FAST_ONLY' BASELINE_RESULT_DIR='$BASELINE_RESULT_DIR' CASE_FILTER='$CASE_FILTER' SPEC_SYNC_OVERRIDE='$SPEC_SYNC_OVERRIDE' MTP_OVERRIDE='$MTP_OVERRIDE' FAST_COMPARE_REQUIRED='$FAST_COMPARE_REQUIRED' REMOTE_RESULT_DIR='$REMOTE_RESULT_DIR' FP8_MODEL_DIR='$FP8_MODEL_DIR' INT4_MODEL_DIR='$INT4_MODEL_DIR' bash -s" <<'REMOTE'
set -euo pipefail

cd "$REMOTE_ROOT"
mkdir -p "$REMOTE_RESULT_DIR"
chown -R "$REMOTE_USER:$REMOTE_USER" "$REMOTE_RESULT_DIR"

read_profile_value() {
  local file=$1
  local key=$2
  awk -F= -v key="$key" '
    $1 == key {
      value = substr($0, index($0, "=") + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", value)
      gsub(/^'\''|'\''$/, "", value)
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  ' "$file"
}

sanitize() {
  printf '%s' "$1" | tr '/ ' '__' | tr -c 'A-Za-z0-9_.-' '_'
}

stop_runtime_vllm() {
  local pid_file pid cmd
  while IFS= read -r pid_file; do
    [[ -n "$pid_file" ]] || continue
    pid=$(cat "$pid_file" 2>/dev/null || true)
    if [[ -n "$pid" && -d "/proc/$pid" ]]; then
      cmd=$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)
      if [[ "$cmd" == *"$REMOTE_ROOT/.venv/bin/python -m vllm.entrypoints.openai.api_server"* ]]; then
        kill "$pid" 2>/dev/null || true
      fi
    fi
    rm -f "$pid_file"
  done < <(find "$REMOTE_ROOT/run-logs" -maxdepth 1 -type f -name '*.pid' -print 2>/dev/null | sort)

  sleep 2
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    kill -TERM "$pid" 2>/dev/null || true
  done < <(pgrep -f "$REMOTE_ROOT/.venv/bin/python -m vllm.entrypoints.openai.api_server" || true)
}

trap stop_runtime_vllm EXIT

make_eval_profile() {
  local rel=$1
  local mode=$2
  local out=$3
  cp "$REMOTE_ROOT/profiles/$rel" "$out"
  if grep -q '^COMPATIBLE_MODES=' "$out"; then
    sed -i 's/^COMPATIBLE_MODES=.*/COMPATIBLE_MODES=safe,normal,fast/' "$out"
  else
    printf '\nCOMPATIBLE_MODES=safe,normal,fast\n' >>"$out"
  fi
  if [[ -n "$MTP_OVERRIDE" ]]; then
    if grep -q '^MTP_K=' "$out"; then
      sed -i "s/^MTP_K=.*/MTP_K=$MTP_OVERRIDE/" "$out"
    else
      printf 'MTP_K=%s\n' "$MTP_OVERRIDE" >>"$out"
    fi
  fi
  if [[ "$mode" == "safe" ]]; then
    case "$(read_profile_value "$out" KV_CACHE_DTYPE)" in
      ""|fp16|default|auto) ;;
      *) sed -i 's/^MTP_K=.*/MTP_K=0/' "$out" ;;
    esac
  fi
}

run_one_case() {
  local group=$1
  local profile=$2
  local model_dir=$3
  local mode=$4
  local role=$5
  local threshold=$6

  local case_id case_dir tmp_profile served_name out_json launch_out launch_err label i
  case_id=$(sanitize "${group}_${mode}")
  case_dir="$REMOTE_RESULT_DIR/$case_id"
  mkdir -p "$case_dir"
  chown -R "$REMOTE_USER:$REMOTE_USER" "$case_dir"
  tmp_profile="$case_dir/profile.env"
  make_eval_profile "$profile" "$mode" "$tmp_profile"
  chown "$REMOTE_USER:$REMOTE_USER" "$tmp_profile"
  served_name=$(read_profile_value "$tmp_profile" SERVED_NAME)
  out_json="$case_dir/pp${PROMPT_TOKENS}_tg${GEN_TOKENS}.jsonl"
  launch_out="$case_dir/launch.out"
  launch_err="$case_dir/launch.err"
  : >"$launch_out"
  : >"$launch_err"
  : >"$case_dir/bench.out"
  : >"$case_dir/bench.err"
  chown "$REMOTE_USER:$REMOTE_USER" \
    "$launch_out" "$launch_err" "$case_dir/bench.out" "$case_dir/bench.err"

  stop_runtime_vllm

  {
    printf 'group\t%s\nprofile\t%s\nmode\t%s\nrole\t%s\nthreshold\t%s\nmodel_dir\t%s\nserved_name\t%s\n' \
      "$group" "$profile" "$mode" "$role" "$threshold" "$model_dir" "$served_name"
  } >"$case_dir/meta.tsv"
  chown "$REMOTE_USER:$REMOTE_USER" "$case_dir/meta.tsv"

  if ! runuser -u "$REMOTE_USER" -- bash -lc \
    "cd '$REMOTE_ROOT' && MODEL_DIR='$model_dir' PROFILE_FILE='$tmp_profile' MODE='$mode' VLLM_SM75_SPEC_SYNC_MODE_OVERRIDE='$SPEC_SYNC_OVERRIDE' GPU_DEVICES='$GPU_DEVICES' PORT='$PORT' SERVICE_SCOPE=local NON_INTERACTIVE=1 START_TIMEOUT=900 ./launcher.sh --non-interactive" \
    >>"$launch_out" 2>>"$launch_err"; then
    printf 'launch_failed\n' >"$case_dir/status"
    chown "$REMOTE_USER:$REMOTE_USER" "$case_dir/status"
    return 0
  fi

  for ((i = 0; i < WARMUPS + MEASURED_RUNS; i += 1)); do
    if (( i < WARMUPS )); then
      label="${case_id}-warmup$((i + 1))"
    else
      label="${case_id}-run$((i - WARMUPS + 1))"
    fi
    runuser -u "$REMOTE_USER" -- bash -lc \
      "cd '$REMOTE_ROOT' && .venv/bin/python tools/profile_request.py --model-dir '$model_dir' --served-name '$served_name' --base-url 'http://127.0.0.1:$PORT/v1' --endpoint completions --prompt-tokens '$PROMPT_TOKENS' --gen-tokens '$GEN_TOKENS' --label '$label' --out '$out_json' --ignore-eos --pure-filler" \
      >>"$case_dir/bench.out" 2>>"$case_dir/bench.err" || true
  done

  printf 'measured\n' >"$case_dir/status"
  chown -R "$REMOTE_USER:$REMOTE_USER" "$case_dir"
  stop_runtime_vllm
}

all_cases_file="$REMOTE_RESULT_DIR/all_cases.tsv"
cases_file="$REMOTE_RESULT_DIR/cases.tsv"
cat >"$all_cases_file" <<CASES
group	profile	model_dir	mode	role	threshold
fp8_fp16kv	qwen27b/fast/fp8/fp16kv-96K-mtp3-text-only.env	$FP8_MODEL_DIR	safe	fp16_compare	0
fp8_fp16kv	qwen27b/fast/fp8/fp16kv-96K-mtp3-text-only.env	$FP8_MODEL_DIR	normal	fp16_compare	0
fp8_fp16kv	qwen27b/fast/fp8/fp16kv-96K-mtp3-text-only.env	$FP8_MODEL_DIR	fast	fp16_compare	0
int4_fp16kv	qwen27b/fast/int4/fp16kv-250K-mtp3-text-only.env	$INT4_MODEL_DIR	safe	fp16_compare	0
int4_fp16kv	qwen27b/fast/int4/fp16kv-250K-mtp3-text-only.env	$INT4_MODEL_DIR	normal	fp16_compare	0
int4_fp16kv	qwen27b/fast/int4/fp16kv-250K-mtp3-text-only.env	$INT4_MODEL_DIR	fast	fp16_compare	0
fp8_int8kv	qwen27b/fast/fp8/int8kv-256K-mtp3-text-only.env	$FP8_MODEL_DIR	fast	fast_guard	70
int4_int8kv	qwen27b/fast/int4/int8kv-256K-mtp3-text-only.env	$INT4_MODEL_DIR	fast	fast_guard	90
CASES

if [[ -f "$REMOTE_ROOT/profiles/qwen27b/experimental/fp8/tqk8v4-256K-mtp3-text-only.env" ]]; then
  printf 'fp8_tqk8v4\tqwen27b/experimental/fp8/tqk8v4-256K-mtp3-text-only.env\t%s\tfast\tfast_guard\t65\n' "$FP8_MODEL_DIR" >>"$all_cases_file"
fi

if [[ "$FAST_ONLY" == "1" ]]; then
  awk -F'\t' 'NR == 1 || $4 == "fast"' "$all_cases_file" >"$cases_file"
else
  cp "$all_cases_file" "$cases_file"
fi

if [[ -n "$CASE_FILTER" ]]; then
  awk -F'\t' -v pat="$CASE_FILTER" '
    NR == 1 {
      print
      next
    }
    ($1 "\t" $2 "\t" $4) ~ pat
  ' "$cases_file" >"$cases_file.filtered"
  mv "$cases_file.filtered" "$cases_file"
fi

tail -n +2 "$cases_file" | while IFS=$'\t' read -r group profile model_dir mode role threshold; do
  run_one_case "$group" "$profile" "$model_dir" "$mode" "$role" "$threshold"
done

runuser -u "$REMOTE_USER" -- "$REMOTE_ROOT/.venv/bin/python" - "$REMOTE_RESULT_DIR" "$FAST_MARGIN" "$FAST_ONLY" "$BASELINE_RESULT_DIR" "$MEASURED_RUNS" "$FAST_COMPARE_REQUIRED" <<'PY'
import csv
import json
import statistics
import sys
from pathlib import Path

root = Path(sys.argv[1])
margin = float(sys.argv[2])
fast_only = sys.argv[3] == "1"
baseline_root = Path(sys.argv[4]) if sys.argv[4] else None
expected_runs = int(sys.argv[5])
fast_compare_required = sys.argv[6] == "1"

def valid_filler(sample: str) -> bool:
    lower = sample.lower()
    return " the the the the" in lower and "climate change" not in lower and "introduction" not in lower

def read_baseline_targets(root: Path | None) -> dict[str, float]:
    if root is None:
        return {}
    summary = root / "summary.tsv"
    if not summary.exists():
        return {}

    by_group = {}
    with summary.open(encoding="utf-8") as fh:
        for row in csv.DictReader(fh, delimiter="\t"):
            if row.get("role") != "fp16_compare":
                continue
            if row.get("mode") not in ("safe", "normal"):
                continue
            decode = row.get("decode_median")
            if not decode:
                continue
            by_group.setdefault(row["group"], []).append(float(decode))
    return {group: max(values) + margin for group, values in by_group.items()}

cases = []
with (root / "cases.tsv").open(encoding="utf-8") as fh:
    for row in csv.DictReader(fh, delimiter="\t"):
        cases.append(row)

rows = []
failures = []
by_group = {}
baseline_targets = read_baseline_targets(baseline_root)

for case in cases:
    case_id = f"{case['group']}_{case['mode']}".replace("/", "_").replace(" ", "_")
    case_id = "".join(ch if ch.isalnum() or ch in "_.-" else "_" for ch in case_id)
    case_dir = root / case_id
    status = (case_dir / "status").read_text(encoding="utf-8", errors="ignore").strip() if (case_dir / "status").exists() else "missing"
    jsonl = case_dir / "pp4096_tg128.jsonl"
    records = []
    if jsonl.exists():
        for line in jsonl.read_text(encoding="utf-8", errors="ignore").splitlines():
            if not line.strip():
                continue
            item = json.loads(line)
            if "-run" in item.get("label", ""):
                records.append(item)

    prefill = [float(r["prefill_tok_s"]) for r in records if r.get("prefill_tok_s") is not None]
    decode = [float(r["decode_tok_s"]) for r in records if r.get("decode_tok_s") is not None]
    chunks = [float(r["chunks"]) for r in records if r.get("chunks") is not None]
    samples = [str(r.get("content_sample", "")) for r in records]
    row = {
        **case,
        "status": status,
        "runs": str(len(records)),
        "prefill_median": f"{statistics.median(prefill):.2f}" if prefill else "",
        "decode_median": f"{statistics.median(decode):.2f}" if decode else "",
        "chunks_median": f"{statistics.median(chunks):.2f}" if chunks else "",
        "filler_valid": str(bool(samples) and all(valid_filler(s) for s in samples)),
        "baseline_target": (
            f"{baseline_targets[case['group']]:.2f}"
            if case["group"] in baseline_targets
            else ""
        ),
        "result": str(jsonl),
    }
    rows.append(row)
    by_group.setdefault(case["group"], {})[case["mode"]] = row

    if status != "measured" or len(records) < expected_runs:
        failures.append(f"{case['group']} {case['mode']}: incomplete status={status} runs={len(records)}")
    if row["filler_valid"] != "True":
        failures.append(f"{case['group']} {case['mode']}: filler output drift")

compare_groups = sorted({case["group"] for case in cases if case.get("role") == "fp16_compare"})
for group in compare_groups:
    modes = by_group.get(group, {})
    if not fast_compare_required and "fast" not in modes:
        continue
    if "fast" not in modes or not modes["fast"]["decode_median"]:
        failures.append(f"{group}: missing fast decode median")
        continue
    fast = float(modes["fast"]["decode_median"])
    if fast_only:
        target = baseline_targets.get(group)
        if target is None:
            failures.append(f"{group}: missing baseline safe/normal target")
            continue
    else:
        if not all(mode in modes and modes[mode]["decode_median"] for mode in ("safe", "normal", "fast")):
            failures.append(f"{group}: missing safe/normal/fast decode medians")
            continue
        safe = float(modes["safe"]["decode_median"])
        normal = float(modes["normal"]["decode_median"])
        target = max(safe, normal) + margin
    if fast < target:
        failures.append(f"{group}: fast decode {fast:.2f} < target {target:.2f}")

for row in rows:
    if row["role"] != "fast_guard":
        continue
    if not row["decode_median"]:
        failures.append(f"{row['group']}: missing fast guard decode")
        continue
    threshold = float(row["threshold"])
    decode = float(row["decode_median"])
    if decode < threshold:
        failures.append(f"{row['group']}: fast guard decode {decode:.2f} < threshold {threshold:.2f}")

summary = root / "summary.tsv"
fieldnames = [
    "group",
    "profile",
    "mode",
    "role",
    "threshold",
    "status",
    "runs",
    "prefill_median",
    "decode_median",
    "chunks_median",
    "filler_valid",
    "baseline_target",
    "result",
]
with summary.open("w", encoding="utf-8", newline="") as fh:
    writer = csv.DictWriter(fh, fieldnames=fieldnames, delimiter="\t")
    writer.writeheader()
    for row in rows:
        writer.writerow({key: row.get(key, "") for key in fieldnames})

verdict = root / "verdict.txt"
if failures:
    verdict.write_text("FAIL\n" + "\n".join(failures) + "\n", encoding="utf-8")
    print(f"FAIL {root}")
    print(verdict.read_text(encoding="utf-8"))
    sys.exit(1)

verdict.write_text("PASS\n", encoding="utf-8")
print(f"PASS {root}")
PY
REMOTE

echo "Remote result: $REMOTE_RESULT_DIR"
