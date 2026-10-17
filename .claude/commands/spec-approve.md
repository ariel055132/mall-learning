---
description: 核准 spec：檢查收斂條件、把狀態改為 approved，並 commit（凍結合約）
argument-hint: <task>
allowed-tools: Read, Grep, Glob, Edit, Bash(ls:*), Bash(date:*), Bash(git status:*), Bash(git branch:*), Bash(git rev-parse:*), Bash(git add:*), Bash(git commit:*), Bash(git log:*)
---

使用者執行 `/spec-approve` 代表**他決定核准這份 spec，可以進入實作**。任務代號：取 `$ARGUMENTS` 的第一個字詞，以下記為 `<task>`。

核准的意義：凍結第 1～8 節作為實作與驗收的合約，並 commit 到基準分支，讓之後從這裡開出的 worktree / branch 都帶有這份 spec，`review.sh` 才能偵測實作期間 spec 是否被改動。

## 步驟 1：收斂條件檢查

依序檢查；**任何一項不符就停下來，向使用者說明並詢問如何處理，不要自行放行。**

1. **檔案存在**：`docs/specs/<task>.md`，以及 `docs/spec-reviews/` 下至少一份 `<task>-p<N>-codex.md`。取最大的 N 為最新一輪。
2. **Codex 結論**：讀最新一輪審查的第一行 `VERDICT:`。
   - `APPROVE` → 符合。
   - `REQUEST_CHANGES` → 不符。除非使用者**明確表示**要以人類裁決覆寫，否則停下。若覆寫，之後在「核准」列註明「人類裁決覆寫 Codex 的 REQUEST_CHANGES」。
3. **審查後是否又改過 spec**：用 `ls -lt` 比較 `docs/specs/<task>.md` 與最新的 `<task>-p<N>-codex.md`。若 spec 比審查新，代表審查之後又有修改。告訴使用者，建議先再執行一次 `scripts/spec-review.sh <task>`；使用者明確要求仍要核准才繼續，並在「核准」列註明「核准前有未經重審的修改」。
4. **沒有待決事項**：
   - 最新的 `<task>-p<N>-resolution.md`（若存在）的「待人決定」必須是「無」。
   - spec 的「開放問題」必須是「無」。
5. **spec 本身完整**：沒有殘留的模板提示（例如 `<任務標題>`、`<條件>`、`<決議內容>`、`<path/to/file>`）；至少有一條 `**AC-n**`；第 6 節有驗證指令的程式碼區塊；第 9 節仍是空白的模板內容（尚未被實作者填寫）。
6. **目前分支是基準分支**：用 `git branch --show-current` 確認在 `main`（或 `master`）。不是的話停下來詢問；spec 必須先進入基準分支，之後的 worktree 才會帶有它。

## 步驟 2：更新 spec

只修改 `docs/specs/<task>.md` meta 表格的兩列，其他內容一律不動：

- `狀態` → `approved`
- `核准` → `YYYY-MM-DD；依據 docs/spec-reviews/<task>-p<N>-codex.md（APPROVE）`（日期用 `date +%F`）。若有步驟 1 的覆寫或未重審情形，附註在同一格。

## 步驟 3：commit

1. 先用 `git status --short` 讓使用者看到目前狀態。
2. **只加入**這份 spec 與它的審查紀錄，不要用 `git add -A` 或 `git add .`：

   ```
   git add docs/specs/<task>.md docs/spec-reviews/<task>-*
   git commit -m "spec(<task>): approved" -- docs/specs/<task>.md docs/spec-reviews/<task>-*
   ```

3. 不要 push。若 commit 失敗（例如 hook 擋下），如實回報原因，不要繞過 hook。

## 步驟 4：回報下一步

簡短回報已核准的 commit，並提供下一步指令（分支名稱用 spec meta 表格的「分支」欄位）：

```bash
git worktree add ../<repo>-<task> -b feat/<task>
cd ../<repo>-<task>
codex exec "閱讀 docs/specs/<task>.md 並實作。嚴格遵守非目標，不得修改第 1～8 節。完成後執行第 6 節的驗證指令並填寫第 9 節。不要 commit。"

# 實作完成後，驗收：
scripts/review.sh <task>
```

提醒使用者：從現在起，第 1～8 節是合約。若實作中發現 spec 有誤，應該回到規劃階段重新修改並重新審查，而不是讓實作者直接改 spec。
