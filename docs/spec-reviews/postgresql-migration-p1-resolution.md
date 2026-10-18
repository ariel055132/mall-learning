# postgresql-migration 方案審查 第 1 輪：回應紀錄

日期：2026-10-17

## 人類意見（口頭，供下一輪審查者參考）

- H1-1：使用者選擇採納 Codex 第 1 輪的三則 suggestion，修改後再跑一輪審查；並表示「主要目的是要進行 mysql 轉用 postgresql」。→ 三則意見全數採納（見下表）；本任務範圍維持 D-1（A 組 6 個模組），不擴大。

## 對 Codex 意見的回應

| 意見 | 類型 | 處置 | 說明 |
|------|------|------|------|
| P1-1 | suggestion | 採納 | 已查證 `mall-tiny-03/.../UmsMemberServiceImpl.java:30-46` 只用 Redis，`PmsBrandServiceImpl.java:46` 才走 PageHelper；03 無 Security，`/brand/list` 可直接呼叫。§2 AC-8 拆為步驟 1（`GET /brand/list?pageNum=1&pageSize=3`，`code=200`、長度 `min(N,3)`、`total=N`）與步驟 2（原驗證碼流程）；§7 對應列註明升級 spec AC-11 對應步驟 2；新增 D-8。 |
| P1-2 | suggestion | 採納（收緊關卡） | 選擇補結構檢查而非改標程式碼審查。§6 改為：`perl -0` 比對 POM dependency 區塊（groupId／artifactId／runtime scope 依序、無 version）、`spring:` 下 datasource 四行逐行與縮排、頂層 `pagehelper:` 區塊；`grep -E` 以 `<insert id="insert" …>`／`<insert id="insertSelective" …>` 分別比對屬性；新增「`plus` 不含 `pagehelper:`」反向檢查。前置條件加 `perl`。已實測：以 `mall-tiny-02` 套用模組檢查全部通過，現況的 `mall-tiny-01` 正確失敗。§2 AC-2 文字同步改為結構化描述；新增 D-9。 |
| P1-3 | suggestion | 採納 | 已查證 `mall-tiny-boot/.../application.yml:2` 為 8088、`mall-tiny-01/pom.xml` 無 springdoc、`mall-tiny-plus/.../MyBatisConfig.java:23` 用 MyBatis-Plus interceptor。§4.5 新增逐模組差異清單；§2 AC-12 加入「共用啟動說明須註明模組差異」；新增 D-10。 |

## spec 變更摘要

- meta：狀態 `draft` → `in-review`。
- §2：AC-2 細項改寫為可結構驗證的描述，並新增「`plus` 不含 `pagehelper:`」；AC-8 拆為步驟 1（新增 `/brand/list`）與步驟 2；AC-12 新增模組差異註記要求。無 AC 新增或移除，編號不變。
- §4：§4.5 新增模組差異清單；關鍵決策參照改為 D-1～D-10。
- §6：關卡改用結構檢查（見 P1-2），前置條件加 `perl`，註解說明 `perl -0` 與 `DS` 單引號。
- §7：AC-8 對應升級 spec 項目改為「AC-11（本 AC 步驟 2）」。
- §8.1：新增 D-8（P1-1）、D-9（P1-2）、D-10（P1-3）。

## 待人決定

無
