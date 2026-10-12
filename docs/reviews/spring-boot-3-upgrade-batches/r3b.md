VERDICT: PASS

## 摘要

本批刪除了 10 個模組的 `Swagger2Config.java`，並在同一目錄新增 `SpringDocConfig.java`。每個模組有沒有認證設定，都和 spec §4.5 的分組一致：`mybatis`、`rabbit`、`swagger` 保留 `components` 與 `brandSecurityCustomizer`；`docker`、`generator`、`hutool`、`jenkins`、`plus`、`redis`、`stream` 只有 `mallTinyOpenAPI()`。新設定與 §4.5 範本逐行相符。舊檔原本以 `basePackage` 指定的掃描範圍，已由各模組 YAML 的 `springdoc.packages-to-scan` 接手，其中 `plus` 是 `modules`，其餘是 `controller`。各 POM 也都已有 springdoc starter。沒有發現 high 或 medium 問題。

## 驗收標準對照

| AC | 狀態 | 證據 |
|----|------|------|
| AC-1 | ✅ | 依 `<machine_checks>`：完整變更（`fec2266`）的 §6 三次建置都通過。本批新檔只用到 `io.swagger.v3.oas.models.*` 與 `org.springdoc.core.customizers.OpenApiCustomizer`；10 個模組的 POM 都已宣告 `springdoc-openapi-starter-webmvc-ui`（例如 `mall-tiny-jenkins/pom.xml:112-114`、`mall-tiny-plus/pom.xml:48-50`） |
| AC-2 | N/A（其他批次） | 本批沒有改 POM |
| AC-3 | ✅（本批相關部分） | 本批 10 個模組的 `springfox.` import 已隨 `Swagger2Config.java` 一起刪除；Grep 本批 10 個模組的 `springfox`／`Swagger2Config`，`.java` 檔都沒有命中。其他 10 個模組殘留的 `Swagger2Config.java` 屬於後續批次 |
| AC-4 | N/A（其他批次） | 本批沒有改 YAML、POM、Dockerfile |
| AC-5 | N/A（其他批次） | — |
| AC-6、AC-7 | N/A（其他批次） | — |
| AC-8 | N/A（其他批次） | 這條驗的是 `mall-tiny-02`，不在本批。本批 `SpringDocConfig` 的 `info` 為 `title("SwaggerUI演示")`、`description("mall-tiny")`、`Contact.name("macro")`、`version("1.0")`，和舊 `apiInfo()` 一致（例如 `mall-tiny-docker/.../SpringDocConfig.java:20-24`） |
| AC-9 | N/A（其他批次） | 第 6 步驗的是 `mall-tiny-04`，不在本批。本批 `mybatis`／`rabbit`／`swagger` 的 customizer 用 `path.startsWith("/brand/")` 加上 `SecurityRequirement("Authorization")`，等同舊的 `PathSelectors.regex("/brand/.*")`；scheme 是 `APIKEY`／`HEADER`／`name=Authorization`，等同舊的 `new ApiKey("Authorization","Authorization","header")`（`mall-tiny-mybatis/.../SpringDocConfig.java:32-50`） |
| AC-10～AC-17 | N/A（其他批次） | — |

## 問題清單

### [R1-1] 帶認證的三個 `SpringDocConfig` import 順序和周邊不一致

- 嚴重度：low
- 位置：`mall-tiny-mybatis/src/main/java/com/macro/mall/tiny/config/SpringDocConfig.java:3-7`（`rabbit`、`swagger` 相同）
- 問題：`io.swagger.v3.oas.models.Components` 排在 `...info.Info` 後面，沒有按字母順序放在 `OpenAPI` 前面。只影響可讀性，不影響行為。
- 建議修法：可以順手調整，不阻擋合併。

## 範圍外改動

無。本批只有 spec §5 列出的刪除 `Swagger2Config.java` 與新增 `SpringDocConfig.java`。新檔保留了原本的類別 Javadoc（作者、描述、日期），沒有夾帶其他改動。

## 缺少的測試

無。依 spec §3.2 與 §7，本任務不新增自動化測試；OpenAPI 輸出改以 AC-8、AC-9 的手動驗證涵蓋。

## Spec 問題

無

## 待確認事項

- 本批 10 個模組啟動後的 `/v3/api-docs` 輸出沒有實測過（§9 只實測了 `02`、`04`、`boot`）。從程式碼判斷，輸出應與已實測的模組相同。若要更有把握，可以挑 `mall-tiny-swagger` 或 `mall-tiny-mybatis` 啟動一次，確認 `/brand/` 路徑帶有 security；`mall-tiny-plus` 則確認掃描 `modules` 套件後有產生 `PmsBrandController` 的 tag。

## 給實作者的修正指令

無需修正
