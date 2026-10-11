VERDICT: APPROVE

## 摘要

上一輪兩個 blocker 均已在新版方案中解決，新增 AC-16 也符合現有帳號、路由及權限規則。Java 21、Docker／Fabric8 映像與 CODEBASE_MAP 更新範圍已同步，未發現新的 blocker。本輪僅做唯讀查證，未執行建置或外部服務驗證。

## 上一輪 blocker 追蹤

| 上一輪編號 | 狀態 | 說明 |
|------------|------|------|
| P1-1 | resolved | spec §4.4 已分列 A／B／C 變體，保留 `boot` 白名單的 GET／POST 限制及獨立登入放行，符合 `mall-tiny-boot/src/main/java/com/macro/mall/tiny/config/SecurityConfig.java:56`、`:58`、`:60`；AC-16 已補上相應驗收。 |
| P1-2 | resolved | AC-12 已改驗證 `WRAPPER_ARRAY`，並加入升級後讀取舊快取的步驟；與 `mall-tiny-redis/src/main/java/com/macro/mall/tiny/config/RedisConfig.java:58` 的設定及 [Jackson 官方實作](https://github.com/FasterXML/jackson-databind/blob/2.19/src/main/java/com/fasterxml/jackson/databind/ObjectMapper.java#L1864) 一致，不再與 §4.9 衝突。 |

## 意見清單

無

## 遺漏的檔案或相依

無

## 需要人類決定的事項

無
