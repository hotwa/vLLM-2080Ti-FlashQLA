#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LOG_DIR=${LOG_DIR:-"$ROOT/build-logs"}
STAMP=$(date +%Y%m%d-%H%M%S)
LOG="$LOG_DIR/build-$STAMP.log"
TOTAL_STEPS=8
STEP_INDEX=0
BUILD_STARTED_AT=$(date +%s)
VERSION=${VERSION:-0.1.6}

banner() {
  cat <<EOF
============================================================
 vLLM 2080 Ti Definitive Edition v$VERSION
 One-click source build
 Author: github.com/weicj
============================================================
EOF
}

fail() {
  echo
  echo "BUILD FAILED"
  echo "Log: $LOG"
  echo "$*" >&2
  exit 1
}

format_seconds() {
  local seconds=$1
  printf '%02d:%02d:%02d' $((seconds / 3600)) $(((seconds % 3600) / 60)) $((seconds % 60))
}

is_positive_integer() {
  [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]
}

detect_cpu_threads() {
  local threads
  threads=$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)
  if ! is_positive_integer "$threads"; then
    threads=$(nproc 2>/dev/null || true)
  fi
  if ! is_positive_integer "$threads"; then
    threads=4
  fi
  echo "$threads"
}

select_max_jobs() {
  local threads=$1
  if (( threads <= 4 )); then
    echo "$threads"
  else
    echo "$((threads - 2))"
  fi
}

confirm_install() {
  if [[ "${ASSUME_YES:-0}" == "1" || "${YES:-0}" == "1" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    fail "Interactive confirmation is required. Re-run with ASSUME_YES=1 for non-interactive install."
  fi

  cat <<EOF

This script will build and install vLLM 2080 Ti Definitive from source into:
  $ROOT/.venv

Expected time:
  30-60 minutes on a typical dual RTX 2080 Ti host.

Build parallelism:
  CPU threads: $CPU_THREADS
  MAX_JOBS: $MAX_JOBS ($MAX_JOBS_SOURCE)

It will download Python/CUDA dependencies, compile CUDA extensions, and keep
logs under:
  $LOG

Continue? [y/N]:
EOF

  local answer
  while true; do
    read -r answer
    case "$answer" in
      y|Y)
        return 0
        ;;
      n|N|"")
        echo "Build cancelled."
        exit 0
        ;;
      *)
        echo "Please type y to continue or n to exit:"
        ;;
    esac
  done
}

print_step_header() {
  local title=$1
  STEP_INDEX=$((STEP_INDEX + 1))
  echo
  echo "------------------------------------------------------------"
  echo " Step $STEP_INDEX/$TOTAL_STEPS: $title"
  echo "------------------------------------------------------------"
  echo "[$(date '+%F %T')] Step $STEP_INDEX/$TOTAL_STEPS: $title" >> "$LOG"
}

run_with_progress() {
  local title=$1
  shift
  local step_start
  local tmp_status
  local pid
  local rc=0
  local elapsed
  local spinner='|/-\'
  local spin_i=0

  print_step_header "$title"
  step_start=$(date +%s)
  tmp_status=$(mktemp)

  (
    set +e
    "$@" >>"$LOG" 2>&1
    echo $? > "$tmp_status"
  ) &
  pid=$!

  while kill -0 "$pid" >/dev/null 2>&1; do
    elapsed=$(format_seconds "$(( $(date +%s) - step_start ))")
    if [[ -t 1 ]]; then
      printf '\r[%c] %s running... elapsed %s | log: %s' \
        "${spinner:spin_i%${#spinner}:1}" "$title" "$elapsed" "$LOG"
      spin_i=$((spin_i + 1))
      if [[ -s "$LOG" ]]; then
        printf '\n'
        tail -n "${TAIL_LINES:-3}" "$LOG" | sed 's/^/    /'
        printf '\033[%sA' "$(( ${TAIL_LINES:-3} + 1 ))"
      fi
    else
      echo "[$elapsed] $title still running. Log: $LOG"
      if [[ -s "$LOG" ]]; then
        tail -n "${TAIL_LINES:-3}" "$LOG" | sed 's/^/    /'
      fi
    fi
    sleep "${PROGRESS_INTERVAL:-5}"
  done

  wait "$pid" || true
  if [[ -s "$tmp_status" ]]; then
    rc=$(cat "$tmp_status")
  else
    rc=1
  fi
  rm -f "$tmp_status"

  if [[ -t 1 ]]; then
    printf '\r'
    printf '%*s\r' "$(tput cols 2>/dev/null || echo 120)" ''
  fi
  elapsed=$(format_seconds "$(( $(date +%s) - step_start ))")

  if [[ "$rc" == "0" ]]; then
    echo "OK: $title completed in $elapsed"
  else
    echo "FAILED: $title after $elapsed"
    echo
    echo "Last log lines:"
    tail -n 80 "$LOG" || true
    fail "Step failed: $title"
  fi
}

run_step() {
  local title=$1
  shift
  print_step_header "$title"
  "$@" 2>&1 | tee -a "$LOG"
}

banner
mkdir -p "$LOG_DIR"
touch "$LOG"

echo "Build log: $LOG"
echo "Source: $ROOT"

CPU_THREADS=${CPU_THREADS:-$(detect_cpu_threads)}
if ! is_positive_integer "$CPU_THREADS"; then
  fail "CPU_THREADS must be a positive integer when set explicitly."
fi
if [[ -z "${MAX_JOBS:-}" ]]; then
  MAX_JOBS=$(select_max_jobs "$CPU_THREADS")
  MAX_JOBS_SOURCE=auto
else
  is_positive_integer "$MAX_JOBS" || fail "MAX_JOBS must be a positive integer."
  MAX_JOBS_SOURCE=manual
fi
export CPU_THREADS
export MAX_JOBS

confirm_install

cd "$ROOT"

if [[ ! -f pyproject.toml || ! -d vllm ]]; then
  fail "Run this script from the vLLM 2080 Ti Definitive source tree."
fi

if ! command -v nvidia-smi >/dev/null 2>&1; then
  fail "nvidia-smi not found. Install NVIDIA driver first."
fi

if [[ -z "${CUDA_HOME:-}" ]]; then
  if [[ -x /usr/local/cuda-12.8/bin/nvcc ]]; then
    export CUDA_HOME=/usr/local/cuda-12.8
  elif [[ -x /usr/local/cuda/bin/nvcc ]]; then
    export CUDA_HOME=/usr/local/cuda
  else
    fail "CUDA_HOME is not set and nvcc was not found under /usr/local/cuda*."
  fi
fi

if [[ ! -x "$CUDA_HOME/bin/nvcc" ]]; then
  fail "nvcc not found at $CUDA_HOME/bin/nvcc."
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "uv not found; installing uv with the official installer."
  curl -LsSf https://astral.sh/uv/install.sh | sh 2>&1 | tee -a "$LOG"
  export PATH="$HOME/.local/bin:$PATH"
fi

command -v uv >/dev/null 2>&1 || fail "uv install did not put uv on PATH."

export CUDA_PATH="$CUDA_HOME"
export CUDACXX="$CUDA_HOME/bin/nvcc"
export PATH="$ROOT/.venv/bin:$CUDA_HOME/bin:$PATH"
export TORCH_CUDA_ARCH_LIST=${TORCH_CUDA_ARCH_LIST:-7.5}
export CMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE:-Release}
export FLASHINFER_ENABLE_AOT=${FLASHINFER_ENABLE_AOT:-1}

cat <<EOF | tee -a "$LOG"

Build settings:
  CUDA_HOME=$CUDA_HOME
  TORCH_CUDA_ARCH_LIST=$TORCH_CUDA_ARCH_LIST
  CPU_THREADS=$CPU_THREADS
  MAX_JOBS=$MAX_JOBS ($MAX_JOBS_SOURCE)
  CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE
  VENV=$ROOT/.venv
EOF

run_step "GPU summary" nvidia-smi
run_step "CUDA compiler" "$CUDA_HOME/bin/nvcc" --version

if [[ ! -d .venv ]]; then
  run_with_progress "Create Python virtualenv" uv venv --python "${PYTHON_VERSION:-3.11}" .venv
fi

if [[ ! -x .venv/bin/python ]]; then
  fail ".venv/bin/python was not created."
fi

run_with_progress "Upgrade build frontend" uv pip install --python .venv/bin/python -U pip setuptools wheel

if [[ -f requirements/build/cuda.txt ]]; then
  run_with_progress "Install CUDA build requirements" uv pip install --python .venv/bin/python -r requirements/build/cuda.txt --torch-backend=auto
fi

if [[ -f requirements/cuda.txt ]]; then
  run_with_progress "Install CUDA runtime requirements" uv pip install --python .venv/bin/python -r requirements/cuda.txt --torch-backend=auto
fi

run_with_progress "Build and install vLLM 2080 Ti Definitive runtime" \
  env \
    CUDA_HOME="$CUDA_HOME" \
    CUDA_PATH="$CUDA_PATH" \
    CUDACXX="$CUDACXX" \
    TORCH_CUDA_ARCH_LIST="$TORCH_CUDA_ARCH_LIST" \
    MAX_JOBS="$MAX_JOBS" \
    CMAKE_BUILD_TYPE="$CMAKE_BUILD_TYPE" \
    FLASHINFER_ENABLE_AOT="$FLASHINFER_ENABLE_AOT" \
    uv pip install --python .venv/bin/python --no-build-isolation -e .

run_step "Runtime check" .venv/bin/python - <<'PY'
import importlib.util
import torch
import vllm

print(f"vllm={getattr(vllm, '__version__', 'unknown')}")
print(f"torch={torch.__version__}")
print(f"cuda_available={torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"cuda_device_count={torch.cuda.device_count()}")
    for idx in range(torch.cuda.device_count()):
        print(f"cuda_device_{idx}={torch.cuda.get_device_name(idx)}")
print(f"flashinfer_available={importlib.util.find_spec('flashinfer') is not None}")
PY

echo
echo "BUILD OK"
echo "Total elapsed: $(format_seconds "$(( $(date +%s) - BUILD_STARTED_AT ))")"
echo "Log: $LOG"
echo "Next step:"
echo "  ./launcher.sh"
echo
