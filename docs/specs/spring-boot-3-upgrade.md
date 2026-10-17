# 全 repo 升級 Spring Boot 2.7.5 → 3.5.16

| 項目 | 內容 |
|------|------|
| 任務代號 | `spring-boot-3-upgrade`（與檔名一致） |
| 狀態 | approved |
| 分支 | `feat/spring-boot-3-upgrade` |
| 建立日期 | 2026-10-11 |
| 核准 | 2026-10-12；依據 docs/spec-reviews/spring-boot-3-upgrade-p2-codex.md（APPROVE）。人類決定在 `spring-boot-3-upgrade` 分支（非 `master`）核准與實作；`review.sh` 需以 `--base <本核准 commit>` 執行 |
| 修訂 | 2026-10-13；加入 D-17（`mall-tiny-02` 執行期改用 PostgreSQL）與 AC-17，人類核准。`review.sh` 改以 `--base <本修訂 commit>` 執行 |
| 修訂 | 2026-10-17；加入 D-18（需 MySQL／Redis／其他外部服務的手動 AC 延後至後續 PostgreSQL 遷移任務驗收），人類核准 |

## 1. 背景與目標

repo 內 22 個範例模組目前建立在 Spring Boot 2.7.5 / Java 8（根 `pom.xml:39`、`mall-tiny-jenkins/pom.xml:41`）。Spring Boot 2.7 已停止 OSS 維護，且 Swagger 使用的 Springfox 3.0.0 無法在 Spring Boot 3 / Spring Framework 6 上運作。目標是把**所有**模組（含不在根 reactor 的 `mall-tiny-alipay`、`mall-tiny-jenkins`）升級到 3.x 最後一條線 **Spring Boot 3.5.16 / Java 21**，完成 `javax.*` → `jakarta.*`、Springfox → springdoc、Spring Security 6 API、相容版本第三方 starter 的替換。做完之後，每個模組都能在 JDK 21 以上編譯，並在相同外部服務下保持原本的 HTTP API、認證與資料行為（Swagger UI 網址除外，見 AC-8）。

## 2. 驗收標準

AC-1～AC-5 由第 6 節機器關卡自動驗證，AC-15 的 grep 部分也在機器關卡內；標註「（手動）」者需啟動應用與外部服務驗證，實作者在 §9 記錄實際結果。依 D-18，AC-6、AC-7、AC-9 步驟 4、AC-11、AC-12、AC-13、AC-16 步驟 2 不在本任務驗收，改由後續 PostgreSQL 遷移任務重新定義並驗收；§9 標示為「延後（D-18）」。

- **AC-1**：在 JDK 21 以上執行 `mvn -B -ntp -DskipTests test-compile`（根 reactor 20 個模組）、以及分別以 `-f mall-tiny-alipay/pom.xml`、`-f mall-tiny-jenkins/pom.xml` 執行同指令時，三次皆 exit 0。（預期結果：輸出含 `BUILD SUCCESS`，無編譯錯誤）
- **AC-2**：上述三個建置的 `dependency:tree` 輸出中，不存在 `io.springfox:*`、`org.springframework.boot:*:jar:2.*`、`org.mybatis.spring.boot:mybatis-spring-boot-(starter|autoconfigure):jar:2.*`、`mysql:mysql-connector-java`、`com.alibaba:druid-spring-boot-starter`（非 `-3-` 版）、`javax.servlet:javax.servlet-api`。
- **AC-3**：`mall-tiny*/src` 下所有 `.java` 檔不含以下字串：`import javax.servlet.`、`import javax.annotation.`、`springfox.`、`io.swagger.annotations.`、`WebSecurityConfigurerAdapter`、`EnableGlobalMethodSecurity`、`.antMatchers(`、`.authorizeRequests()`、`JsqlParserCountOptimize`、`setObjectMapper(`、`v2/api-docs`、`swagger-resources`。
- **AC-4**：所有 `mall-tiny*/src/main/resources/application*.yml` 不含 `matching-strategy`、`v2/api-docs`、`swagger-resources`，也沒有位於 `spring:` 正下方（兩格縮排）的 `redis:` 鍵；所有 `pom.xml` 與 `Dockerfile` 不含 `openjdk:8` 與 `<java.version>1.8</java.version>`。
- **AC-5**：根 `pom.xml` 與 `mall-tiny-jenkins/pom.xml` 的 parent 版本為 `3.5.16`、`<java.version>` 為 `21`；`mall-tiny-docker`、`mall-tiny-jenkins` 的 `Dockerfile` 與 docker/jenkins/alipay 三個 POM 的 Fabric8 `<from>` 皆為 `eclipse-temurin:21-jre`。
- **AC-6**（手動）：MySQL 匯入 `document/sql/mall_tiny.sql` 後啟動 `mall-tiny-01`，`GET /brand/list?pageNum=1&pageSize=3` 回傳 `code=200`、`data.list` 長度 3、`data.total` 等於 `pms_brand` 資料表筆數；首次查詢後應用 log 含 Druid 的 `{dataSource-1} inited`，且不含 `HikariPool`。（驗證 PageHelper、MyBatis starter 3、Druid 3 starter 實際生效，而非靜默退回 Hikari）
- **AC-7**（手動）：啟動 `mall-tiny-plus`，`GET /brand/list?pageNum=1&pageSize=2` 回傳 `data.list` 長度 2，且 `data.total` 等於資料表筆數（不是 0 或 2）。（驗證 MyBatis-Plus 分頁外掛）
- **AC-8**（手動）：啟動 `mall-tiny-02`，`GET /v3/api-docs` 回傳 200 JSON，其中 `info.title` 為 `SwaggerUI演示`、`tags` 含 `PmsBrandController`、`/brand/listAll` 的 GET operation `summary` 為 `获取所有品牌列表`；`GET /swagger-ui/index.html` 回傳 200。舊網址 `/swagger-ui/`、`/v2/api-docs` 不再提供（此為預期的對外變更）。
- **AC-9**（手動）：啟動 `mall-tiny-04`（需 MySQL、Redis），依序：
  1. 不帶 token 呼叫 `GET /brand/listAll` → 回傳 `code=401` 的 JSON（`RestAuthenticationEntryPoint` 輸出），而不是 HTML 或 HTTP 500。
  2. 不帶 token 呼叫 `GET /v3/api-docs`、`GET /swagger-ui/index.html` → 皆 200。
  3. `POST /admin/login?username=admin&password=123456` → `code=200`，`data.token` 非空。
  4. 帶 `Authorization: Bearer <token>` 呼叫 `GET /brand/listAll` → `code=200`。
  5. 以 `macro/123456` 登入取得 token 後呼叫 `GET /brand/list` → 回傳 `code=403` 的 JSON（`RestfulAccessDeniedHandler` 輸出）。
  6. `/v3/api-docs` 中所有 `/brand/` 開頭路徑的 operation 帶有 `security: [{"Authorization": []}]`，`/admin/login` 不帶；`components.securitySchemes.Authorization` 為 `type=apiKey`、`in=header`、`name=Authorization`。
- **AC-10**（手動，錯誤情境）：在 `mall-tiny-04`：
  1. `POST /admin/login?username=admin&password=wrong` → 回傳 `code=404`（`validateFailed`）JSON，HTTP 狀態不是 401/500。
  2. 帶 `Authorization: Bearer abc.def.ghi`（無效 token）呼叫 `GET /brand/listAll` → `code=401` JSON，且應用 log 無未捕捉的例外堆疊導致 500。
  3. 帶有效 admin token 呼叫 `GET /brand/abc`（路徑參數型別錯誤，觸發 `/error` 轉發）→ HTTP 狀態為 400，而不是被安全鏈攔成 401（驗證 D-8）。
- **AC-11**（手動）：啟動 `mall-tiny-03`，`GET /sso/getAuthCode?telephone=13800000000` 回傳 6 位數驗證碼；Redis 中存在 key `portal:authCode:13800000000`，TTL ≤ 120 秒；再以該碼 `POST /sso/verifyAuthCode` 回傳成功。（驗證 `spring.data.redis.*` 設定生效）
- **AC-12**（手動）：驗證 `RedisConfig` 序列化格式不變、與升級前快取相容，以及 SpEL `#id` 參數名稱解析：
  1. 在**升級前**的 `master`（Boot 2.7.5）啟動 `mall-tiny-redis`，呼叫 `GET /brand/1`，記下回應 `data` 與 `redis-cli GET mall::pms:brand:1` 的值。
  2. 不清除 Redis，改啟動**升級後**的 `mall-tiny-redis`，呼叫 `GET /brand/1` → `code=200`，`data` 與步驟 1 相同，log 無 `SerializationException`（證明可讀取舊版寫入的快取）。
  3. `redis-cli DEL mall::pms:brand:1` 後再呼叫一次 `GET /brand/1`，新寫入的值與步驟 1 記下的值格式相同：為 Jackson `WRAPPER_ARRAY` 型別包裝，即 `["com.macro.mall.tiny.mbg.model.PmsBrand",{...}]`（第一個元素是完整類別名稱），**不是**含 `@class` 屬性的物件；`redis-cli TTL` 約 86400 秒。
- **AC-13**（手動，需 Elasticsearch 8.x + IK 分詞、MongoDB、RabbitMQ、MinIO）：啟動 `mall-tiny`，`POST /esProduct/importAll` 回傳匯入筆數 > 0；`GET /esProduct/search/simple?keyword=小米` 回傳結果；`POST /member/readHistory/create` 後 `GET /member/readHistory/list` 可讀回；`POST /order/generateOrder` 後 log 出現延遲取消訊息；`POST /minio/upload` 上傳圖片回傳可存取的 URL。若無法提供某項服務，於 §9 明確列出「未驗證」項目，不得標示為通過。
- **AC-14**：所有含 `@ApiModelProperty` 產生邏輯的 `mbg/CommentGenerator.java`（17 個模組，見 §5）改為產生 `@Schema(description = "<remarks>")` 並匯入 `io.swagger.v3.oas.annotations.media.Schema`；`mall-tiny-plus` 的 `MyBatisPlusGenerator` 使用 `.enableSpringdoc()` 取代 `.enableSwagger()`。（以程式碼審查確認，不需實際執行產碼）
- **AC-15**：`CODEBASE_MAP.md` 中下列位置反映本次升級後的版本、類別與設定鍵：§2 快速索引「Swagger 顯示、掃描範圍、Authorization」列（改指向 `J/config/SpringDocConfig.java` 與 YAML `springdoc.packages-to-scan`）、§3.1 `mall-tiny-02` 列（`SpringDocConfig`）、§7.3 版本表與其下方說明段落、§8.1 設定表中的 `spring.redis.*` 列（改 `spring.data.redis.*`）、§9 中「依該模組的 `Swagger2Config`」的敘述（改 `SpringDocConfig`）。完成後 `grep -nE 'Swagger2Config|matching-strategy|ANT_PATH_MATCHER|2\.7\.5|spring\.redis\.' CODEBASE_MAP.md` 無輸出；Java target 寫為 `21`。
- **AC-16**（手動）：啟動 `mall-tiny-boot`（port 8088，需 MySQL），驗證變體 B 的放行規則未改變：
  1. 不帶 token `POST /admin/login?username=admin&password=123456` → `code=200`，`data.token` 非空（`/admin/login` 不在 YAML 白名單中，靠獨立規則放行）。
  2. 不帶 token `GET /brand/listAll` → `code=401` JSON；帶上一步 token → `code=200`。
  3. 以 `macro/123456`（`ROLE_USER`）的 token 呼叫 `GET /brand/list` → `code=403` JSON。
  4. 不帶 token `GET /v3/api-docs` → 200（白名單 GET 放行）。
  5. 不帶 token `PUT /favicon.ico` → `code=401` JSON（白名單只放行 GET／POST，未擴大到其他 method）。
- **AC-17**（手動＋程式碼審查，D-17）：`mall-tiny-02` 改連 PostgreSQL：
  1. 程式碼審查：`mall-tiny-02/pom.xml` 以 `org.postgresql:postgresql`（runtime、不寫 version）取代 MySQL driver；`application.yml` 的 datasource 為 `jdbc:postgresql://...`，密碼只來自 `PG_PASSWORD` 環境變數，repo 中不含實際密碼；`pagehelper.helper-dialect` 為 `postgresql`；`PmsBrandMapper.xml` 的 `insert`／`insertSelective` 不含 `LAST_INSERT_ID()`，改用 `useGeneratedKeys`。其他模組的 datasource 與 driver 仍為 MySQL。
  2. 在已匯入 `document/sql/mall_tiny_postgre.sql` 的 PostgreSQL 上（設定 `PG_PASSWORD`）啟動 `mall-tiny-02`，`GET /brand/list?pageNum=1&pageSize=3` 回傳 `code=200`、`data.list` 長度 3、`data.total` 等於 `pms_brand` 筆數。
  3. `POST /brand/create` 回傳 `code=200` 且 `data.id` 非空；以該 id `GET /brand/{id}` 可讀回；驗證後刪除該筆資料。

## 3. 範圍

### 3.1 範圍內

- 根 `pom.xml` 與 22 個模組 `pom.xml`（含 `mall-tiny-alipay`、獨立 parent 的 `mall-tiny-jenkins`）的 parent、Java 版本、依賴座標與版本。
- `javax.servlet.*`、`javax.annotation.PostConstruct` → `jakarta.*`。
- Springfox → springdoc-openapi：刪除 20 個 `config/Swagger2Config.java`，新增同模組的 `config/SpringDocConfig.java`；所有 Swagger 2 註解（`io.swagger.annotations.*`）改為 OpenAPI 3 註解（`io.swagger.v3.oas.annotations.*`）。
- MyBatis Generator 的 `CommentGenerator` 與 MyBatis-Plus 產碼器改為產生 OpenAPI 3 註解。
- 8 個 `SecurityConfig.java` 改用 Spring Security 6 API。
- 8 個 `RedisConfig.java` 改用非棄用的 `Jackson2JsonRedisSerializer` 建構子。
- `mall-tiny-plus` 的 `MyBatisConfig.java` 移除已不存在的 import。
- `application*.yml`：`spring.redis.*` → `spring.data.redis.*`、移除 `spring.mvc.pathmatch.matching-strategy`、Swagger 白名單路徑、新增 `springdoc.packages-to-scan`、`management.endpoint.shutdown.enabled` → `access`、alipay 的 `returnUrl`。
- Docker 基底映像 `openjdk:8` → `eclipse-temurin:21-jre`（Dockerfile 與 Fabric8 設定）。
- `CODEBASE_MAP.md` 中與版本、Swagger 設定類別、設定鍵直接相關的導覽與段落（§2、§3.1、§7.3、§8.1、§9 的指定位置，見 AC-15）。
- `mall-tiny-02` 執行期改用 PostgreSQL（D-17）：driver、`application.yml` 的 datasource 與 PageHelper 方言、`PmsBrandMapper.xml` 的主鍵回填；`CODEBASE_MAP.md` 中說明該模組資料庫的段落。

### 3.2 非目標（禁止事項）

- 不重構、不重新命名與本任務無關的程式碼（`Swagger2Config` → `SpringDocConfig` 為本任務的一部分，例外）。
- 不做無關的格式化（例如整檔 reformat、import 重新排序）；只移除／新增本次變更直接涉及的 import。既有程式註解維持原本的簡體中文，新增註解比照周邊風格。
- 不新增或升級依賴，除非已列在第 4 節版本表或 D-17（`mall-tiny-02` 的 PostgreSQL driver）。特別是：**不升級 JJWT（維持 0.9.1）、不升級 Hutool、MinIO、Alipay SDK、mybatis-generator-core、Fabric8 plugin、velocity**。
- 不變更任何 HTTP API 路徑、參數、回應格式、錯誤碼與權限規則；Swagger UI／API docs 網址變更除外（AC-8）。不新增 trailing slash 相容設定。
- 不升級到 Spring Boot 4.x；不把 `AntPathRequestMatcher` 改為 `PathPatternRequestMatcher`（屬 Boot 4 遷移範圍）。
- 不重新執行 MyBatis Generator／MyBatis-Plus 產碼器重新產生 model 或 mapper；既有產生檔的註解以手動（文字替換）方式改寫。
- 不修改 `docs/`（Docsify 教學文章）、`README.md`、`document/`、SQL 檔。
- 不新增 Maven Wrapper、不改 `skipTests`、不新增或修改測試類別。
- 不修改 `docker-compose.yml`（含 MySQL 5.7 映像）、`mall-tiny-jenkins.sh`，也不修正 Jenkins Dockerfile 既有的 jar 名稱／port 不一致（只改 `FROM` 行）。
- 不移除 §4.2 未點名的既有 POM properties（例如未使用的 `mybatis.version`、`aliyun-oss.version`、`logstash-logback.version`）。
- 不改變 `JwtAuthenticationTokenFilter` 以 `@Bean` 註冊的方式。
- 不修改 `.idea/`、`scripts/`、`.claude/`、`db-tunnel.sh`。
- 不修改本 spec 的第 1～8 節。
- 不執行 `git commit`、`git push`。

## 4. 設計與實作要點

- **方案**：一次性把所有模組升到 Spring Boot 3.5.16，透過「改 POM → 修編譯錯誤 → 改設定檔 → 手動驗證代表模組」完成。各模組是彼此獨立的副本（同名類別不共用），同一類變更需要逐模組套用相同改法。
- **關鍵決策**：見 §8.1（D-1～D-12）。

### 4.1 執行順序（建議）

1. 根 `pom.xml` → 讓根 reactor 能解析依賴。
2. 逐類修正編譯錯誤：jakarta → Security → springdoc config → Swagger 註解 → Redis → MyBatis-Plus。
3. `mall-tiny-alipay`、`mall-tiny-jenkins` 的 POM 與程式。
4. YAML、Dockerfile、`CODEBASE_MAP.md`。
5. 跑第 6 節機器關卡，再做手動 AC。

### 4.2 POM 變更

**根 `pom.xml`**

| 項目 | 變更前 | 變更後 |
|------|--------|--------|
| parent `spring-boot-starter-parent` | `2.7.5` | `3.5.16` |
| `java.version` | `1.8` | `21` |
| `pagehelper-starter.version` | `1.4.5` | `2.1.1` |
| `mybatis-starter.version` | `2.2.2` | `3.0.5` |
| `druid.version` | `1.2.14` | `1.2.28`（座標改為 `druid-spring-boot-3-starter`，見下） |
| `springfox-swagger.version` | `3.0.0` | **刪除**，新增 `springdoc.version` = `2.9.1` |
| `mysql-connector.version` | `8.0.29` | **刪除**（改由 Boot 管理，見下） |
| `spring-data-commons.version`、`swagger-models.version`、`swagger-annotations.version` | `2.7.5`／`1.6.0`／`1.6.0` | **刪除**（未被引用且為 Boot 2／Springfox 時代的值） |
| 其餘 properties | — | 不變（含 `jjwt.version` 0.9.1、`jaxb-api.version` 2.3.1、`hutool.version`、`minio.version`） |
| `<dependencies>` 中的 `javax.xml.bind:jaxb-api` | 保留 | 保留（JJWT 0.9.1 執行期需要 `javax.xml.bind.DatatypeConverter`，見 D-6） |

根 `pom.xml` 新增 `<dependencyManagement>`，強制 PageHelper 傳遞進來的 MyBatis starter 使用 3.x（PageHelper starter 2.1.1 的 POM 宣告 `mybatis-spring-boot` 2.3.2，那是 Boot 2 版本，見 D-4）：

```xml
<dependencyManagement>
    <dependencies>
        <dependency>
            <groupId>org.mybatis.spring.boot</groupId>
            <artifactId>mybatis-spring-boot-starter</artifactId>
            <version>${mybatis-starter.version}</version>
        </dependency>
        <dependency>
            <groupId>org.mybatis.spring.boot</groupId>
            <artifactId>mybatis-spring-boot-autoconfigure</artifactId>
            <version>${mybatis-starter.version}</version>
        </dependency>
    </dependencies>
</dependencyManagement>
```

**各模組 `pom.xml`（依實際有宣告者套用）**

| 舊依賴 | 新依賴 |
|--------|--------|
| `io.springfox:springfox-boot-starter:${springfox-swagger.version}` | `org.springdoc:springdoc-openapi-starter-webmvc-ui:${springdoc.version}` |
| `com.alibaba:druid-spring-boot-starter:${druid.version}` | `com.alibaba:druid-spring-boot-3-starter:${druid.version}` |
| `mysql:mysql-connector-java:${mysql-connector.version}` | `com.mysql:mysql-connector-j`（**不寫 version**，由 Boot 管理） |
| `mall-tiny-plus`：`com.baomidou:mybatis-plus-boot-starter:3.5.3` | `com.baomidou:mybatis-plus-spring-boot3-starter:3.5.17` **以及** 新增 `com.baomidou:mybatis-plus-jsqlparser:3.5.17`（`PaginationInnerInterceptor` 自 3.5.9 起移到此 artifact，套件名稱不變） |
| `mall-tiny-plus`：`com.baomidou:mybatis-plus-generator:3.5.3` | `3.5.17` |
| docker／jenkins／alipay 的 Fabric8 `<from>openjdk:8</from>` | `<from>eclipse-temurin:21-jre</from>` |
| `mall-tiny-02`：`mysql:mysql-connector-java:${mysql-connector.version}` | `org.postgresql:postgresql`（`runtime` scope，**不寫 version**，由 Boot 管理；D-17） |

**`mall-tiny-jenkins/pom.xml`**（獨立 parent，不繼承根 POM）：parent 改 `3.5.16`、`java.version` 改 `21`，properties 與依賴座標比照根 POM 與上表同步修改，並加入同樣的 `<dependencyManagement>` 區塊。

### 4.3 jakarta 命名空間

只改 import，不改程式邏輯：

- `javax.servlet.*` → `jakarta.servlet.*`：8 個模組（`mall-tiny`、`04`～`08`、`boot`、`swagger`）的 `component/{JwtAuthenticationTokenFilter,RestAuthenticationEntryPoint,RestfulAccessDeniedHandler}.java`，以及 `mall-tiny-alipay/.../AlipayController.java`、`mall-tiny-hutool/.../HutoolController.java`。
- `javax.annotation.PostConstruct` → `jakarta.annotation.PostConstruct`：上述 8 個模組的 `service/impl/UmsAdminServiceImpl.java`。
- **不要**改 `javax.xml.bind`（無 Java 程式直接使用；JJWT 內部需要）。

### 4.4 Spring Security 6（8 個 `config/SecurityConfig.java`）

三種現況，**各自的放行規則（路徑 × HTTP method）必須原樣保留**，只換 API：

| 變體 | 模組 | 現有放行規則 | 改寫後 |
|------|------|--------------|--------|
| A. YAML 白名單、不限 method | `mall-tiny`、`04`～`08` | 每個 `ignoreUrlsConfig.getUrls()` 以 `antMatchers(url)` 放行（所有 method）；`antMatchers(HttpMethod.OPTIONS)` 放行 | 下方範本 |
| B. YAML 白名單、限 GET／POST，另放行登入 | `boot` | `mall-tiny-boot/.../SecurityConfig.java:56` `antMatchers(HttpMethod.GET, urlArray)`、`:58` `antMatchers(HttpMethod.POST, urlArray)`、`:60` `antMatchers("/admin/login")`（所有 method）、`:62` OPTIONS | 見範本下方「變體 B」 |
| C. 寫死在 Java、限 GET，另放行登入 | `swagger` | `antMatchers(HttpMethod.GET, "/", "/swagger-ui/", ...)`、`antMatchers("/admin/login")`（所有 method）、OPTIONS | 見範本下方「變體 C」 |

變體 A 的改法如下（B、C 只有 `authorizeHttpRequests` 內的放行規則不同，其餘鏈設定相同）：

```java
@Configuration
@EnableWebSecurity
@EnableMethodSecurity
public class SecurityConfig {
    // 既有 @Autowired 欄位維持不變

    @Bean
    SecurityFilterChain filterChain(HttpSecurity httpSecurity) throws Exception {
        httpSecurity.authorizeHttpRequests(registry -> {
                    //不需要保护的资源路径允许访问
                    for (String url : ignoreUrlsConfig.getUrls()) {
                        registry.requestMatchers(AntPathRequestMatcher.antMatcher(url)).permitAll();
                    }
                    //允许跨域请求的OPTIONS请求
                    registry.requestMatchers(AntPathRequestMatcher.antMatcher(HttpMethod.OPTIONS, "/**")).permitAll();
                    //错误页转发不再鉴权，保持与旧版行为一致
                    registry.dispatcherTypeMatchers(DispatcherType.ERROR).permitAll();
                    //除上面外的所有请求全部需要鉴权认证
                    registry.anyRequest().authenticated();
                })
                // 由于使用的是JWT，我们这里不需要csrf
                .csrf(AbstractHttpConfigurer::disable)
                // 基于token，所以不需要session
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                // 禁用缓存
                .headers(headers -> headers.cacheControl(Customizer.withDefaults()))
                // 添加JWT filter
                .addFilterBefore(jwtAuthenticationTokenFilter(), UsernamePasswordAuthenticationFilter.class)
                //添加自定义未授权和未登录结果返回
                .exceptionHandling(exception -> exception
                        .accessDeniedHandler(restfulAccessDeniedHandler)
                        .authenticationEntryPoint(restAuthenticationEntryPoint));
        return httpSecurity.build();
    }
    // passwordEncoder()、jwtAuthenticationTokenFilter()、（boot/swagger 的）userDetailsService() 維持不變
}
```

**變體 B（`mall-tiny-boot`）**：`authorizeHttpRequests` 內改為下列規則，順序照舊；`List<String> urls`／`urlArray` 的取得方式可保留或改為直接迴圈，但不得放寬 method：

```java
for (String url : ignoreUrlsConfig.getUrls()) {
    // 允许对于网站静态资源的无授权访问
    registry.requestMatchers(AntPathRequestMatcher.antMatcher(HttpMethod.GET, url)).permitAll();
    registry.requestMatchers(AntPathRequestMatcher.antMatcher(HttpMethod.POST, url)).permitAll();
}
// 对登录注册要允许匿名访问
registry.requestMatchers(AntPathRequestMatcher.antMatcher("/admin/login")).permitAll();
//跨域请求会先进行一次options请求
registry.requestMatchers(AntPathRequestMatcher.antMatcher(HttpMethod.OPTIONS, "/**")).permitAll();
registry.dispatcherTypeMatchers(DispatcherType.ERROR).permitAll();
registry.anyRequest().authenticated();
```

**變體 C（`mall-tiny-swagger`）**：寫死清單中的每個路徑以 `AntPathRequestMatcher.antMatcher(HttpMethod.GET, path)` 放行（路徑依 §4.6 換成新 Swagger 路徑，其他路徑不變），`/admin/login` 以不帶 method 的 `antMatcher("/admin/login")` 放行，接著 OPTIONS、ERROR dispatch、`anyRequest().authenticated()`，與變體 B 同結構。

要點：
- `@EnableGlobalMethodSecurity(prePostEnabled=true)` → `@EnableMethodSecurity`（預設即啟用 `@PreAuthorize`）。
- 各變體的放行集合（路徑 × method）在升級前後必須相同；唯一新增的是 ERROR dispatch 放行（D-8）。
- 一律使用 `AntPathRequestMatcher.antMatcher(...)` 明確指定 Ant 語意，**不要**用 `requestMatchers(String...)`：白名單含 `/**/*.html` 這類 `**` 在中間的樣式，PathPattern 解析器不支援；且 `requestMatchers(String)` 在多個 Servlet 註冊時會丟例外（見 D-7）。`AntPathRequestMatcher` 在 Security 6.5 有棄用警告，可接受。
- 必須加上 `dispatcherTypeMatchers(DispatcherType.ERROR).permitAll()`：Security 6 的 `authorizeHttpRequests` 會對 ERROR dispatch 也做授權，不加的話，例外轉發 `/error` 時會被改寫成 401（AC-10）。`DispatcherType` 來自 `jakarta.servlet`。
- 刪除已不存在或不再使用的 import：`WebSecurityConfigurerAdapter`、`ExpressionUrlAuthorizationConfigurer`、`EnableGlobalMethodSecurity`，以及本來就未使用的 `AuthenticationManager`、`AuthenticationManagerBuilder`（若仍被引用則保留）。

### 4.5 springdoc 設定（取代 20 個 `config/Swagger2Config.java`）

刪除各模組 `config/Swagger2Config.java`（包含其中為 Springfox 而寫的 `BeanPostProcessor`），在同一目錄新增 `config/SpringDocConfig.java`。涉及模組：`02`～`08`、`mall-tiny`、`alipay`、`boot`、`docker`、`generator`、`hutool`、`jenkins`、`mybatis`、`plus`、`rabbit`、`redis`、`stream`、`swagger`（`01`、`lombok` 沒有 Swagger）。

```java
@Configuration
public class SpringDocConfig {

    private static final String SECURITY_SCHEME_NAME = "Authorization";

    @Bean
    public OpenAPI mallTinyOpenAPI() {
        return new OpenAPI()
                .info(new Info().title("SwaggerUI演示")
                        .description("mall-tiny")
                        .contact(new Contact().name("macro"))
                        .version("1.0"))
                //添加登录认证（仅原本配置了 securitySchemes 的模块需要）
                .components(new Components().addSecuritySchemes(SECURITY_SCHEME_NAME,
                        new SecurityScheme().type(SecurityScheme.Type.APIKEY)
                                .in(SecurityScheme.In.HEADER)
                                .name(SECURITY_SCHEME_NAME)));
    }

    //设置需要登录认证的路径（仅原本配置了 securityContexts 的模块需要）
    @Bean
    public OpenApiCustomizer brandSecurityCustomizer() {
        return openApi -> {
            if (openApi.getPaths() == null) {
                return;
            }
            openApi.getPaths().forEach((path, pathItem) -> {
                if (path.startsWith("/brand/")) {
                    pathItem.readOperations().forEach(operation ->
                            operation.addSecurityItem(new SecurityRequirement().addList(SECURITY_SCHEME_NAME)));
                }
            });
        };
    }
}
```

- **需要認證設定**（原本有 `securitySchemes()` 與 `getContextByPath("/brand/.*")`）：`mall-tiny`、`04`～`08`、`boot`、`mybatis`、`rabbit`、`swagger`。這些模組保留 `.components(...)` 與 `brandSecurityCustomizer`。
- **不需要**（原本只有 `apiInfo`）：`02`、`03`、`alipay`、`docker`、`generator`、`hutool`、`jenkins`、`plus`、`redis`、`stream`。這些模組的 `SpringDocConfig` 只有 `mallTinyOpenAPI()` 且不呼叫 `.components(...)`，也不定義 `brandSecurityCustomizer`。
- 掃描範圍：原 `RequestHandlerSelectors.basePackage(...)` 改為在各模組 `application.yml` 加上：
  ```yaml
  springdoc:
    packages-to-scan: com.macro.mall.tiny.controller   # mall-tiny-plus 用 com.macro.mall.tiny.modules
  ```
- `OpenApiCustomizer` 的套件為 `org.springdoc.core.customizers.OpenApiCustomizer`；模型類別來自 `io.swagger.v3.oas.models.*`。

### 4.6 Swagger 白名單與網址

- YAML 的 `secure.ignored.urls`（`mall-tiny`、`04`～`08`、`boot`）：刪除 `/swagger-ui/`、`/swagger-resources/**`、`/**/v2/api-docs`、`/v2/api-docs/**`，在原位置加入 `/swagger-ui/**`、`/swagger-ui.html`、`/v3/api-docs/**`。其他項目不動。
- `mall-tiny-swagger/.../SecurityConfig.java` 寫死的清單同樣替換（`HttpMethod.GET` 限定保留）。
- 所有 `application.yml` 刪除 `spring.mvc.pathmatch.matching-strategy`（只為 Springfox 存在；已確認所有 Controller 映射都不含萬用字元）。若刪除後 `spring.mvc` 底下沒有其他鍵，連同空的 `mvc:` 一起刪除。
- `mall-tiny-alipay/src/main/resources/application.yml` 的 `returnUrl: http://localhost:8080/swagger-ui/` → `http://localhost:8080/swagger-ui/index.html`。

### 4.7 Swagger 2 → OpenAPI 3 註解對照（111 個 `.java` 檔）

| 舊註解 | 新註解 |
|--------|--------|
| `@Api(tags = "X")`（類別上已有 `@Tag`） | 直接刪除 `@Api` 那一行 |
| `@Api(tags = "X", description = "D")`（類別上沒有 `@Tag`：`mall-tiny-plus`、`mall-tiny-stream` 的 `PmsBrandController`） | `@Tag(name = "X", description = "D")` |
| `@ApiOperation("S")` / `@ApiOperation(value = "S")` | `@Operation(summary = "S")` |
| `@ApiOperation(value = "S", notes = "N")` | `@Operation(summary = "S", description = "N")` |
| `@ApiParam("D")` / `@ApiParam(value = "D")` | `@Parameter(description = "D")` |
| `@ApiParam(value = "D", required = true)` | `@Parameter(description = "D", required = true)` |
| `@ApiModel(value = "V", description = "D")` | `@Schema(description = "D")`（捨棄 `value`，模型名稱維持類別名稱） |
| `@ApiModelProperty("D")` / `@ApiModelProperty(value = "D")` | `@Schema(description = "D")` |
| `@ApiImplicitParams({@ApiImplicitParam(name = "n", value = "D", required = true, dataTypeClass = String.class), ...})`（僅 `mall-tiny-swagger` 的 `UmsAdminController.login`） | `@Parameters({@Parameter(name = "n", description = "D", required = true, in = ParameterIn.QUERY), ...})` |

- import 對應：`io.swagger.v3.oas.annotations.{Operation, Parameter, Parameters}`、`io.swagger.v3.oas.annotations.enums.ParameterIn`、`io.swagger.v3.oas.annotations.media.Schema`、`io.swagger.v3.oas.annotations.tags.Tag`。已存在的 `io.swagger.v3...ApiResponse(s)`、`Tag` import 保留。
- 只替換註解與相關 import；字串內容一字不改。

### 4.8 產碼器

- 17 個 `mbg/CommentGenerator.java`（`02`～`08`、`mall-tiny`、`alipay`、`boot`、`docker`、`generator`、`jenkins`、`mybatis`、`redis`、`stream`、`swagger`）：
  - 常數 `API_MODEL_PROPERTY_FULL_CLASS_NAME = "io.swagger.annotations.ApiModelProperty"` → 改名為 `SCHEMA_FULL_CLASS_NAME`，值 `"io.swagger.v3.oas.annotations.media.Schema"`，並更新引用處。
  - `field.addJavaDocLine("@ApiModelProperty(value = \"" + remarks + "\")")` → `field.addJavaDocLine("@Schema(description = \"" + remarks + "\")")`。
  - `mall-tiny-01` 的 `CommentGenerator` 不含 Swagger，不動。
- `mall-tiny-plus/.../generator/MyBatisPlusGenerator.java`：`.enableSwagger()` → `.enableSpringdoc()`（3.5.17 API 已確認存在）。其他 Builder 方法在 3.5.17 皆存在，不需改。

### 4.9 其他程式

- 8 個 `config/RedisConfig.java`（`mall-tiny`、`03`～`08`、`redis`）：
  ```java
  ObjectMapper objectMapper = new ObjectMapper();
  objectMapper.setVisibility(PropertyAccessor.ALL, JsonAutoDetect.Visibility.ANY);
  objectMapper.activateDefaultTyping(LaissezFaireSubTypeValidator.instance, ObjectMapper.DefaultTyping.NON_FINAL);
  return new Jackson2JsonRedisSerializer<>(objectMapper, Object.class);
  ```
  取代 `new Jackson2JsonRedisSerializer<>(Object.class)` + `setObjectMapper(...)`。序列化格式不變。
- `mall-tiny-plus/.../config/MyBatisConfig.java`：刪除 `import ...pagination.optimize.JsqlParserCountOptimize;`（3.5.17 已移除該類別；原程式未使用）。

### 4.10 設定檔

- `spring.redis.*` → `spring.data.redis.*`（`mall-tiny`、`03`～`08`、`redis`）。**注意**：`mall-tiny`、`05`～`08` 的 `spring:` 下已經有 `data:`（elasticsearch／mongodb），`redis:` 區塊必須併入既有的 `data:` 之下，不可再新增第二個 `data:` 鍵（YAML 重複鍵會導致啟動失敗）。子鍵（host、port、database、password、lettuce.pool.*）原樣搬移。
- 頂層自訂的 `redis.key.*`（0 格縮排）不是 Spring 屬性，**不動**。
- `mall-tiny-boot`：`management.endpoint.shutdown.enabled: true` → `management.endpoint.shutdown.access: unrestricted`。
- Dockerfile（`mall-tiny-docker`、`mall-tiny-jenkins` 的 `src/main/docker/Dockerfile`）：`FROM openjdk:8` → `FROM eclipse-temurin:21-jre`，其餘行不動。

### 4.11 資料結構 / API 變更

- HTTP API：無變更。
- 對外可見變更：Swagger UI 由 `/swagger-ui/` 改為 `/swagger-ui/index.html`；API 文件由 `/v2/api-docs`（Swagger 2.0）改為 `/v3/api-docs`（OpenAPI 3）。
- Spring 6 預設不再做 trailing slash 比對：`/brand/list/` 不再等同 `/brand/list`（接受此變更，見 D-9）。

## 5. 預計異動的檔案

`<M>` 代表該列括號中列出的模組；`J/` = `src/main/java/com/macro/mall/tiny/`，`R/` = `src/main/resources/`。

| 檔案 | 動作 | 說明 |
|------|------|------|
| `pom.xml` | 修改 | §4.2 根 POM |
| `<M>/pom.xml`（全部 22 個模組） | 修改 | §4.2 依賴座標；`mall-tiny-jenkins` 另改 parent／properties |
| `<M>/J/component/{JwtAuthenticationTokenFilter,RestAuthenticationEntryPoint,RestfulAccessDeniedHandler}.java`（`mall-tiny`、`04`～`08`、`boot`、`swagger`） | 修改 | jakarta |
| `<M>/J/service/impl/UmsAdminServiceImpl.java`（同上 8 模組） | 修改 | jakarta `@PostConstruct` |
| `mall-tiny-alipay/J/controller/AlipayController.java`、`mall-tiny-hutool/J/controller/HutoolController.java` | 修改 | jakarta + 註解 |
| `<M>/J/config/SecurityConfig.java`（同上 8 模組） | 修改 | §4.4 |
| `<M>/J/config/Swagger2Config.java`（20 模組，見 §4.5） | 刪除 | Springfox 設定 |
| `<M>/J/config/SpringDocConfig.java`（20 模組，見 §4.5） | 新增 | springdoc 設定 |
| 所有 import `io.swagger.annotations.*` 的 `.java`（111 檔：controller 51、mbg/model 22、mbg 17（即 CommentGenerator）、model 9、domain 7、dto 3、modules/pms 2） | 修改 | §4.7／§4.8 註解替換 |
| `mall-tiny-plus/J/generator/MyBatisPlusGenerator.java` | 修改 | `.enableSpringdoc()` |
| `mall-tiny-plus/J/config/MyBatisConfig.java` | 修改 | 移除失效 import |
| `<M>/J/config/RedisConfig.java`（`mall-tiny`、`03`～`08`、`redis`） | 修改 | §4.9 |
| `<M>/R/application.yml`（20 個含 `matching-strategy` 的模組） | 修改 | 移除 pathmatch、加 `springdoc.packages-to-scan`；其中 8 個改 `spring.data.redis`、7 個改白名單、`boot` 改 shutdown、`alipay` 改 returnUrl |
| `mall-tiny-docker/src/main/docker/Dockerfile`、`mall-tiny-jenkins/src/main/docker/Dockerfile` | 修改 | 基底映像 |
| `mall-tiny-02/pom.xml`、`mall-tiny-02/R/application.yml`、`mall-tiny-02/R/com/macro/mall/tiny/mbg/mapper/PmsBrandMapper.xml` | 修改 | D-17：PostgreSQL driver、datasource、PageHelper 方言、`useGeneratedKeys` |
| `CODEBASE_MAP.md` | 修改 | AC-15 指定的 5 處（約第 46、59、268～275、288、351 行）；另依 D-17 補充 `mall-tiny-02` 使用 PostgreSQL 的說明 |
| `docs/specs/spring-boot-3-upgrade.md` | 修改 | 僅第 9 節 |

## 6. 驗證指令

前置條件：JDK 21 以上、Maven 3.6.3 以上在 `PATH`（目前 repo 沒有 Maven Wrapper）；於 repo 根目錄執行。只跑到 `test-compile`，避免 docker／jenkins／alipay 綁在 `package` phase 的 Fabric8 `docker:build` 去連遠端 Docker daemon。

```bash
log="$(mktemp)"
mvn -B -ntp -DskipTests test-compile dependency:tree | tee "$log"
mvn -B -ntp -DskipTests -f mall-tiny-alipay/pom.xml test-compile dependency:tree | tee -a "$log"
mvn -B -ntp -DskipTests -f mall-tiny-jenkins/pom.xml test-compile dependency:tree | tee -a "$log"
if grep -nE 'io\.springfox:|org\.springframework\.boot:[a-z0-9-]+:jar:2\.|org\.mybatis\.spring\.boot:mybatis-spring-boot-(starter|autoconfigure):jar:2\.|mysql:mysql-connector-java:|com\.alibaba:druid-spring-boot-starter:|javax\.servlet:javax\.servlet-api:' "$log"; then echo 'FAIL(AC-2): 依賴樹仍含 Boot 2 時代套件'; exit 1; fi
if grep -rnE --include='*.java' 'import javax\.(servlet|annotation)\.|springfox\.|io\.swagger\.annotations\.|WebSecurityConfigurerAdapter|EnableGlobalMethodSecurity|\.antMatchers\(|\.authorizeRequests\(\)|JsqlParserCountOptimize|setObjectMapper\(|v2/api-docs|swagger-resources' mall-tiny*/src; then echo 'FAIL(AC-3): 原始碼殘留舊 API'; exit 1; fi
if grep -nE '^  redis:|matching-strategy|v2/api-docs|swagger-resources' mall-tiny*/src/main/resources/application*.yml; then echo 'FAIL(AC-4): 設定檔殘留舊鍵或舊路徑'; exit 1; fi
if grep -rnE --exclude-dir=target --exclude-dir=.git --include=pom.xml --include=Dockerfile 'openjdk:8|<java\.version>1\.8</java\.version>' .; then echo 'FAIL(AC-4): 仍有 Java 8 設定'; exit 1; fi
grep -q '<version>3.5.16</version>' pom.xml
grep -q '<version>3.5.16</version>' mall-tiny-jenkins/pom.xml
grep -q '<java.version>21</java.version>' pom.xml
grep -q '<java.version>21</java.version>' mall-tiny-jenkins/pom.xml
grep -q '^FROM eclipse-temurin:21-jre' mall-tiny-docker/src/main/docker/Dockerfile
grep -q '^FROM eclipse-temurin:21-jre' mall-tiny-jenkins/src/main/docker/Dockerfile
test "$(grep -l '<from>eclipse-temurin:21-jre</from>' mall-tiny-docker/pom.xml mall-tiny-jenkins/pom.xml mall-tiny-alipay/pom.xml | wc -l)" -eq 3
if grep -nE 'Swagger2Config|matching-strategy|ANT_PATH_MATCHER|2\.7\.5|spring\.redis\.' CODEBASE_MAP.md; then echo 'FAIL(AC-15): CODEBASE_MAP 仍有過時敘述'; exit 1; fi
echo 'ALL CHECKS PASSED'
```

註：腳本由 `bash -eo pipefail` 執行；反向檢查刻意寫成 `if grep …; then exit 1; fi`，因為 `set -e` 不會對 `! grep` 生效。

## 7. 測試要求

本 repo 根 POM 設 `skipTests=true`，既有測試幾乎都是需要 MySQL／Redis 等外部服務的 `@SpringBootTest contextLoads()`，本任務**不新增**自動化測試（見 §3.2）。驗收以「第 6 節機器關卡 + 手動驗證」完成；手動結果由實作者記錄於 §9（貼上關鍵的 curl 回應或 log 片段）。

| AC | 驗證方式 | 位置／步驟 |
|----|----------|------------|
| AC-1 | 機器關卡 | §6 前三行 `mvn` |
| AC-2 | 機器關卡（依賴樹 grep） | §6 |
| AC-3 | 機器關卡（原始碼 grep） | §6 |
| AC-4 | 機器關卡（YAML／POM／Dockerfile grep） | §6 |
| AC-5 | 機器關卡（正向 grep） | §6 |
| AC-6 | 手動 | `mvn -pl mall-tiny-01 spring-boot:run` + curl |
| AC-7 | 手動 | `mvn -pl mall-tiny-plus spring-boot:run` + curl |
| AC-8 | 手動 | `mvn -pl mall-tiny-02 spring-boot:run` + curl／瀏覽器 |
| AC-9 | 手動 | `mvn -pl mall-tiny-04 spring-boot:run` + curl 六步驟 |
| AC-10 | 手動（錯誤路徑） | 同 AC-9 環境 |
| AC-11 | 手動 | `mall-tiny-03` + `redis-cli TTL` |
| AC-12 | 手動（相容性） | `master` 與升級分支先後啟動 `mall-tiny-redis` + `redis-cli GET`／`DEL`／`TTL` |
| AC-13 | 手動（依環境） | `mall-tiny`，需 ES 8.x／MongoDB／RabbitMQ／MinIO |
| AC-14 | 程式碼審查 | `CommentGenerator.java`、`MyBatisPlusGenerator.java` |
| AC-15 | 機器關卡（grep）＋程式碼審查 | §6 最後一個 grep；`CODEBASE_MAP.md` 指定 5 處 |
| AC-16 | 手動（含錯誤路徑） | `mvn -pl mall-tiny-boot spring-boot:run` + curl 五步驟 |
| AC-17 | 程式碼審查＋手動 | `mall-tiny-02` 的 POM／YAML／mapper；`PG_PASSWORD=... mvn -pl mall-tiny-02 spring-boot:run` + curl |

## 8. 邊界情況、風險、開放問題與決議

- **邊界情況**：
  - `spring.data.redis` 與既有 `spring.data.{elasticsearch,mongodb}` 必須合併在同一個 `data:` 鍵下（§4.10）。
  - Controller 中 `@RequestParam String username`（未寫 name）與 `@Cacheable(key = "'pms:brand:'+#id")` 依賴編譯參數 `-parameters`。Spring 6.1 起已移除 LocalVariableTable 的退路；`spring-boot-starter-parent` 會為 `maven-compiler-plugin` 開啟 `-parameters`，但若在 IDE 中未委派 Maven 編譯，可能出現「參數名稱無法解析」。手動驗證請以 `mvn spring-boot:run` 或確認 IDE 已設定 `-parameters`。
  - 帶結尾斜線的請求（如 `/brand/list/`）在升級後回 404（D-9）。
  - `mall-tiny-swagger` 的 `contextLoads()` 沒有 `@Test`，屬既有狀況，不處理。
- **風險**：
  - **Elasticsearch 伺服器版本**：Spring Data Elasticsearch 5.5 使用 Elasticsearch Java Client 8.18，無法連 6.x／7.x 伺服器（文件中仍寫 6.4.0／7.6.2）。`mall-tiny`、`05`～`08` 的搜尋功能需要 ES 8.x（含 IK 分詞），這是執行環境的升級，不在程式碼範圍內。
  - **MySQL 5.7 + Connector/J**：Boot 3.5.16 管理的 `mysql-connector-j` 為 9.7.0，官方支援矩陣以 MySQL 8.0 以上為主。若連 5.7（docker-compose 仍用 `mysql:5.7`）失敗，退路是在根 POM 加 `<mysql.version>8.4.0</mysql.version>` 覆寫 Boot 管理的版本（需走 spec 變更流程）。
  - **MongoDB driver 5.x**：與舊版 MongoDB 伺服器（文件中為 4.2.5）的相容性，請在 AC-13 確認。
  - **Java 21 執行環境**：所有執行端（本機 IDE、`spring-boot:run`、Docker 映像、Jenkins 部署主機）都必須是 JDK／JRE 21 以上；以 17 執行會出現 `UnsupportedClassVersionError`。AC-12 步驟 1 需要在升級前的 `master` 啟動舊版，JDK 21 仍可編譯 Java 8 目標。
  - **JJWT 0.9.1 on Java 21**：依賴 `javax.xml.bind.DatatypeConverter`，由根 POM 的 `jaxb-api` 2.3.1（內含 `DatatypeConverterImpl`）提供；AC-9 的登入與 token 驗證會覆蓋這條路徑。
  - **`AntPathRequestMatcher` 已棄用**：編譯時有警告；未來升 Boot 4 / Security 7 時需改用 `PathPatternRequestMatcher` 並改寫 `/**/*.html` 這類樣式。
  - **Swagger 書籤失效**：舊 `/swagger-ui/` 網址不再可用，教學文章中的截圖與網址仍是舊版（非目標）。
  - **回滾方式**：所有變更在 `feat/spring-boot-3-upgrade` 分支，未合併前直接捨棄分支即可；本任務不涉及資料庫結構或資料遷移，Redis 快取序列化格式不變。
- **開放問題**：無。

### 8.1 決議紀錄

| ID | 日期 | 決議 | 理由 | 來源 |
|----|------|------|------|------|
| D-1 | 2026-10-11 | 目標版本為 Spring Boot **3.5.16**（Maven Central 上 3.x 最後一個版本） | 使用者要求 3.x；3.5 是 3.x 最後一條線，可一次跨到最新、避免短期內再升 3.x 小版本；4.x 不在範圍內 | Claude |
| D-2 | 2026-10-11 | （已由 D-13 取代）Java 基準設為 **17**（`java.version=17`），不設 21 | 17 是 Boot 3 的最低要求、相容面最廣；本機 JDK 21 可正常編譯與執行 17 目標 | Claude |
| D-3 | 2026-10-11 | Springfox 換成 **springdoc-openapi 2.9.1**，並把 Swagger 2 註解全面改成 OpenAPI 3 註解；捨棄「保留 `io.swagger.annotations` 依賴只換 UI」的方案 | Springfox 不支援 Boot 3；只換 UI 會讓所有描述文字在文件中消失，對教學 repo 失去意義；`@Tag` 已在 50 個 Controller 中存在，遷移成本可控。2.9.1 的 parent 即為 Boot 3.5.16 | Claude |
| D-4 | 2026-10-11 | PageHelper starter 用 **2.1.1**，並在根／jenkins POM 以 `dependencyManagement` 把 `mybatis-spring-boot-starter`／`-autoconfigure` 固定為 **3.0.5** | 2.1.1 的 autoconfigure 已有 `AutoConfiguration.imports`，但其 POM 傳遞 `mybatis-spring-boot` 2.3.2（Boot 2 版本）；PageHelper 4.x 的 parent 是 Boot 4.1，不適用 | Claude |
| D-5 | 2026-10-11 | Druid 改 `druid-spring-boot-3-starter` 1.2.28；MySQL 驅動改 `com.mysql:mysql-connector-j` 並交由 Boot 管理版本 | 舊 `druid-spring-boot-starter` 只有 `spring.factories`，在 Boot 3 不會生效，DataSource 會靜默變成 Hikari；`mysql:mysql-connector-java` 已遷移座標 | Claude |
| D-6 | 2026-10-11 | **不升級 JJWT**（維持 0.9.1 + `javax.xml.bind:jaxb-api` 2.3.1） | 升到 0.11+／0.12 會強制 HS512 金鑰至少 64 bytes，現有 `jwt.secret: mySecret` 會在執行期失敗，需要連帶改設定與教學內容，超出框架升級範圍 | Claude |
| D-7 | 2026-10-11 | Security 白名單一律用 `AntPathRequestMatcher.antMatcher(...)`，不改寫白名單樣式 | 現有樣式（`/**/*.html` 等）只有 Ant 語意能解析；明確指定 matcher 可避開 `requestMatchers(String)` 在多 Servlet 時丟例外；接受 6.5 的棄用警告 | Claude |
| D-8 | 2026-10-11 | 安全鏈對 `DispatcherType.ERROR` 一律 `permitAll` | 保持 Boot 2.7（`authorizeRequests` 不重檢 error dispatch）的行為，避免例外被包裝成 401 | Claude |
| D-9 | 2026-10-11 | 接受 Spring 6 移除 trailing slash 比對，不加相容設定 | 不提供官方非棄用的全域開關；本 repo 的 Controller 與文件都使用無結尾斜線的路徑 | Claude |
| D-10 | 2026-10-11 | `Swagger2Config` 改名為 `SpringDocConfig`（刪除舊檔、新增新檔） | 內容已不是 Swagger 2；`CODEBASE_MAP.md` 已提醒「不能只看類別名稱 `Swagger2Config` 推定套件版本」 | Claude |
| D-11 | 2026-10-11 | `mall-tiny-alipay`、`mall-tiny-jenkins` 一併升級 | alipay 繼承根 POM，根 POM 升級後它不改就無法編譯；jenkins 雖獨立，但與其他副本保持一致，避免 repo 內殘留 Boot 2 模組 | Claude |
| D-12 | 2026-10-11 | 不新增 Maven Wrapper；驗證指令假設環境中有 `mvn` ≥ 3.6.3 | 新增 wrapper 屬建置流程變更，與框架升級無關；可另開任務 | Claude |
| D-13 | 2026-10-12 | Java 基準改為 **21**（`java.version=21`），Docker 基底映像隨之改為 `eclipse-temurin:21-jre`；取代 D-2 | 使用者指定維持使用 Java 21；以 21 編譯的 class（版本 65）無法在 17 的 JRE 執行，因此映像必須同步改為 21 | 人類 H1-1 |
| D-14 | 2026-10-12 | SecurityConfig 分 A／B／C 三種變體改寫，各自保留原本的「路徑 × HTTP method」放行集合；`boot` 保留 GET／POST 限定與獨立的 `/admin/login` 放行；新增 AC-16 | 原範本會讓 `mall-tiny-boot` 匿名登入被擋、白名單擴大到所有 method（`mall-tiny-boot/.../SecurityConfig.java:56-62`），違反 §3.2 | Codex P1-1 |
| D-15 | 2026-10-12 | AC-12 改為驗證 Jackson `WRAPPER_ARRAY` 格式，並加入「升級後讀取升級前寫入的快取」相容性步驟 | `activateDefaultTyping(ptv, NON_FINAL)` 兩參數版本使用 `WRAPPER_ARRAY`，不會產生 `@class`；§4.9 要求格式不變，原 AC 自相矛盾 | Codex P1-2 |
| D-16 | 2026-10-12 | `CODEBASE_MAP.md` 更新範圍擴大到所有指向 `Swagger2Config`／`matching-strategy`／`spring.redis.*` 的導覽位置，並加入機器關卡 grep | 只改版本表會讓導覽指向已刪除的類別與設定鍵（`CODEBASE_MAP.md:46`、`:59`、`:351`） | Codex P1-3 |
| D-17 | 2026-10-12 | `mall-tiny-02` 執行期改連既有 PostgreSQL（經 SSH tunnel `127.0.0.1:15432`）：driver 改 `org.postgresql:postgresql`、datasource 帳號／database／schema 可由 `PG_*` 環境變數覆寫且密碼只來自 `PG_PASSWORD`、PageHelper 方言 `postgresql`、`PmsBrandMapper.xml` 以 `useGeneratedKeys` 取代 `LAST_INSERT_ID()`；新增 AC-17。範圍僅限 `mall-tiny-02` 的執行期，`generator.properties`／`generatorConfig.xml` 維持 MySQL、不重新產碼，其他模組仍用 MySQL | 使用者要以既有的遠端 PostgreSQL（`document/sql/mall_tiny_postgre.sql`）實際驗證 `mall-tiny-02`；`LAST_INSERT_ID()` 為 MySQL 專屬，PostgreSQL 必須改用 JDBC generated keys 才能回填主鍵 | 人類 |
| D-18 | 2026-10-17 | 本任務不再驗證需要 MySQL、Redis 或其他外部服務的手動 AC：AC-6、AC-7、AC-9 步驟 4、AC-11、AC-12、AC-13、AC-16 步驟 2 延後到後續「其餘模組改用 PostgreSQL」任務，由該任務的 spec 改以 PostgreSQL 重新定義並驗收。AC-12 步驟 1～2（讀取升級前寫入的快取）不適用，後續只驗證新寫入值的 `WRAPPER_ARRAY` 格式、SpEL `#id` 與 TTL。§8 的「MySQL 5.7 + Connector/J」風險不再追蹤。本任務以機器關卡、分批審查（8/8 PASS）與已通過的 AC-8、AC-10、AC-17 為完成依據後合併；合併後到遷移完成前，`master` 上這些模組的 MySQL／Redis 執行路徑未經實測，人類接受此風險 | 使用者不再安裝 MySQL，repo 的目標資料庫改為 PostgreSQL；MySQL 專屬風險將隨遷移消失，框架層行為（PageHelper／MyBatis starter 3、Druid 3、MyBatis-Plus 分頁、Security 的 DB 查詢、Redis 快取）可在遷移後以 PostgreSQL 一次驗證，避免重複測試；本 repo 為個人學習用途，無既有線上快取或其他使用者 | 人類 |

---

## 9. 實作備註（由實作者填寫）

實作日期：2026-10-12；分支：`spring-boot-3-upgrade`；基準 HEAD：`bde7987`。變更保留在工作目錄，未執行 commit／push。

- **偏離 spec 之處與原因**：
  - 首次執行 §6 時，`mall-tiny-plus` 編譯失敗：`package com.baomidou.mybatisplus.extension.service does not exist`，`extension.service.impl` 亦不存在。指定的 MyBatis-Plus 3.5.17 已將這兩個類別移至 `com.baomidou.mybatisplus.spring.service`／`.impl`，因此在 §5 清單之外，另修改 `modules/pms/service/PmsBrandService.java` 與 `modules/pms/service/impl/PmsBrandServiceImpl.java` 各一個 import；類別、繼承關係與行為不變，未另增依賴。依據為本機 3.5.17 JAR 及上游 [IService](https://github.com/baomidou/mybatis-plus/blob/v3.5.17/mybatis-plus-spring/src/main/java/com/baomidou/mybatisplus/spring/service/IService.java)、[ServiceImpl](https://github.com/baomidou/mybatis-plus/blob/v3.5.17/mybatis-plus-spring/src/main/java/com/baomidou/mybatisplus/spring/service/impl/ServiceImpl.java) 原始碼。
  - 配合設定遷移，`mall-tiny-boot` 原本的 `springfox.documentation.enabled: true` 區塊替換為 `springdoc.packages-to-scan`（文件仍預設啟用）；`mall-tiny-hutool` 刪除 `mvc` 後一併移除空的 `spring:`。其餘設定值不變。
- **未完成的項目**：程式與設定遷移已完成；外部服務相關手動驗證尚未完成，詳見下表。本機未提供 MySQL、Redis、Elasticsearch 8.x + IK、MongoDB、RabbitMQ、MinIO，也未發現 Docker／mysql／redis-cli 工具。未匯入 SQL，未驗證升級前後的 Redis 快取互讀。
- **需要審查者特別注意的地方**：
  - Security A／B／C 保留各自的 method 限制與登入規則，僅依規格新增 ERROR dispatch 放行。JWT filter 的 `@Bean` 註冊方式未變；`AntPathRequestMatcher` 的棄用警告為規格接受項目。
  - 保留 JJWT 0.9.1 與 JAXB 2.3.1；未升級非目標依賴，未新增或修改測試、重新產碼、修改 Compose／部署腳本／教學文件。`mall-tiny-lombok` 直接繼承根 POM 的新版本與 Java target，其模組 POM 無需異動。
  - 框架升級階段的 `test-compile` 通過代表正式程式與測試程式可編譯；該階段未執行 `test`。後續另執行 `mall-tiny-02` 的既有測試與 PostgreSQL 實測，見 §9.3。均未執行 `package` 或觸發 Fabric8 Docker build。
  - 以下 HTTP 測試以 `mvn -B -ntp -pl <module> spring-boot:run` 啟動；`02` 使用 8080、`boot` 使用 8088，`04` 另加 `-Dspring-boot.run.arguments=--server.port=8084` 避免衝突。測試後三個應用皆已停止。token 證據已遮蔽。

### 9.1 機器關卡與程式碼核對

環境：Eclipse Temurin **21.0.12.1**、Maven **3.10.0**。將 §6 的 bash 區塊原文擷取至 `/tmp/mall-spring-boot-3-upgrade/verify-section6.sh`，以 `bash -eo pipefail` 執行。sandbox 初次阻擋 Maven 寫入 `~/.m2/repository/.locks`；取得執行權限後完成驗證。後續 §9.3 的 PostgreSQL 設定完成後，再次原樣執行整份腳本，**exit 0**；下列建置時間為最終重跑結果，輸出保存於 `/tmp/mall-spring-boot-3-upgrade/verification.log`。

| 驗證 | 結果與關鍵輸出 |
|------|----------------|
| AC-1：根 reactor | 通過；20 個模組與根專案皆 `SUCCESS`，`BUILD SUCCESS`，`Total time: 4.205 s` |
| AC-1：alipay | 通過；`BUILD SUCCESS`，`Total time: 3.373 s` |
| AC-1：jenkins | 通過；`BUILD SUCCESS`，`Total time: 3.201 s` |
| AC-2～AC-5、AC-15 grep | 通過；禁止項目皆無命中，版本／映像正向檢查皆通過，最後輸出 `ALL CHECKS PASSED` |
| AC-14 | 程式碼核對通過；17 個 `CommentGenerator` 均產生 `@Schema(description = ...)` 並匯入 `Schema`；`mall-tiny-01` 的產碼器未變；MyBatis-Plus 使用 `.enableSpringdoc()`，未執行產碼 |
| AC-15 文件核對 | 指定五處已更新至 `SpringDocConfig`、`springdoc.packages-to-scan`、`spring.data.redis.*`、Boot 3.5.16／Java 21 與新依賴版本 |
| 範圍與內容核對 | `git diff --check` 通過；24 份 application YAML 可解析且無重複鍵；框架升級階段的 20 份 YAML 除指定遷移外語意不變，後續僅 `mall-tiny-02` 另依使用者要求改 PostgreSQL（§9.3）；94 份 Controller／model／DTO 的程式本體、非文件註解與描述字串保持不變（依規格捨棄 `ApiModel.value`）；20 個新 springdoc 設定保留原本是否啟用認證的分組 |

第 9 節之前的全部內容與實作前逐位元組一致；SHA-256：`e91d93c46ae520cff6e08e4e481404b4a1fd6ce455056f8c1e7c4fa594d90165`。

### 9.2 手動 AC 結果

| AC | 結果 | 關鍵輸出／未驗證範圍 |
|----|------|-----------------------|
| AC-6 | **延後（D-18）** | 缺 MySQL 與匯入後的測試資料，未執行 `mall-tiny-01` 的品牌查詢、筆數比對及該模組 Druid 驗證 |
| AC-7 | **延後（D-18）** | 缺 MySQL，未實測 `mall-tiny-plus` 分頁與總筆數；編譯及分頁依賴解析已通過 |
| AC-8 | **通過** | `GET /v3/api-docs` → HTTP 200；`info.title="SwaggerUI演示"`、`tags=[{"name":"PmsBrandController","description":"商品品牌管理"}]`、`paths["/brand/listAll"].get.summary="获取所有品牌列表"`。`GET /swagger-ui/index.html` → 200；`GET /swagger-ui/`、`GET /v2/api-docs` → 404 |
| AC-9 | **部分步驟通過，其餘延後（D-18）** | 步驟 1／2／3／5／6 通過：匿名品牌查詢 → `{"code":401,"message":"暂未登录或token已经过期"}`；文件及 UI → HTTP 200；admin 登入 → `{"code":200,"data":{"token":"<nonempty>","tokenHead":"Bearer"}}`；macro token 查 `/brand/list` → `{"code":403,"message":"没有相关权限"}`；6 個品牌 operation 均有 `security:[{"Authorization":[]}]`，登入 operation 無 security，scheme 為 `{"type":"apiKey","name":"Authorization","in":"header"}`。步驟 4 的有效 admin token 品牌查詢需 MySQL，未驗證 |
| AC-10 | **通過** | 錯誤密碼 → HTTP 200、`{"code":404,"message":"用户名或密码错误","data":null}`；`Bearer abc.def.ghi` → HTTP 200、`code=401` JSON，應用 log 無未捕捉堆疊／500；有效 admin token 呼叫 `/brand/abc` → HTTP 400、`{"status":400,"error":"Bad Request","path":"/brand/abc"}`。log：`Resolved [org.springframework.web.method.annotation.MethodArgumentTypeMismatchException: Method parameter 'id': Failed to convert value of type 'java.lang.String' to required type 'java.lang.Long'; For input string: "abc"]` |
| AC-11 | **延後（D-18）** | 缺 Redis，未驗證 `mall-tiny-03` 的驗證碼、key、TTL 與校驗流程 |
| AC-12 | **延後（D-18）** | 缺 MySQL／Redis，未啟動 master 寫入舊快取，也未驗證新版讀取舊快取、WRAPPER_ARRAY 實際儲存值、SpEL `#id` 與 86400 秒 TTL；僅確認 ObjectMapper 設定未變 |
| AC-13 | **延後（D-18）** | Elasticsearch 8.x + IK 的匯入／搜尋、MongoDB 的瀏覽歷史、RabbitMQ 的延遲取消訊息、MinIO 的圖片上傳／URL 均因缺服務而未驗證 |
| AC-16 | **部分步驟通過，其餘延後（D-18）** | 步驟 1／3／4／5 通過：匿名 admin 登入 → `code=200` 且 token 非空；macro token 查 `/brand/list` → `code=403` JSON；匿名 `/v3/api-docs` → HTTP 200；匿名 `PUT /favicon.ico` → `code=401` JSON。步驟 2 的匿名查詢 → `code=401` 已確認，有效 token 的資料查詢需 MySQL，未驗證 |

HTTP 證據：`/tmp/mall-spring-boot-3-upgrade/openapi-02.json`、`openapi-04.json`、`openapi-boot.json`、`security-http-results.json`；應用 log：同目錄的 `run-02.log`、`run-04.log`、`run-boot.log`。三個啟動 log 均出現 `{dataSource-1} inited`，未出現 `HikariPool`，但這不替代 AC-6 的 MySQL 查詢驗證。Maven 啟動時有既有 `jvnet-nexus-releases` metadata 的 PKIX 憑證警告，三個應用均成功啟動，未修改 repository 或憑證設定。

### 9.3 後續需求：mall-tiny-02 使用現有 PostgreSQL

使用者後續指定先調整 `mall-tiny-02`，使用既有遠端 PostgreSQL 與已啟動的 SSH tunnel。此需求僅套用於該模組的執行期設定、driver 與品牌 mapper；未擴及其他模組，也未修改 §1～8。

- 連線為 `127.0.0.1:15432`，database 為 `mall_tiny`、帳號為 `mall_app`。實際唯讀查核發現只有 `public` 使用者 schema，品牌表是 `public.pms_brand`；使用者原提供的 `mall_tiny` 是 database 名稱，並不存在同名 schema。因此 YAML 使用 `currentSchema=${PG_SCHEMA:public}`，database／user 分別可由 `PG_DATABASE`／`PG_USER` 覆寫；密碼只透過 `PG_PASSWORD` 帶入，未寫入 repo 或驗證日誌。
- runtime driver 改用 Boot 管理的 `org.postgresql:postgresql:42.7.11`；PageHelper 設定為 `postgresql`。`PmsBrandMapper.xml` 的 `insert`／`insertSelective` 改用 `useGeneratedKeys="true" keyProperty="id" keyColumn="id"`，移除兩個 MySQL `LAST_INSERT_ID()`。未重新產碼；產碼器的連線設定仍為原本 MySQL，不在本次執行期遷移範圍。
- 指令 `mvn -B -ntp -pl mall-tiny-02 -am -DskipTests test-compile dependency:tree` 通過，模組依賴樹有 PostgreSQL driver、無 MySQL driver。另以占位連線環境變數執行 `mvn -B -ntp -pl mall-tiny-02 -DskipTests=false test`，既有 `contextLoads` 為 1 test、0 failures、0 errors；該測試不代表實際連線成功，實際證據如下。

| 遠端／HTTP 驗證 | 結果 |
|----------------|------|
| JDBC 與資料表 | PostgreSQL 18.6；`current_database()=mall_tiny`、`current_schema()=public`、`current_user=mall_app`；`pms_brand` 有 12 筆；帳號具 SELECT／INSERT／UPDATE／DELETE 權限 |
| 啟動及文件 | Tomcat 在 8080 啟動；`/v3/api-docs`、`/swagger-ui/index.html` 均 HTTP 200 |
| 查詢／分頁 | `/brand/listAll` 12 筆；`/brand/list?pageNum=1&pageSize=3` 與第 2 頁皆 `code=200`，`total=12`、`totalPage=4`、各回傳 3 筆；既有品牌詳情成功 |
| 新增／ID 回填 | `POST /brand/create` 建立唯一名稱的驗證品牌，`code=200`、回填 `id=60`；以該 ID 查詢可讀回新增欄位，涵蓋 `insertSelective` 路徑 |
| 更新／刪除 | `POST /brand/update/60` 後讀回名稱與排序正確；`GET /brand/delete/60` 成功，再查該 ID 回傳 `data=null` |
| 清理 | 專用驗證資料剩餘 0 筆，原本 12 筆品牌 ID 集合一致；未匯入 SQL、未建立／搬移 schema；正常新增使 identity sequence 前進，未重設 sequence |
| 最終規格檢查 | 完整重跑 §6，三次 `BUILD SUCCESS`，最後 `ALL CHECKS PASSED`，exit 0 |

證據位於 `/tmp/mall-tiny-02-postgresql/`：`build.log`、`context-test.log`、`database-inspection.log`、`run-live.log`、`live-results.json`。HTTP 驗收由暫存腳本完成，未新增或修改 repo 測試。驗收後 `mall-tiny-02` 已停止，使用者的 SSH tunnel 保持運作；若要人工使用 Swagger UI，設定 `PG_PASSWORD` 後在 repo 根目錄執行 `mvn -pl mall-tiny-02 spring-boot:run`。其餘模組的外部服務限制與 §9.2 未驗證項目維持不變；未執行 commit／push。
