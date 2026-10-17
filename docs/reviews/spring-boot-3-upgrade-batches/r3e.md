VERDICT: PASS

## 摘要

本批 20 個 Controller 已把 Swagger 2 註解換成 OpenAPI 3 註解，做法符合 spec §4.7 對照表。類別上已有 `@Tag` 的，直接刪除 `@Api`；`mall-tiny-plus`、`mall-tiny-stream` 的 `PmsBrandController` 改為 `@Tag(name, description)`；`mall-tiny-swagger` 的 `@ApiImplicitParams` 改為 `@Parameters` 並加上 `ParameterIn.QUERY`。描述字串都沒有改動，程式本體與 HTTP 映射也沒有變。以 Grep 確認，本批模組的 Controller 已經沒有任何 `io.swagger.annotations` 殘留；剩下的命中都在 `mall-tiny`、`04`～`08`，屬於其他批次。

## 驗收標準對照

| AC | 狀態 | 證據 |
|----|------|------|
| AC-1 | ✅ | 本批只換註解與 import。新註解都來自 springdoc 帶入的 `io.swagger.v3.oas.annotations.*`，jakarta import 也正確（`mall-tiny-alipay/.../AlipayController.java:17-18`、`mall-tiny-hutool/.../HutoolController.java:34-35`）。完整變更 `fec2266` 的 §6 機器關卡 exit 0 |
| AC-2 | N/A（其他批次） | 本批沒有 POM 變更 |
| AC-3 | ✅（本批相關部分） | 在 `**/controller/**` 下 Grep `io\.swagger\.annotations\|@Api(Operation\|Param\|ImplicitParams?)?\(`，命中的 32 個檔案都在 `mall-tiny`、`mall-tiny-04`～`08`，不在本批範圍。本批 alipay／hutool 的 `import javax.servlet.` 已改為 `jakarta.servlet.` |
| AC-4 | N/A（其他批次） | — |
| AC-5 | N/A（其他批次） | — |
| AC-6 | N/A（其他批次） | `mall-tiny-01` 沒有 Swagger |
| AC-7 | N/A（其他批次） | 本批對 `mall-tiny-plus/.../PmsBrandController.java` 只改註解，分頁邏輯 `:96-100` 不變 |
| AC-8 | ✅（本批相關部分） | `mall-tiny-02/.../PmsBrandController.java:27` 有 `@Tag(name = "PmsBrandController", ...)`，`:35` 有 `@Operation(summary = "获取所有品牌列表")`，對應 `/brand/listAll` GET。`info.title` 與 UI 網址由其他批次的 `SpringDocConfig` 和 YAML 處理。§9.2 自述實測通過，但這只是自述，不當作證據 |
| AC-9 | N/A（其他批次） | `mall-tiny-04` 的 Controller 不在本批 |
| AC-10 | N/A（其他批次） | — |
| AC-11 | N/A（其他批次） | 本批對 `mall-tiny-03/.../UmsMemberController.java` 只換註解，`@RequestParam String telephone` 等簽章不變 |
| AC-12 | N/A（其他批次） | 本批對 `mall-tiny-redis` 的 Controller 只換註解，路徑與參數不變 |
| AC-13 | N/A（其他批次） | — |
| AC-14 | N/A（其他批次） | — |
| AC-15 | N/A（其他批次） | — |
| AC-16 | N/A（其他批次） | 本批對 `mall-tiny-boot` 的 `PmsBrandController`／`UmsAdminController` 只換註解，`@PreAuthorize("hasRole('ADMIN')")` 與 `/admin/login` 映射都保留（`mall-tiny-boot/.../PmsBrandController.java` diff 中的 `@PreAuthorize` 行沒有變） |
| AC-17 | N/A（其他批次） | 本批對 `mall-tiny-02` 只改 Controller 註解 |

## 問題清單

無

## 範圍外改動

無。我逐檔核對過，只有以下三類變更：
- 刪除或新增註解 import；
- `@Api` 刪除或改成 `@Tag`；
- `@ApiOperation`／`@ApiParam`／`@ApiImplicitParam(s)` 依 §4.7 換成新註解，且保留原本的空白風格（例如 `"支付宝异步回调",description = ...`、`"状态",required = true`）。

`mall-tiny-swagger/.../PmsBrandController.java` 原本是萬用字元 `import io.swagger.annotations.*;`，現在改成兩個明確的 import。這屬於直接相關的 import 調整，不是 import 重新排序。

## 缺少的測試

無。依 spec §3.2／§7，本任務不新增測試。

## Spec 問題

無

## 待確認事項

- spec §4.5 列出 `mall-tiny-mybatis`，但這個模組底下找不到任何 Controller（Grep `@(Rest)?Controller\b` 無命中），所以本批沒有它的 Controller 變更是合理的。只是要提醒：批次說明把 `mybatis` 列入本批，實際上沒有對應檔案。

## 給實作者的修正指令

無需修正
