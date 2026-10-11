#!/usr/bin/env bash
#
# review.sh — 機器關卡 + 獨立 Claude 審查
#
# 流程：
#   1. 讀取 docs/specs/<task>.md，執行第 6 節「驗證指令」（機器關卡）
#   2. 產生相對於分支起點的 diff（含未 commit 的修改與新增檔案，不動你的 index）
#   3. 以全新、唯讀的 `claude -p` session 審查（只給 spec + diff + 檢查結果）
#   4. 寫入 docs/reviews/<task>-r<N>.md，依第一行 VERDICT 回傳 exit code
#
# 相容 bash 3.2（macOS 預設）以上。
#
set -euo pipefail

# ---------- exit codes ----------
EX_PASS=0     # 審查通過
EX_FAIL=1     # 審查不通過（review 已寫出）
EX_ERROR=2    # 用法、環境或工具錯誤
EX_CHECKS=3   # 機器關卡失敗（未呼叫 Claude）
EX_ROUNDS=4   # 已超過最大輪數

# ---------- 可用環境變數覆寫的設定 ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPEC_DIR="${SPEC_DIR:-docs/specs}"
REVIEW_DIR="${REVIEW_DIR:-docs/reviews}"
PROMPT_TEMPLATE="${PROMPT_TEMPLATE:-$SCRIPT_DIR/review-prompt.md}"
MAX_ROUNDS="${MAX_ROUNDS:-3}"
MAX_DIFF_LINES="${MAX_DIFF_LINES:-2500}"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
CLAUDE_MODEL="${CLAUDE_MODEL:-}"
CLAUDE_EXTRA_ARGS="${CLAUDE_EXTRA_ARGS:-}"
# diff 內文要省略的檔名（任何目錄層級），仍會出現在 diffstat
DIFF_EXCLUDES="${DIFF_EXCLUDES:-package-lock.json pnpm-lock.yaml yarn.lock poetry.lock uv.lock Cargo.lock go.sum}"

# ---------- 輸出 helpers ----------
if [[ -t 2 ]]; then
  C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_0=$'\033[0m'
else
  C_G=""; C_Y=""; C_R=""; C_0=""
fi
info() { printf '%s[review]%s %s\n' "$C_G" "$C_0" "$*" >&2; }
warn() { printf '%s[review]%s %s\n' "$C_Y" "$C_0" "$*" >&2; }
err()  { printf '%s[review]%s %s\n' "$C_R" "$C_0" "$*" >&2; }
die()  { err "$*"; exit "$EX_ERROR"; }

usage() {
  cat <<'EOF'
用法: review.sh <task> [選項]

  <task>                  任務代號，對應 docs/specs/<task>.md

選項:
  -b, --base <ref>        比較的基準分支（預設：main，找不到則 master）
  -r, --round <n>         手動指定輪次（預設：依 docs/reviews 內既有檔案自動遞增）
  -v, --verify <cmds>     覆寫機器關卡指令（預設：讀 spec 第 6 節的第一個程式碼區塊）
      --skip-checks       略過機器關卡（不建議）
  -f, --force             diff 過大時仍強制審查
  -h, --help              顯示說明

環境變數:
  SPEC_DIR, REVIEW_DIR    spec 與 review 目錄（預設 docs/specs、docs/reviews）
  MAX_ROUNDS              最大審查輪數（預設 3）
  MAX_DIFF_LINES          diff 行數上限（預設 2500）
  CLAUDE_BIN              claude 執行檔（預設 claude）
  CLAUDE_MODEL            指定模型（--model）
  CLAUDE_EXTRA_ARGS       額外傳給 claude 的參數（以空白分隔）
  DIFF_EXCLUDES           省略內文的檔名清單（空白分隔，預設為常見 lockfile）
  PROMPT_TEMPLATE         審查 prompt 模板路徑
  VERIFY_CMD              同 --verify

Exit code:
  0 通過 | 1 不通過 | 2 錯誤 | 3 機器關卡失敗 | 4 超過最大輪數
EOF
}

need_arg() { [[ $# -ge 2 && -n "${2:-}" ]] || die "選項 $1 需要參數"; }

# ---------- 解析參數 ----------
TASK=""; BASE=""; ROUND=""; VERIFY_OVERRIDE="${VERIFY_CMD:-}"; SKIP_CHECKS=0; FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--base)     need_arg "$@"; BASE="$2"; shift 2 ;;
    -r|--round)    need_arg "$@"; ROUND="$2"; shift 2 ;;
    -v|--verify)   need_arg "$@"; VERIFY_OVERRIDE="$2"; shift 2 ;;
    --skip-checks) SKIP_CHECKS=1; shift ;;
    -f|--force)    FORCE=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    -*)            die "未知選項: $1（用 --help 查看用法）" ;;
    *)             [[ -z "$TASK" ]] || die "只能指定一個任務代號"; TASK="$1"; shift ;;
  esac
done

if [[ -z "$TASK" ]]; then usage >&2; exit "$EX_ERROR"; fi
[[ "$TASK" =~ ^[A-Za-z0-9._-]+$ ]] || die "任務代號只能包含英數字與 . _ -"

# ---------- 環境檢查 ----------
command -v git >/dev/null 2>&1 || die "找不到 git"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "請在 git repo（或 worktree）內執行"
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
command -v "$CLAUDE_BIN" >/dev/null 2>&1 || die "找不到 ${CLAUDE_BIN}（可用 CLAUDE_BIN 指定路徑）"

SPEC="$SPEC_DIR/$TASK.md"
[[ -f "$SPEC" ]] || die "找不到 spec: $SPEC"
[[ -f "$PROMPT_TEMPLATE" ]] || die "找不到 prompt 模板: $PROMPT_TEMPLATE"

if [[ -z "$BASE" ]]; then
  for c in main master; do
    if git rev-parse --verify --quiet "$c^{commit}" >/dev/null; then BASE="$c"; break; fi
  done
  [[ -n "$BASE" ]] || die "找不到 main 或 master，請用 --base 指定基準分支"
fi
git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null || die "找不到基準分支: $BASE"
MERGE_BASE="$(git merge-base HEAD "$BASE")" || die "無法計算與 $BASE 的分支起點"

# ---------- 決定輪次 ----------
mkdir -p "$REVIEW_DIR"
if [[ -z "$ROUND" ]]; then
  shopt -s nullglob
  existing=("$REVIEW_DIR/$TASK"-r[0-9]*.md)
  shopt -u nullglob
  ROUND=$(( ${#existing[@]} + 1 ))
fi
[[ "$ROUND" =~ ^[0-9]+$ && "$ROUND" -ge 1 ]] || die "輪次必須是正整數"

if (( ROUND > MAX_ROUNDS )); then
  warn "已進行 $((ROUND - 1)) 輪審查，超過上限 ${MAX_ROUNDS}。"
  warn "反覆修不好，通常代表 spec 不夠清楚。建議回到規劃階段檢視 ${SPEC}，"
  warn "必要時縮小範圍或拆分任務；若仍要繼續，請加 --round 指定輪次並調高 MAX_ROUNDS。"
  exit "$EX_ROUNDS"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---------- 1. 機器關卡 ----------
extract_verify_cmds() {
  # 取出標題含「驗證指令」的章節中，第一個 ``` 程式碼區塊的內容
  awk '
    /^##[[:space:]]+.*驗證指令/ { in_sec = 1; next }
    in_sec && /^##[[:space:]]/   { exit }
    in_sec && /^```/             { if (in_block) exit; in_block = 1; next }
    in_sec && in_block           { print }
  ' "$1"
}

CHECKS_SUMMARY=""
if (( SKIP_CHECKS )); then
  warn "已略過機器關卡。"
  CHECKS_SUMMARY="（已略過機器關卡：未執行測試、lint、型別檢查）"
else
  if [[ -n "$VERIFY_OVERRIDE" ]]; then
    cmds="$VERIFY_OVERRIDE"
  else
    cmds="$(extract_verify_cmds "$SPEC")"
  fi
  [[ -n "${cmds//[[:space:]]/}" ]] \
    || die "找不到驗證指令。請確認 spec 第 6 節有程式碼區塊，或使用 --verify / --skip-checks。"

  printf '%s\n' "$cmds" > "$WORK/verify.sh"
  CHECKS_LOG="$REVIEW_DIR/$TASK-checks.log"
  info "執行機器關卡（輸出：${CHECKS_LOG}）"
  rc=0
  bash -eo pipefail "$WORK/verify.sh" > "$CHECKS_LOG" 2>&1 || rc=$?
  if (( rc != 0 )); then
    printf -- '---- %s (最後 40 行) ----\n' "$CHECKS_LOG" >&2
    tail -n 40 "$CHECKS_LOG" >&2
    err "機器關卡失敗（exit ${rc}），未呼叫 Claude。請先修到全綠，可把 $CHECKS_LOG 餵回 Codex。"
    exit "$EX_CHECKS"
  fi
  CHECKS_SUMMARY="全部通過（所有指令 exit 0）。執行的指令：
$cmds"
  info "機器關卡通過"
fi

# ---------- 2. 產生 diff ----------
# 用暫時的 index 把「未 commit 的修改 + 未追蹤的新檔」都納入，不會動到你真正的 index。
IDX="$WORK/index"
cp "$(git rev-parse --git-path index)" "$IDX" 2>/dev/null || true

read -r -a excl_names <<< "$DIFF_EXCLUDES"
base_excludes=(":(exclude)$REVIEW_DIR" ":(exclude)$SPEC_DIR")
diff_excludes=()
for n in ${excl_names[@]+"${excl_names[@]}"}; do
  diff_excludes+=(":(exclude,glob)**/$n")
done

(
  export GIT_INDEX_FILE="$IDX"
  git add -A -- . >/dev/null 2>&1
  git diff --cached --no-color --find-renames "$MERGE_BASE" -- . \
    "${base_excludes[@]}" ${diff_excludes[@]+"${diff_excludes[@]}"} > "$WORK/diff.patch"
  git diff --cached --no-color --stat=120 --find-renames "$MERGE_BASE" -- . \
    "${base_excludes[@]}" > "$WORK/diffstat.txt"
)

DIFF_LINES="$(wc -l < "$WORK/diff.patch" | tr -d '[:space:]')"
(( DIFF_LINES > 0 )) \
  || die "沒有偵測到程式碼變更（相對於 ${BASE}；已排除 ${SPEC_DIR}、$REVIEW_DIR 與 lockfile）"
if (( DIFF_LINES > MAX_DIFF_LINES && FORCE == 0 )); then
  die "diff 共 $DIFF_LINES 行，超過上限 ${MAX_DIFF_LINES}；過大的 diff 會明顯降低審查品質。建議拆分任務，或加 --force 強制審查。"
fi

# 偵測 spec 在實作期間是否被改動（需要 spec 已 commit 在分支起點）
SPEC_CHANGES=""
if git cat-file -e "$MERGE_BASE:$SPEC" 2>/dev/null; then
  SPEC_CHANGES="$(GIT_INDEX_FILE="$IDX" git diff --cached --no-color "$MERGE_BASE" -- "$SPEC")"
  if [[ -n "$SPEC_CHANGES" ]]; then
    warn "spec 在此分支上有變動，已附給審查者；請自行確認第 1～8 節沒被改動。"
  fi
else
  warn "spec 尚未 commit 到分支起點，無法偵測它是否在實作期間被改動。"
  warn "建議：先 commit spec，再開 worktree / branch。"
fi

# ---------- 3. 組裝 prompt ----------
tpl="$(cat "$PROMPT_TEMPLATE")"
tpl="${tpl//\{\{TASK\}\}/$TASK}"
tpl="${tpl//\{\{ROUND\}\}/$ROUND}"
tpl="${tpl//\{\{MAX_ROUNDS\}\}/$MAX_ROUNDS}"

PREV_REVIEW="$REVIEW_DIR/$TASK-r$((ROUND - 1)).md"
{
  printf '%s\n\n' "$tpl"
  printf '<spec path="%s">\n' "$SPEC"
  cat "$SPEC"
  printf '\n</spec>\n\n'
  if [[ -n "$SPEC_CHANGES" ]]; then
    printf '<spec_changes>\n%s\n</spec_changes>\n\n' "$SPEC_CHANGES"
  fi
  printf '<machine_checks>\n%s\n</machine_checks>\n\n' "$CHECKS_SUMMARY"
  printf '<diffstat>\n'
  cat "$WORK/diffstat.txt"
  printf '</diffstat>\n\n'
  printf '<diff base="%s">\n' "$MERGE_BASE"
  cat "$WORK/diff.patch"
  printf '</diff>\n'
  if (( ROUND > 1 )) && [[ -f "$PREV_REVIEW" ]]; then
    printf '\n<previous_review path="%s">\n' "$PREV_REVIEW"
    cat "$PREV_REVIEW"
    printf '\n</previous_review>\n'
  fi
} > "$WORK/prompt.md"

# ---------- 4. 呼叫 Claude（全新 session、唯讀工具） ----------
claude_args=(
  -p "請依 stdin 內的〈審查指令〉與審查材料執行審查，並嚴格遵守其中規定的輸出格式。"
  --allowedTools "Read,Grep,Glob"
  --disallowedTools "Edit,Write,Bash,NotebookEdit"
)
[[ -z "$CLAUDE_MODEL" ]] || claude_args+=(--model "$CLAUDE_MODEL")
if [[ -n "$CLAUDE_EXTRA_ARGS" ]]; then
  read -r -a extra_args <<< "$CLAUDE_EXTRA_ARGS"
  claude_args+=("${extra_args[@]}")
fi

OUT="$REVIEW_DIR/$TASK-r$ROUND.md"
info "第 $ROUND/$MAX_ROUNDS 輪審查中（base: ${BASE}，diff $DIFF_LINES 行）…"
if ! "$CLAUDE_BIN" "${claude_args[@]}" < "$WORK/prompt.md" > "$WORK/review.md" 2> "$WORK/claude.err"; then
  cat "$WORK/claude.err" >&2
  die "Claude 執行失敗，本輪不計入。"
fi
[[ -s "$WORK/review.md" ]] || die "Claude 沒有輸出任何內容，本輪不計入。"
mv "$WORK/review.md" "$OUT"

# ---------- 5. 解析結論 ----------
verdict="$(grep -m1 -oiE 'VERDICT:[[:space:]]*(PASS|FAIL)' "$OUT" | grep -oiE 'PASS|FAIL' | tr '[:lower:]' '[:upper:]' || true)"
n_high="$(grep -ciE '嚴重度(：|:)[[:space:]]*\**high\**[[:space:]]*($|[^|[:space:]])' "$OUT" || true)"
n_med="$(grep -ciE '嚴重度(：|:)[[:space:]]*\**medium\**[[:space:]]*($|[^|[:space:]])' "$OUT" || true)"
n_low="$(grep -ciE '嚴重度(：|:)[[:space:]]*\**low\**[[:space:]]*($|[^|[:space:]])' "$OUT" || true)"

case "$verdict" in
  PASS)
    info "✅ 審查通過（high $n_high / medium $n_med / low ${n_low}）"
    info "review: $OUT"
    echo "$OUT"
    exit "$EX_PASS"
    ;;
  FAIL)
    warn "❌ 審查不通過（high $n_high / medium $n_med / low ${n_low}）"
    warn "review: $OUT"
    left=$(( MAX_ROUNDS - ROUND ))
    if (( left > 0 )); then
      warn "還剩 $left 輪。下一步，交給 Codex 修正："
      printf '  codex exec "依據 %s 的「給實作者的修正指令」修正 high 與 medium 問題。不得修改 spec 第 1～8 節。完成後重跑 spec 第 6 節的驗證指令。不要 commit。"\n' "$OUT" >&2
    else
      warn "已達輪數上限。若仍不通過，請回到規劃階段檢視 ${SPEC}。"
    fi
    echo "$OUT"
    exit "$EX_FAIL"
    ;;
  *)
    err "無法從輸出解析 VERDICT 行，請人工檢視：$OUT"
    echo "$OUT"
    exit "$EX_ERROR"
    ;;
esac
