VERDICT: PASS

## 摘要

本批涵蓋 `mall-tiny`、`mall-tiny-04`～`08` 的 32 個 Controller。改動只有兩件事：把 Swagger 2 註解換成 OpenAPI 3 註解，以及同步調整 import。每一處都符合 spec §4.7 的對照表，註解中的字串一字未改。這 6 個模組的 `controller/` 目錄共 32 個檔案，全部在 diff 中，Grep 確認已沒有 `io.swagger.annotations`、`@Api`、`@ApiOperation`、`@ApiParam` 殘留。沒有發現範圍外改動或行為變更。

## 驗收標準對照

| AC | 狀態 | 證據 |
|----|------|------|
| AC-1 | ✅（本批相關部分） | 新註解都有對應 import：只有 `PmsBrandController` 使用 `@Parameter`，6 個模組的這支檔案都已匯入 `io.swagger.v3.oas.annotations.Parameter`；其餘檔案只用 `@Operation`／`@Tag`，也都已匯入。完整變更 `fec2266` 的 §6 關卡 exit 0 |
| AC-2 | N/A（其他批次） | — |
| AC-3 | ✅（本批相關部分） | 6 個模組的 `controller/*.java` 中，Grep `io\.swagger\.annotations\|@Api\(\|@ApiOperation\|@ApiParam\|@ApiImplicitParam` 無命中 |
| AC-4 | N/A（其他批次） | — |
| AC-5 | N/A（其他批次） | — |
| AC-6 | N/A（其他批次） | — |
| AC-7 | N/A（其他批次） | — |
| AC-8 | N/A（其他批次） | 屬 `mall-tiny-02` |
| AC-9 | ⚠️ 手動，本批相關部分 ✅ | `mall-tiny-04/.../PmsBrandController.java` 的 `@Tag(name = "PmsBrandController")` 保留，6 個 `/brand/` operation 都改成 `@Operation(summary = ...)`。步驟 6 的 security 標記由 `SpringDocConfig` 處理（其他批次）。§9 自述步驟 6 通過；步驟 4 未驗證，原因是缺 MySQL，與本批無關 |
| AC-10 | N/A（其他批次） | 屬 Security 鏈 |
| AC-11 | N/A（其他批次） | — |
| AC-12 | N/A（其他批次） | — |
| AC-13 | ❓（手動，未驗證） | 本批只改 `mall-tiny` 的 `EsProductController`、`MemberReadHistoryController`、`OmsPortalOrderController`、`MinioController` 的文件註解，不影響執行邏輯。§9 自述此 AC 未驗證 |
| AC-14 | N/A（其他批次） | — |
| AC-15 | N/A（其他批次） | — |
| AC-16 | N/A（其他批次） | — |
| AC-17 | N/A（其他批次） | — |

各類替換都符合 §4.7：
- `@Api(tags = "X")`：類別上已有 `@Tag`，所以直接刪除該行。例如 `mall-tiny-04/.../UmsAdminController.java:26`。
- `@ApiOperation("S")`／`@ApiOperation(value = "S")` → `@Operation(summary = "S")`。
- `@ApiParam("D")` → `@Parameter(description = "D")`，見 `PmsBrandController.java:98,100`。
- 既有的 `io.swagger.v3.oas.annotations.tags.Tag` import 保留。

## 問題清單

無

## 範圍外改動

無。diffstat 的 32 個檔案全部屬於 §5「所有 import `io.swagger.annotations.*` 的 `.java`」中的 controller 類別。diff 只動到註解行與 import 行，沒有重新格式化、沒有調整 import 順序，也沒有改程式邏輯。

## 缺少的測試

無。依 spec §3.2 與 §7，本任務不新增自動化測試。

## Spec 問題

無

## 待確認事項

- AC-13（`mall-tiny` 的 ES／MongoDB／RabbitMQ／MinIO 端點）尚未手動驗證，§9 已如實標示。本批只動文件註解，對這些端點的執行行為沒有影響，但 AC 本身仍待實測。

## 給實作者的修正指令

無需修正
