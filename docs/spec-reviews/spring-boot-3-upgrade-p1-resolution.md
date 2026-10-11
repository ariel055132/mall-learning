# spring-boot-3-upgrade 方案審查 第 1 輪：回應紀錄

日期：2026-10-12

## 人類意見（口頭，供下一輪審查者參考）

- H1-1：Java 版本維持使用 21，不要用 17。→ 採納。`java.version` 改為 `21`（根 POM、`mall-tiny-jenkins`），Docker／Fabric8 基底映像連帶改為 `eclipse-temurin:21-jre`（以 21 編譯的 class 無法在 17 JRE 執行），AC-1／AC-5、§1、§4.2、§4.10、§6、§8 同步修改；D-2 標記為已取代，新增 D-13。
- H1-2：其他部分請 Claude 依 Codex 意見判斷處理。→ 依下表逐條查證後處置。

## 對 Codex 意見的回應

| 意見 | 類型 | 處置 | 說明 |
|------|------|------|------|
| P1-1 | blocker | 採納 | 查證 `mall-tiny-boot/.../SecurityConfig.java:56-62` 屬實：白名單只放行 GET／POST，`/admin/login` 另有獨立規則，且不在 `application.yml:32-44` 白名單中。§4.4 改為 A／B／C 三種變體表格，附上變體 B 的規則程式碼與變體 C 的說明，並新增要點「各變體的放行集合（路徑 × method）升級前後必須相同」。新增 AC-16（boot 匿名登入、受保護 API、403、白名單 GET 放行、`PUT` 不被放行），§7 補上對應列。記為 D-14。 |
| P1-2 | blocker | 採納 | 查證 `mall-tiny-redis/.../RedisConfig.java:58` 使用兩參數的 `activateDefaultTyping(ptv, NON_FINAL)`，Jackson 會以 `WRAPPER_ARRAY` 包裝型別資訊，原 AC-12 要求 `@class` 是錯的。AC-12 改為三步驟：升級前寫入快取 → 升級後讀取相同 `data` 且無 `SerializationException` → 刪除後重寫，值為 `["com.macro.mall.tiny.mbg.model.PmsBrand",{...}]` 格式。§4.9 不變。記為 D-15。 |
| P1-3 | suggestion | 採納 | 查證 `CODEBASE_MAP.md:46`、`:59`、`:351` 確實指向 `Swagger2Config`／`matching-strategy`。AC-15 擴大到 §2、§3.1、§7.3、§8.1、§9 共 5 處；§3.1、§5 同步修改；§6 機器關卡新增 `CODEBASE_MAP.md` grep（目前命中的正好就是這 5 處）。記為 D-16。 |

## spec 變更摘要

- meta：狀態 `draft` → `in-review`。
- §1：目標改為 Java 21。
- §2：修改 AC-1（JDK 21）、AC-5（`java.version=21`、`eclipse-temurin:21-jre`）、AC-12（WRAPPER_ARRAY 格式 + 跨版本快取相容）、AC-15（擴大更新範圍並加 grep 條件）；新增 AC-16（`mall-tiny-boot` 安全規則）。AC 編號沒有變動。
- §3.1：Docker 映像改 21；`CODEBASE_MAP.md` 範圍描述擴大。
- §4.2、§4.10：Java 與映像版本改為 21。
- §4.4：改寫為三種變體，補上變體 B／C 規則與「放行集合不變」的要點。
- §5：`CODEBASE_MAP.md` 列出 5 處位置。
- §6：前置條件改 JDK 21；正向 grep 改 21；新增 AC-15 的 `CODEBASE_MAP.md` grep。
- §7：AC-12 列改為相容性驗證；AC-15 改為機器關卡＋審查；新增 AC-16 列。
- §8：新增「Java 21 執行環境」風險；JJWT 風險標題改為 Java 21。
- §8.1：D-2 標記為已由 D-13 取代；新增 D-13～D-16。

## 待人決定

- 無
