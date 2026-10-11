#!/usr/bin/env bash
#
# spec-review.sh — 方案審查：讓 Codex 以唯讀模式審查 spec
#
# 流程：
#   1. 檢查 spec 是否可審（無殘留模板提示、有驗收標準、有驗證指令）
#   2. 組裝材料：spec、（第 2 輪起）上一輪的 Codex 意見與 Claude 的回應紀錄
#   3. 以唯讀沙盒執行 `codex exec`，並「強制」使用指定的推理強度（預設 ultra）
#   4. 檢查 codex 實際採用的推理強度；與要求不符就中止，不計入輪次
#   5. 寫入 docs/spec-reviews/<task>-p<N>-codex.md，依第一行 VERDICT 回傳 exit code
#
# 之後由 Claude Code 的 /spec-respond 依意見修改，直到收斂，再由你用 /spec-approve 核准。
# 相容 bash 3.2（macOS 預設）以上。
#
set -euo pipefail

# ---------- exit codes ----------
EX_APPROVE=0   # Codex 認為可進入實作
EX_CHANGES=1   # Codex 要求修改（review 已寫出）
EX_ERROR=2     # 用法、環境或工具錯誤（含推理強度未生效）
EX_LINT=3      # spec 尚不可審（未填完）
EX_ROUNDS=4    # 已超過最大輪數

# ---------- 可用環境變數覆寫的設定 ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPEC_DIR="${SPEC_DIR:-docs/specs}"
SPEC_REVIEW_DIR="${SPEC_REVIEW_DIR:-docs/spec-reviews}"
SPEC_PROMPT_TEMPLATE="${SPEC_PROMPT_TEMPLATE:-$SCRIPT_DIR/spec-review-prompt.md}"
SPEC_MAX_ROUNDS="${SPEC_MAX_ROUNDS:-3}"
CODEX_BIN="${CODEX_BIN:-codex}"
CODEX_MODEL="${CODEX_MODEL:-}"
CODEX_EXTRA_ARGS="${CODEX_EXTRA_ARGS:-}"
# 推理強度：未設定 → ultra；設為空字串 → 不強制（沿用 codex 自己的設定）
CODEX_REASONING_EFFORT="${CODEX_REASONING_EFFORT-ultra}"
# 實際強度與要求不符時預設中止；設 1 則只警告
CODEX_ALLOW_DOWNGRADE="${CODEX_ALLOW_DOWNGRADE:-0}"

# ---------- 輸出 helpers ----------
if [[ -t 2 ]]; then
  C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_0=$'\033[0m'
else
  C_G=""; C_Y=""; C_R=""; C_0=""
fi
info() { printf '%s[spec-review]%s %s\n' "$C_G" "$C_0" "$*" >&2; }
warn() { printf '%s[spec-review]%s %s\n' "$C_Y" "$C_0" "$*" >&2; }
err()  { printf '%s[spec-review]%s %s\n' "$C_R" "$C_0" "$*" >&2; }
die()  { err "$*"; exit "$EX_ERROR"; }

usage() {
  cat <<'EOF'
用法: spec-review.sh <task> [選項]

  <task>                  任務代號，對應 docs/specs/<task>.md

選項:
  -r, --round <n>         手動指定輪次（預設：依 docs/spec-reviews 內既有檔案自動遞增）
  -f, --force             略過「上一輪尚未產出回應紀錄」的檢查
  -h, --help              顯示說明

環境變數:
  SPEC_DIR, SPEC_REVIEW_DIR   spec 與審查紀錄目錄（預設 docs/specs、docs/spec-reviews）
  SPEC_MAX_ROUNDS             最大審查輪數（預設 3）
  CODEX_BIN                   codex 執行檔（預設 codex）
  CODEX_MODEL                 指定模型（-m）
  CODEX_REASONING_EFFORT      推理強度（預設 ultra；設為空字串則不強制）
  CODEX_ALLOW_DOWNGRADE       設 1：實際強度與要求不符時只警告，不中止
  CODEX_EXTRA_ARGS            額外傳給 `codex exec` 的參數（以空白分隔）
  SPEC_PROMPT_TEMPLATE        審查 prompt 模板路徑

Exit code:
  0 APPROVE | 1 REQUEST_CHANGES | 2 錯誤 | 3 spec 尚不可審 | 4 超過最大輪數
EOF
}

need_arg() { [[ $# -ge 2 && -n "${2:-}" ]] || die "選項 $1 需要參數"; }

# ---------- 解析參數 ----------
TASK=""; ROUND=""; FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--round) need_arg "$@"; ROUND="$2"; shift 2 ;;
    -f|--force) FORCE=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    -*)         die "未知選項: $1（用 --help 查看用法）" ;;
    *)          [[ -z "$TASK" ]] || die "只能指定一個任務代號"; TASK="$1"; shift ;;
  esac
done

if [[ -z "$TASK" ]]; then usage >&2; exit "$EX_ERROR"; fi
[[ "$TASK" =~ ^[A-Za-z0-9._-]+$ ]] || die "任務代號只能包含英數字與 . _ -"
if [[ -n "$CODEX_REASONING_EFFORT" ]]; then
  [[ "$CODEX_REASONING_EFFORT" =~ ^[A-Za-z0-9_-]+$ ]] || die "CODEX_REASONING_EFFORT 只能包含英數字與 _ -"
fi

# ---------- 環境檢查 ----------
command -v git >/dev/null 2>&1 || die "找不到 git"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "請在 git repo 內執行（Codex 需要讀取專案程式碼）"
cd "$(git rev-parse --show-toplevel)"
command -v "$CODEX_BIN" >/dev/null 2>&1 || die "找不到 $CODEX_BIN（可用 CODEX_BIN 指定路徑）"

SPEC="$SPEC_DIR/$TASK.md"
[[ -f "$SPEC" ]] || die "找不到 spec: $SPEC"
[[ -f "$SPEC_PROMPT_TEMPLATE" ]] || die "找不到 prompt 模板: $SPEC_PROMPT_TEMPLATE"

# ---------- 決定輪次 ----------
mkdir -p "$SPEC_REVIEW_DIR"
if [[ -z "$ROUND" ]]; then
  shopt -s nullglob
  existing=("$SPEC_REVIEW_DIR/$TASK"-p[0-9]*-codex.md)
  shopt -u nullglob
  ROUND=$(( ${#existing[@]} + 1 ))
fi
[[ "$ROUND" =~ ^[0-9]+$ && "$ROUND" -ge 1 ]] || die "輪次必須是正整數"
PREV_ROUND=$(( ROUND - 1 ))

if (( ROUND > SPEC_MAX_ROUNDS )); then
  warn "已進行 $PREV_ROUND 輪方案審查，超過上限 $SPEC_MAX_ROUNDS。"
  warn "反覆無法收斂，通常代表需求本身不夠清楚，或雙方卡在品味差異。"
  warn "建議由你直接裁決：把決定告訴 Claude 並記入 §8.1，然後用 /spec-approve 核准；"
  warn "若仍要多審一輪，請加 --round 指定輪次並調高 SPEC_MAX_ROUNDS。"
  exit "$EX_ROUNDS"
fi

# ---------- 1. 檢查 spec 是否可審 ----------
extract_verify_cmds() {
  awk '
    /^##[[:space:]]+.*驗證指令/ { in_sec = 1; next }
    in_sec && /^##[[:space:]]/   { exit }
    in_sec && /^```/             { if (in_block) exit; in_block = 1; next }
    in_sec && in_block           { print }
  ' "$1"
}

lint_spec() {
  local f="$1" bad=0 m cmds
  for m in '<任務標題>' '`<task>`' '<條件>' '<決議內容>' '<path/to/file>'; do
    if grep -qF -- "$m" "$f"; then
      err "spec 仍含有未填寫的模板提示：$m"; bad=1
    fi
  done
  if ! grep -qE '\*\*AC-[0-9]+\*\*' "$f"; then
    err "spec 找不到任何驗收標準（格式：**AC-1**：…）"; bad=1
  fi
  cmds="$(extract_verify_cmds "$f")"
  if [[ -z "${cmds//[[:space:]]/}" ]]; then
    err "spec 第 6 節沒有驗證指令的程式碼區塊"; bad=1
  fi
  return "$bad"
}

lint_spec "$SPEC" || { err "spec 尚不可審，請先補完（本輪不計入）。"; exit "$EX_LINT"; }

if grep -qiE '^\|[[:space:]]*狀態[[:space:]]*\|.*(approved|implemented)[[:space:]]*\|?[[:space:]]*$' "$SPEC"; then
  warn "spec 的狀態已是 approved / implemented，確定還要再做方案審查嗎？"
fi

# ---------- 2. 第 2 輪起的前置檢查 ----------
PREV_REVIEW="$SPEC_REVIEW_DIR/$TASK-p$PREV_ROUND-codex.md"
PREV_RESOLUTION="$SPEC_REVIEW_DIR/$TASK-p$PREV_ROUND-resolution.md"
if (( ROUND > 1 )); then
  [[ -f "$PREV_REVIEW" ]] || die "找不到上一輪的 Codex 審查：$PREV_REVIEW（可用 --round 手動指定）"
  if [[ ! -f "$PREV_RESOLUTION" && $FORCE -eq 0 ]]; then
    err "找不到上一輪的回應紀錄：$PREV_RESOLUTION"
    err "請先在 Claude Code 執行 /spec-respond $TASK（它會把你的口頭意見也記下來，Codex 才看得到）。"
    err "若確定要略過，請加 --force。"
    exit "$EX_ERROR"
  fi
  if [[ -f "$PREV_RESOLUTION" && "$SPEC" -ot "$PREV_REVIEW" ]]; then
    warn "spec 的修改時間早於上一輪的審查，看起來還沒有依意見修改。"
  fi
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---------- 3. 組裝 prompt ----------
tpl="$(cat "$SPEC_PROMPT_TEMPLATE")"
tpl="${tpl//\{\{TASK\}\}/$TASK}"
tpl="${tpl//\{\{ROUND\}\}/$ROUND}"
tpl="${tpl//\{\{PREV_ROUND\}\}/$PREV_ROUND}"
tpl="${tpl//\{\{MAX_ROUNDS\}\}/$SPEC_MAX_ROUNDS}"

{
  printf '%s\n\n' "$tpl"
  printf '<spec path="%s">\n' "$SPEC"
  cat "$SPEC"
  printf '\n</spec>\n'
  if (( ROUND > 1 )); then
    printf '\n<previous_review path="%s">\n' "$PREV_REVIEW"
    cat "$PREV_REVIEW"
    printf '\n</previous_review>\n'
    if [[ -f "$PREV_RESOLUTION" ]]; then
      printf '\n<previous_resolution path="%s">\n' "$PREV_RESOLUTION"
      cat "$PREV_RESOLUTION"
      printf '\n</previous_resolution>\n'
    fi
  fi
} > "$WORK/prompt.md"

# ---------- 4. 呼叫 Codex（唯讀沙盒、強制推理強度） ----------
codex_args=(exec --sandbox read-only)
[[ -z "$CODEX_MODEL" ]] || codex_args+=(-m "$CODEX_MODEL")
if [[ -n "$CODEX_EXTRA_ARGS" ]]; then
  read -r -a extra_args <<< "$CODEX_EXTRA_ARGS"
  codex_args+=("${extra_args[@]}")
fi
# 推理強度放在額外參數「之後」，讓它優先於 CODEX_EXTRA_ARGS / profile 內的設定。
# 值以 TOML 字串傳入（含雙引號），例如 model_reasoning_effort="ultra"
if [[ -n "$CODEX_REASONING_EFFORT" ]]; then
  codex_args+=(-c "model_reasoning_effort=\"$CODEX_REASONING_EFFORT\"")
fi
codex_args+=(-)   # 從 stdin 讀取 prompt

OUT="$SPEC_REVIEW_DIR/$TASK-p$ROUND-codex.md"
info "第 $ROUND/$SPEC_MAX_ROUNDS 輪方案審查中（Codex 唯讀，推理強度：${CODEX_REASONING_EFFORT:-沿用 codex 設定}）…"
if ! "$CODEX_BIN" "${codex_args[@]}" < "$WORK/prompt.md" > "$WORK/raw.md" 2> "$WORK/codex.err"; then
  tail -n 30 "$WORK/codex.err" >&2
  die "Codex 執行失敗，本輪不計入。"
fi
[[ -s "$WORK/raw.md" ]] || die "Codex 沒有輸出任何內容，本輪不計入。"

# ---------- 4.5 確認推理強度真的生效 ----------
# codex exec 啟動時通常會在 stderr 印出「reasoning effort: <值>」；
# 找不到這行（版本不同）時只警告，不當成失敗。
actual_model="$(grep -m1 -iE '^[[:space:]]*model:' "$WORK/codex.err" | sed -E 's/^[^:]*:[[:space:]]*//' | tr -d '\r' || true)"
actual_effort="$(grep -m1 -iE '^[[:space:]]*reasoning[[:space:]]+effort:' "$WORK/codex.err" | sed -E 's/^[^:]*:[[:space:]]*//' | tr -d '\r' | tr '[:upper:]' '[:lower:]' || true)"
actual_effort="${actual_effort%% *}"

if [[ -n "$CODEX_REASONING_EFFORT" ]]; then
  want="$(printf '%s' "$CODEX_REASONING_EFFORT" | tr '[:upper:]' '[:lower:]')"
  if [[ -z "$actual_effort" ]]; then
    warn "無法從 codex 的輸出確認實際的推理強度，請自行確認已生效（model: ${actual_model:-未知}）。"
  elif [[ "$actual_effort" != "$want" ]]; then
    msg="推理強度未生效：要求 $want，codex 實際使用 $actual_effort（model: ${actual_model:-未知}）。"
    if [[ "$CODEX_ALLOW_DOWNGRADE" == "1" ]]; then
      warn "$msg 已設定 CODEX_ALLOW_DOWNGRADE=1，繼續。"
    else
      err "$msg"
      err "可能是該模型不支援 $want。請用 codex 的 /model 查看可用的模型與等級，並以 CODEX_MODEL 指定。"
      err "若可接受降級，請設 CODEX_ALLOW_DOWNGRADE=1。本輪不計入。"
      exit "$EX_ERROR"
    fi
  else
    info "已確認：model ${actual_model:-未知}，reasoning effort $actual_effort"
  fi
elif [[ -n "$actual_effort" ]]; then
  info "codex 使用：model ${actual_model:-未知}，reasoning effort $actual_effort"
fi

# 去掉 VERDICT 行之前的雜訊（若有）
awk '/^[[:space:]]*\**VERDICT:/ { f = 1 } f' "$WORK/raw.md" > "$WORK/review.md"
if [[ ! -s "$WORK/review.md" ]]; then
  RAW_OUT="$SPEC_REVIEW_DIR/$TASK-p$ROUND-codex.raw.txt"
  cp "$WORK/raw.md" "$RAW_OUT"
  err "無法在輸出中找到 VERDICT 行，本輪不計入。原始輸出已存到：$RAW_OUT"
  exit "$EX_ERROR"
fi
mv "$WORK/review.md" "$OUT"

# ---------- 5. 解析結論 ----------
# 類型欄位只計算「單一詞」的行，避免誤計 prompt 範例中的 "blocker | suggestion | question"
count_type() { grep -ciE "類型(：|:)[[:space:]]*\**$1\**[[:space:]]*($|[^|[:space:]])" "$OUT" || true; }
n_block="$(count_type blocker)"
n_sugg="$(count_type suggestion)"
n_ques="$(count_type question)"

verdict="$(grep -m1 -oiE 'VERDICT:[[:space:]]*(APPROVE|REQUEST_CHANGES)' "$OUT" | grep -oiE 'APPROVE|REQUEST_CHANGES' | tr '[:lower:]' '[:upper:]' || true)"

if [[ "$verdict" == "APPROVE" && "$n_block" -gt 0 ]]; then
  warn "Codex 結論是 APPROVE，但意見中仍有 $n_block 則 blocker；依規則視為 REQUEST_CHANGES。"
  verdict="REQUEST_CHANGES"
fi

case "$verdict" in
  APPROVE)
    info "✅ Codex 認為方案可進入實作（blocker $n_block / suggestion $n_sugg / question $n_ques）"
    info "review: $OUT"
    info "下一步：回到 Claude Code，確認沒有想補充的意見後執行 /spec-approve $TASK"
    if (( n_sugg + n_ques > 0 )); then
      info "提醒：仍有 suggestion / question，可先看過再決定要不要納入。"
    fi
    echo "$OUT"
    exit "$EX_APPROVE"
    ;;
  REQUEST_CHANGES)
    warn "❌ Codex 要求修改（blocker $n_block / suggestion $n_sugg / question $n_ques）"
    warn "review: $OUT"
    left=$(( SPEC_MAX_ROUNDS - ROUND ))
    warn "下一步：回到 Claude Code，補充你自己的意見後執行 /spec-respond $TASK（還剩 $left 輪）"
    echo "$OUT"
    exit "$EX_CHANGES"
    ;;
  *)
    err "無法解析 VERDICT，請人工檢視：$OUT"
    echo "$OUT"
    exit "$EX_ERROR"
    ;;
esac
