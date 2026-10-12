VERDICT: PASS

## 摘要

本批刪除 10 個模組的 `Swagger2Config.java`，並在同一目錄新增 `SpringDocConfig.java`，內容符合 spec §4.5 的範本。需要認證的模組（`mall-tiny`、`04`～`08`、`boot`）保留了 `Components` 安全機制與 `brandSecurityCustomizer`。不需要認證的模組（`02`、`03`、`alipay`）只定義 `mallTinyOpenAPI()`。這個分組與舊檔是否設定 `securitySchemes`／`securityContexts` 完全一致。舊檔中為 Springfox 寫的 `BeanPostProcessor` 已一併移除；專案 `src` 內也找不到其他程式（含測試）引用已刪除的類別或 Bean。沒有發現 high 或 medium 問題。

## 驗收標準對照

| AC | 狀態 | 證據 |
|----|------|------|
| AC-1 | ✅ | 新檔只使用 `io.swagger.v3.oas.models.*`、`org.springdoc.core.customizers.OpenApiCustomizer` 與 Spring 註解。這 10 個模組中有 9 個的 POM 已改用 `springdoc-openapi-starter-webmvc-ui`（例如 `mall-tiny-04/pom.xml:74`）。`mall-tiny-02/pom.xml:75` 仍是 `springfox-boot-starter`，屬於後續 D-17 批次，本批單獨看無法編譯是預期內的。完整變更 `fec2266` 的 §6 關卡 exit 0 |
| AC-2 | N/A（其他批次） | POM 依賴屬其他批次 |
| AC-3 | ✅（本批部分） | 本批新增的 10 個檔案不含 `springfox.`、`io.swagger.annotations.`、`v2/api-docs`、`swagger-resources`。以 Grep 確認，`Swagger2Config` 只殘留在 stream／swagger／redis／mybatis／jenkins／hutool／docker／plus／generator／rabbit，這些屬其他批次 |
| AC-4 | N/A（其他批次） | YAML、POM、Dockerfile 不在本批 |
| AC-5 | N/A（其他批次） | — |
| AC-6 | N/A（其他批次） | `mall-tiny-01` 沒有 Swagger |
| AC-7 | N/A（其他批次） | — |
| AC-8 | ✅（本批部分） | `mall-tiny-02/.../SpringDocConfig.java:21` 的 `title("SwaggerUI演示")` 與舊檔 `apiInfo()` 一致。`tags`、`summary` 來自 Controller 註解，屬其他批次。§9.2 自述實測通過 |
| AC-9 | ✅（步驟 6 的程式碼部分） | `mall-tiny-04/.../SpringDocConfig.java:33-36` 宣告的安全機制為 `APIKEY`／`HEADER`／`name=Authorization`，對應舊檔 `ApiKey("Authorization","Authorization","header")`。`:41-51` 以 `path.startsWith("/brand/")` 加上 security requirement，與舊的 `PathSelectors.regex("/brand/.*")` 語意相同。`/admin/login` 不符合這個前綴，所以不會帶 security。其他步驟屬 SecurityConfig 批次與手動驗證 |
| AC-10 | N/A（其他批次） | — |
| AC-11 | N/A（其他批次） | — |
| AC-12 | N/A（其他批次） | — |
| AC-13 | ❓ | `mall-tiny/.../SpringDocConfig.java` 的設定正確，但 AC-13 需要外部服務，§9.2 標示為未驗證 |
| AC-14 | N/A（其他批次） | — |
| AC-15 | N/A（其他批次） | — |
| AC-16 | ✅（步驟 4 的程式碼部分） | `mall-tiny-boot/.../SpringDocConfig.java` 已提供 springdoc 設定。`/v3/api-docs` 的放行由 SecurityConfig／YAML 批次負責 |
| AC-17 | N/A（其他批次） | — |

## 問題清單

### [R1-1] 新增檔案的 import 沒有依字母排序

- 嚴重度：low
- 位置：`mall-tiny-04/src/main/java/com/macro/mall/tiny/config/SpringDocConfig.java:5-6`（`05`～`08`、`boot`、`mall-tiny` 相同）
- 問題：`io.swagger.v3.oas.models.Components` 排在 `info.Contact`／`info.Info` 之後，順序與周邊慣例不一致。純屬風格問題，不影響功能。
- 建議修法：可選擇把 `Components` 移到 `OpenAPI` 之前或之後的字母序位置；也可以不改。

## 範圍外改動

無。本批 20 個檔案都在 §5「刪除 `Swagger2Config.java`／新增 `SpringDocConfig.java`」的清單內。新檔沿用了舊檔的 Javadoc（作者、日期、description），沒有額外重構。

## 缺少的測試

無。spec §3.2 和 §7 規定不新增測試，AC-8 與 AC-9 步驟 6 以手動方式驗證。

## Spec 問題

無

## 待確認事項

- 本批只遷移了 Java 設定。舊檔的 `RequestHandlerSelectors.basePackage("com.macro.mall.tiny.controller")` 掃描範圍，要靠各模組 `application.yml` 的 `springdoc.packages-to-scan` 補上，這屬於 YAML 批次，本批無法確認。
- springdoc 預設會快取 OpenAPI 文件，所以 `brandSecurityCustomizer` 每次建構文件只執行一次，不會重複加入 security item。這是依 springdoc 2.x 的預設行為判斷，未實際執行確認；§9.2 自述 `mall-tiny-04` 的 6 個品牌 operation 都只有一組 `security:[{"Authorization":[]}]`，與此一致。

## 給實作者的修正指令

無需修正
