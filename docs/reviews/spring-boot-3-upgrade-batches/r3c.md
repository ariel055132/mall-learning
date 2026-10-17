VERDICT: PASS

## 摘要

本批涵蓋 17 個 `CommentGenerator`、`MyBatisPlusGenerator`，以及 22 個 mbg/model、9 個 model、7 個 domain、3 個 dto 與 `mall-tiny-plus` 的 `PmsBrand`。所有變更都符合 §4.7／§4.8：只替換註解與 import，描述字串一字不改，`@ApiModel` 的 `value` 依規格捨棄。以 Grep 確認，本批範圍的目錄已沒有 `io.swagger.annotations`、`@ApiModel` 或 `API_MODEL_PROPERTY` 殘留；剩下的 52 個命中檔全部位於 `controller/`，屬於其他批次。沒有發現 high 或 medium 問題。

## 驗收標準對照

| AC | 狀態 | 證據 |
|----|------|------|
| AC-1 | ✅（本批部分） | 機器關卡是在完整變更（`fec2266`）上執行，exit 0；`.enableSpringdoc()` 與 `io.swagger.v3.oas.annotations.media.Schema` 都能編譯 |
| AC-2 | N/A（其他批次） | 本批沒有 POM 變更 |
| AC-3 | ✅（本批部分） | 在 `mall-tiny*/src/**/*.java` 以 Grep 搜尋 `io\.swagger\.annotations\|API_MODEL_PROPERTY\|@ApiModel`，命中檔全部位於 `controller/`。mbg、model、domain、dto、generator 目錄都是 0 筆 |
| AC-4 | N/A（其他批次） | — |
| AC-5 | N/A（其他批次） | — |
| AC-6～AC-13 | N/A（其他批次） | 本批只改註解，不影響執行期行為 |
| AC-14 | ✅ | ① Glob 找到 18 個 `CommentGenerator`。除了 `mall-tiny-01`（不在 diff 中，維持原狀）以外，其餘 17 個都已改為 `SCHEMA_FULL_CLASS_NAME="io.swagger.v3.oas.annotations.media.Schema"` 與 `field.addJavaDocLine("@Schema(description = \""+remarks+"\")")`，例如 `mall-tiny-generator/.../mbg/CommentGenerator.java:23,48,58`。② `mall-tiny-plus/.../generator/MyBatisPlusGenerator.java:63` 已改為 `.enableSpringdoc()`。專案沒有自訂 velocity 模板（`mall-tiny-plus/src/main/resources/templates/**` 不存在），因此會使用 3.5.17 內建、支援 springdoc 的模板 |
| AC-15 | N/A（其他批次） | — |
| AC-16 | N/A（其他批次） | — |
| AC-17 | N/A（其他批次） | 本批的 `mall-tiny-02` 只改了 `CommentGenerator` 與 `PmsBrand` 的註解 |

## 問題清單

無

## 範圍外改動

無。60 個檔案都屬於 §5 列出的類別：mbg/model 22、mbg 17、model 9、domain 7、dto 3、modules/pms 1（plus 的 `PmsBrand`），以及 `MyBatisPlusGenerator`。

`mall-tiny-generator` 與 `mall-tiny-mybatis` 的 `UmsAdminRoleRelation.java` 只刪除了原本沒被使用的 `io.swagger.annotations.ApiModelProperty` import，沒有新增 `Schema` import。這是本次遷移直接涉及的 import，符合 §3.2。

## 缺少的測試

無。§3.2／§7 規定不新增測試，AC-14 以程式碼審查驗證。

## Spec 問題

無

## 待確認事項

無

## 給實作者的修正指令

無需修正
