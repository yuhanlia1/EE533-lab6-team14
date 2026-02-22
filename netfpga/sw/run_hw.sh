#!/usr/bin/env bash
set -euo pipefail

PIP_REG="${1:-./scripts/lab6/pip_reg}"
IMEM_FILE="${2:-imem.hex}"
DMEM_FILE="${3:-dmem.hex}"
RUN_SECS="${4:-0.05}"

DMEM_BASE_WORD="${DMEM_BASE_WORD:-256}"
RESULT_BASE_WORD="${RESULT_BASE_WORD:-180}"
RESULT_LEN="${RESULT_LEN:-6}"

norm_hex32() {
  local x="$1"
  x="${x//_/}"
  x="${x%,}"
  x="${x%:}"
  x="$(printf '%s' "$x" | tr '[:upper:]' '[:lower:]')"
  case "$x" in
    0x*) printf '%s\n' "$x" ;;
    *)   printf '0x%s\n' "$x" ;;
  esac
}

hex_to_dec() {
  local x
  x="$(norm_hex32 "$1")"
  printf "%d" "$((x))"
}

load_mem_file_seq_or_addr() {
  local kind="$1"
  local file="$2"
  local base_word="$3"

  local line a b addr word
  addr="$base_word"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line%%//*}"
    [[ -z "${line//[[:space:]]/}" ]] && continue

    read -r a b <<<"$line" || true

    if [[ -n "${b:-}" ]]; then
      addr="$(hex_to_dec "$a")"
      word="$(norm_hex32 "$b")"
    else
      word="$(norm_hex32 "$a")"
    fi

    if [[ "$kind" == "imem" ]]; then
      "$PIP_REG" imem_write "$(printf "0x%X" "$addr")" "$word"
    else
      "$PIP_REG" dmem_write "$(printf "0x%X" "$addr")" "$word"
    fi

    addr=$((addr + 1))
  done < "$file"
}

echo "[1] freeze"
"$PIP_REG" freeze

echo "[2] load imem from $IMEM_FILE"
load_mem_file_seq_or_addr imem "$IMEM_FILE" 0

echo "[3] load dmem from $DMEM_FILE (base word = $DMEM_BASE_WORD)"
load_mem_file_seq_or_addr dmem "$DMEM_FILE" "$DMEM_BASE_WORD"

echo "[4] unfreeze and run for ${RUN_SECS}s"
"$PIP_REG" unfreeze
sleep "$RUN_SECS"

echo "[5] freeze"
"$PIP_REG" freeze

echo "[6] read results: DMEM[word ${RESULT_BASE_WORD}..$((RESULT_BASE_WORD+RESULT_LEN-1))]"
for ((i=0; i<RESULT_LEN; i++)); do
  a=$((RESULT_BASE_WORD + i))
  "$PIP_REG" dmem_read "$(printf "0x%X" "$a")"
done
