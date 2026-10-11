VERDICT: REQUEST_CHANGES

## 摘要

主要遷移範圍與檔案盤點符合現況，但有兩個 blocker：統一的 Security 範本會破壞 `mall-tiny-boot` 的登入與既有授權規則，AC-12 則要求了與保留序列化格式互相矛盾的結果。修正這兩處即可避免實作者照方案完成後仍無法正確驗收。本輪僅做唯讀查證，未執行建置或外部服務測試。

## 上一輪 blocker 追蹤

無

## 意見清單

### [P1-1] Security 遷移遺漏 `mall-tiny-boot` 的登入放行與 HTTP method 限制

- 類型：blocker
- 位置：spec §4.4、§7 / `mall-tiny-boot/src/main/java/com/macro/mall/tiny/config/SecurityConfig.java:56`
- 問題：§4.4 把 `boot` 歸入一般 YAML 白名單版本，但它有額外規則。直接套用範本會讓匿名登入被攔截，也會將原本僅允許 GET／POST 的白名單擴大至所有 method，違反 §3.2「不變更權限規則」。目前 AC-9 只驗證 `04`，無法發現此退化。
- 證據：上述 `SecurityConfig.java:56`、`:58` 分別限定白名單為 GET、POST；`:60` 另行放行 `/admin/login`。`mall-tiny-boot/src/main/resources/application.yml:32` 的白名單沒有登入路徑，而實際登入端點位於 `mall-tiny-boot/src/main/java/com/macro/mall/tiny/controller/UmsAdminController.java:39`。
- 建議：§4.4 明列 `boot` 為第三種變體，保留 GET／POST 限定，以及獨立的 `/admin/login` 放行規則，仍依 D-7 使用明確的 Ant matcher。補上 `boot` 的手動驗收：匿名登入成功、受保護 API 仍需認證、白名單未擴大至其他 method。

### [P1-2] AC-12 的 `@class` 要求與「Redis 序列化格式不變」矛盾

- 類型：blocker
- 位置：spec §2 AC-12、§4.9、§8 / `mall-tiny-redis/src/main/java/com/macro/mall/tiny/config/RedisConfig.java:58`
- 問題：依 §4.9 保留現有設定後，Redis 值使用陣列包裹型別資訊，不會產生 AC-12 要求的 `@class` 欄位。正確保留格式的實作因此無法通過驗收；若為了通過而改成屬性式型別資訊，又違反格式不變的要求。
- 證據：現有程式呼叫兩參數的 `activateDefaultTyping(..., NON_FINAL)`；[Jackson 官方原始碼](https://github.com/FasterXML/jackson-databind/blob/2.19/src/main/java/com/fasterxml/jackson/databind/ObjectMapper.java) 明確將此 overload 委派至 `JsonTypeInfo.As.WRAPPER_ARRAY`。`mall-tiny-redis/src/main/java/com/macro/mall/tiny/mbg/model/PmsBrand.java:6` 是非 final 類別，因此其值形如 `["com.macro.mall.tiny.mbg.model.PmsBrand", {...}]`。
- 建議：將 AC-12 改為驗證上述陣列格式及完整類別名稱，保留 §4.9 的設定。另加入讀取升級前既有快取值的驗證，才能直接確認格式相容性。

### [P1-3] CODEBASE_MAP 的更新範圍漏掉會失效的導覽位置

- 類型：suggestion
- 位置：spec §2 AC-15、§3.1、§5 / `CODEBASE_MAP.md:46`
- 問題：只更新指定的版本表與設定表後，索引仍會引導實作者尋找已刪除的 `Swagger2Config` 與設定鍵。
- 證據：`CODEBASE_MAP.md:46` 指向 `config/Swagger2Config.java` 與 `spring.mvc.pathmatch.matching-strategy`；`:59`、`:351` 也要求參照舊類別。這些內容會因 §4.5、§4.6 的修改而失效。
- 建議：將這三處直接相關的導覽文字納入更新範圍，改為 `SpringDocConfig` 與 `springdoc.packages-to-scan`。

## 遺漏的檔案或相依

無。上述問題涉及的檔案均已列入 §5；需補的是實作規則、驗收內容與文件更新段落。

## 需要人類決定的事項

無
