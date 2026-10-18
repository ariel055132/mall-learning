# A 組 6 個模組改用 PostgreSQL

| 項目 | 內容 |
|------|------|
| 任務代號 | `postgresql-migration`（與檔名一致） |
| 狀態 | approved |
| 分支 | `postgresql-migration` |
| 建立日期 | 2026-10-17 |
| 核准 | 2026-10-17；依據 docs/spec-reviews/postgresql-migration-p2-codex.md（APPROVE）。人類決定在 `postgresql-migration` 分支（非 `master`）核准與實作；`review.sh` 需以 `--base <本核准 commit>` 執行 |

## 1. 背景與目標

Spring Boot 3 升級（`docs/specs/spring-boot-3-upgrade.md`）依 D-18 合併時，把需要 MySQL／Redis 的手動驗收延後，並決定 repo 的目標資料庫改為 PostgreSQL。目前只有 `mall-tiny-02` 改連 PostgreSQL（升級 spec 的 D-17），其餘 18 個資料庫模組仍是 MySQL。本任務是分三步遷移的第一步：把延後驗收會用到的 **A 組 6 個模組**——`mall-tiny-01`、`mall-tiny-03`、`mall-tiny-04`、`mall-tiny-plus`、`mall-tiny-boot`、`mall-tiny-redis`——比照 `mall-tiny-02` 改連同一個 PostgreSQL，並在 PostgreSQL＋Redis 上補完升級 spec 延後的 AC（AC-13 除外）。做完之後，這 6 個模組在設定 `PG_PASSWORD`、啟動 SSH tunnel 與本機 Redis 後即可執行，HTTP API、認證與快取行為與升級後相同。

## 2. 驗收標準

AC-1～AC-3 由第 6 節機器關卡自動驗證；標註「（手動）」者需在 PostgreSQL（經 SSH tunnel）與本機 Redis 上啟動應用驗證，實作者在 §9 記錄實際結果（貼上關鍵 curl 回應、`redis-cli` 輸出或 log 片段，token 與密碼須遮蔽）。手動驗證前後需記錄 `SELECT count(*) FROM pms_brand` 與 `pms_brand` 的 id 集合，下文以 `N` 表示驗證前的筆數。

- **AC-1**：在 JDK 21 以上執行 `mvn -B -ntp -DskipTests test-compile`（根 reactor）時 exit 0。（預期結果：輸出含 `BUILD SUCCESS`）
- **AC-2**：A 組 6 個模組皆滿足（下列細項全部由 §6 的結構檢查驗證；`application.yml` 其餘鍵未被改動則由程式碼審查確認）：
  1. `pom.xml` 不含 `mysql-connector-j`；含一個 `<dependency>`，依序只有 `<groupId>org.postgresql</groupId>`、`<artifactId>postgresql</artifactId>`、`<scope>runtime</scope>`（不寫 version）。
  2. `application.yml` 中 `spring:` 下緊接的 `datasource:` 區塊與 `mall-tiny-02` 逐行相同，依序為 `driver-class-name: org.postgresql.Driver`、`url: jdbc:postgresql://127.0.0.1:15432/${PG_DATABASE:mall_tiny}?currentSchema=${PG_SCHEMA:public}`、`username: ${PG_USER:mall_app}`、`password: ${PG_PASSWORD}`（縮排與 `mall-tiny-02` 相同）；檔案不含 `jdbc:mysql`。
  3. 除 `mall-tiny-plus` 外的 5 個模組：`application.yml` 有頂層區塊 `pagehelper:`，其下一行為 `  helper-dialect: postgresql`；`PmsBrandMapper.xml` 不含 `LAST_INSERT_ID`，且 `<insert id="insert" …>` 與 `<insert id="insertSelective" …>` 兩個開始標籤各自帶 `useGeneratedKeys="true" keyProperty="id" keyColumn="id"`。`mall-tiny-plus` 的 `application.yml` 不含 `pagehelper:`。
  4. `mall-tiny-plus/.../config/MyBatisConfig.java` 的分頁外掛為 `new PaginationInnerInterceptor(DbType.POSTGRE_SQL)`，不含 `DbType.MYSQL`。
- **AC-3**：A 組以外的模組資料庫設定不變：`application.yml` 含 `jdbc:mysql` 的模組恰為 `mall-tiny`、`mall-tiny-05`～`08`、`alipay`、`docker`、`generator`、`jenkins`、`mybatis`、`stream`、`swagger` 共 12 個；`mall-tiny-02` 仍為 `jdbc:postgresql`。
- **AC-4**（手動）：啟動 `mall-tiny-01`：
  1. `GET /brand/list?pageNum=1&pageSize=3` → `code=200`、`data.list` 長度 3、`data.total` 等於 `N`；首次查詢後 log 含 `{dataSource-1} inited`，且不含 `HikariPool`。（取代升級 spec AC-6）
  2. `POST /brand/create`（JSON body，`name` 為唯一的驗證用名稱）→ `code=200` 且 `data.id` 非空；`GET /brand/{id}` 讀回同名資料；`GET /brand/delete/{id}` 成功後，再 `GET /brand/{id}` 回傳 `data` 為 `null`。
- **AC-5**（手動）：啟動 `mall-tiny-plus`：
  1. `GET /brand/list?pageNum=1&pageSize=2` → `data.list` 長度 2，`data.total` 等於 `N`（不是 0 或 2）。（取代升級 spec AC-7）
  2. `POST /brand/create` → `code=200` 且 `data.id` 非空（`IdType.AUTO` 對 identity 欄位回填）；`GET /brand/{id}` 可讀回；`GET /brand/delete/{id}` 後讀不到。
- **AC-6**（手動）：啟動 `mall-tiny-04`（需 Redis）：
  1. 不帶 token `GET /brand/listAll` → `code=401` JSON。
  2. `POST /admin/login?username=admin&password=123456` 取得 token，帶 `Authorization: Bearer <token>` 呼叫 `GET /brand/listAll` → `code=200`，`data` 長度等於 `N`。（取代升級 spec AC-9 步驟 4）
  3. 以 `macro/123456` 的 token 呼叫 `GET /brand/list` → `code=403` JSON。
- **AC-7**（手動）：啟動 `mall-tiny-boot`（port 8088）：不帶 token `GET /brand/listAll` → `code=401` JSON；以 admin token 呼叫 → `code=200`，`data` 長度等於 `N`。（取代升級 spec AC-16 步驟 2）
- **AC-8**（手動）：啟動 `mall-tiny-03`：
  1. `GET /brand/list?pageNum=1&pageSize=3` → `code=200`、`data.list` 長度為 `min(N,3)`、`data.total` 等於 `N`（證明此模組的 PostgreSQL 連線與 PageHelper 方言生效）。
  2. `GET /sso/getAuthCode?telephone=13800000000` 回傳 6 位數驗證碼；`redis-cli` 中存在 key `portal:authCode:13800000000`，`TTL` 介於 1～120；以 `POST /sso/verifyAuthCode?telephone=13800000000&authCode=<碼>` 回傳 `code=200`。（取代升級 spec AC-11）
- **AC-9**（手動）：啟動 `mall-tiny-redis`，以 `POST /brand/create` 建立驗證用品牌取得 id `X`：
  1. `GET /brand/X` → `code=200`；`redis-cli GET mall::pms:brand:X` 的值為 Jackson `WRAPPER_ARRAY` 型別包裝，即以 `["com.macro.mall.tiny.mbg.model.PmsBrand",{` 開頭，不含 `@class`；`redis-cli TTL mall::pms:brand:X` 介於 86000～86400。（取代升級 spec AC-12 步驟 3；步驟 1～2 依升級 spec D-18 不適用）
  2. `GET /brand/delete/X` 成功後，`redis-cli EXISTS mall::pms:brand:X` 為 `0`（`@CacheEvict` 生效）。
- **AC-10**（手動，邊界與錯誤情境）：
  1. `mall-tiny-01`：`GET /brand/list?pageNum=1000&pageSize=3` → `code=200`、`data.list` 長度 0、`data.total` 等於 `N`，HTTP 狀態不是 500。
  2. `mall-tiny-redis`：`GET /brand/999999`（不存在的 id）→ `code=200` 且 `data` 為 `null`；`redis-cli EXISTS mall::pms:brand:999999` 為 `0`（`unless = "#result==null"` 生效，不快取空結果）。
  3. `mall-tiny-04`：帶有效 admin token 呼叫 `GET /brand/abc` → HTTP 400，而不是 401 或 500。
- **AC-11**（手動，資料清理）：全部手動驗證結束後，`SELECT count(*) FROM pms_brand` 等於 `N`，且 id 集合與驗證前相同；不得殘留驗證用資料。（identity sequence 前進屬預期，不需重設）
- **AC-12**（程式碼審查）：`CODEBASE_MAP.md` 中敘述「只有 `mall-tiny-02` 使用 PostgreSQL」的段落（目前約在第 249、261、278、291、301、303～308 行）改為反映 7 個 PostgreSQL 模組（`02` 與 A 組 6 個），共用的啟動說明須註明模組差異（`mall-tiny-boot` 使用 port 8088、`mall-tiny-01` 沒有 Swagger UI、`mall-tiny-plus` 以 MyBatis-Plus 分頁外掛而非 PageHelper、mapper 主鍵回填說明不適用於 `plus`），並寫明 A 組 MBG 產碼設定（`generator.properties`／`generatorConfig.xml`）仍為 MySQL、目前無法直接執行，重新產碼會覆蓋 `useGeneratedKeys`。完成後 `grep -n '其餘品牌範例需要 MySQL\|其餘資料庫模組仍使用 MySQL\|其餘資料庫模組保留 MySQL' CODEBASE_MAP.md` 無輸出。

## 3. 範圍

### 3.1 範圍內

- A 組 6 個模組的 `pom.xml`：`com.mysql:mysql-connector-j` → `org.postgresql:postgresql`（runtime）。
- A 組 6 個模組的 `src/main/resources/application.yml`：`spring.datasource` 改為 PostgreSQL；除 `plus` 外新增 `pagehelper.helper-dialect: postgresql`。
- 除 `plus` 外 5 個模組的 `mbg/mapper/PmsBrandMapper.xml`：`LAST_INSERT_ID()` 的 `<selectKey>` 改為 `useGeneratedKeys`。
- `mall-tiny-plus` 的 `config/MyBatisConfig.java`：`DbType.MYSQL` → `DbType.POSTGRE_SQL`。
- `CODEBASE_MAP.md`：AC-12 指定的段落。

### 3.2 非目標（禁止事項）

- 不動 A 組以外的模組，包括 `mall-tiny-02`、B 組（`alipay`、`docker`、`generator`、`jenkins`、`mybatis`、`stream`、`swagger`）與 C 組（`mall-tiny`、`05`～`08`）。這兩組分別是後續任務。
- 不驗證、不處理需要 Elasticsearch、MongoDB、RabbitMQ、MinIO 的功能（升級 spec AC-13 延後到 C 組任務）。
- 不修改 MBG 產碼設定 `generator.properties`、`generatorConfig.xml`、`CommentGenerator.java`、`mall-tiny-plus` 的 `generator.properties`／`MyBatisPlusGenerator.java`；不重新執行任何產碼器。
- 不新增或升級依賴，只有 A 組 6 個 POM 的 `org.postgresql:postgresql`（版本由 Boot 管理）例外；根 POM 不動。
- 不變更 HTTP API 路徑、參數、回應格式、錯誤碼與權限規則；不修改 `SecurityConfig`、`RedisConfig`、快取 key、Redis 設定與序列化方式。
- 不修改 `document/`（含 SQL 檔）、`docs/`（教學文章）、`README.md`、`docker-compose.yml`、`db-tunnel.sh`、`.db-tunnel.env*`。
- 不修改 `docs/specs/spring-boot-3-upgrade.md`；延後 AC 的對應結果記錄在本 spec 的 §9。
- 不建立、搬移或重設資料庫 schema、資料表、sequence，不匯入 SQL；手動驗證只透過 HTTP API 寫入驗證資料並依 AC-11 清除。
- 不把任何密碼寫入 repo、§9 或驗證證據檔。
- 不做無關的格式化、import 重新排序或重構；YAML 只改 datasource 與新增 pagehelper 區塊，其餘鍵與註解原樣保留。
- 不新增或修改測試類別、不改 `skipTests`、不新增 Maven Wrapper。
- 不修改本 spec 的第 1～8 節。
- 不執行 `git commit`、`git push`。

## 4. 設計與實作要點

- **方案**：完全比照 `mall-tiny-02`（升級 spec D-17）已驗證的改法，逐模組套用。各模組是獨立副本，不抽共用設定。
- **關鍵決策**：見 §8.1（D-1～D-10）。

### 4.1 POM（A 組 6 個）

把 MySQL driver 依賴整段替換，保留原位置與上方註解的位置（註解文字改為 `PostgreSQL数据库驱动`，比照 `mall-tiny-02/pom.xml`）：

```xml
<!--PostgreSQL数据库驱动-->
<dependency>
    <groupId>org.postgresql</groupId>
    <artifactId>postgresql</artifactId>
    <scope>runtime</scope>
</dependency>
```

### 4.2 application.yml（A 組 6 個）

`spring.datasource` 區塊改為下列內容（四個鍵、順序如下），`spring` 底下的其他鍵（`data.redis`、`main` 等）不動：

```yaml
spring:
  datasource:
    driver-class-name: org.postgresql.Driver
    url: jdbc:postgresql://127.0.0.1:15432/${PG_DATABASE:mall_tiny}?currentSchema=${PG_SCHEMA:public}
    username: ${PG_USER:mall_app}
    password: ${PG_PASSWORD}
```

除 `mall-tiny-plus` 外，在 `mybatis:` 區塊之後新增頂層區塊（若該位置之後緊接 `springdoc:` 等區塊，插在其前並以一個空行分隔）：

```yaml
pagehelper:
  helper-dialect: postgresql
```

`mall-tiny-plus` 使用 MyBatis-Plus 分頁，不加 `pagehelper`。

### 4.3 PmsBrandMapper.xml（01、03、04、boot、redis）

檔案位置：`<M>/src/main/resources/com/macro/mall/tiny/mbg/mapper/PmsBrandMapper.xml`。`insert` 與 `insertSelective` 兩處，刪除內含 `SELECT LAST_INSERT_ID()` 的 `<selectKey>…</selectKey>` 三行，並在開始標籤加上屬性：

```xml
<insert id="insert" parameterType="com.macro.mall.tiny.mbg.model.PmsBrand" useGeneratedKeys="true" keyProperty="id" keyColumn="id">
```

```xml
<insert id="insertSelective" parameterType="com.macro.mall.tiny.mbg.model.PmsBrand" useGeneratedKeys="true" keyProperty="id" keyColumn="id">
```

SQL 本體不動。改完後應與 `mall-tiny-02` 同檔案的對應區段一致。

### 4.4 mall-tiny-plus 分頁方言

`mall-tiny-plus/src/main/java/com/macro/mall/tiny/config/MyBatisConfig.java`：`new PaginationInnerInterceptor(DbType.MYSQL)` → `new PaginationInnerInterceptor(DbType.POSTGRE_SQL)`（MyBatis-Plus 3.5.17 的常數名稱，已確認存在）。`PmsBrand` 的 `@TableId(value = "id", type = IdType.AUTO)` 與 YAML 的 `id-type: auto` 不動：PostgreSQL 的 `pms_brand.id` 為 `GENERATED BY DEFAULT AS IDENTITY`（`document/sql/mall_tiny_postgre.sql:32`），`AUTO` 以 JDBC generated keys 回填即可。

### 4.5 CODEBASE_MAP.md

依 AC-12 改寫敘述：把「只有 `mall-tiny-02` 使用 PostgreSQL」改為「`mall-tiny-01`～`04`、`plus`、`boot`、`redis` 使用 PostgreSQL，其餘模組仍使用 MySQL」，§8.1 中 `mall-tiny-02` 的連線說明擴充為適用 7 個模組（啟動指令改為 `mvn -pl <模組> spring-boot:run`）；§7.2 產碼說明擴充到 A 組。共用說明不可直接沿用 `mall-tiny-02` 的 PageHelper、8080 與 Swagger UI 敘述，須逐項註明差異：

- `mall-tiny-boot`：port 8088（API 與 Swagger UI 網址改用 8088）。
- `mall-tiny-01`：沒有 springdoc 依賴，不提供 Swagger UI／OpenAPI。
- `mall-tiny-plus`：分頁由 MyBatis-Plus `PaginationInnerInterceptor(DbType.POSTGRE_SQL)` 處理，不使用 PageHelper；主鍵回填由 `IdType.AUTO` 處理，沒有 `PmsBrandMapper.xml` 的 `useGeneratedKeys` 改動。
- 其餘模組（`01`～`04`、`redis`）：port 8080、PageHelper `helper-dialect: postgresql`、mapper `useGeneratedKeys`，與 `mall-tiny-02` 相同。

新增一行「增量更新日期：<實作日期>」說明本次範圍。其他段落不動。

### 4.6 資料結構 / API 變更

- HTTP API：無變更。
- 執行環境變更：A 組模組改需 PostgreSQL（經 tunnel `127.0.0.1:15432`）與 `PG_PASSWORD` 環境變數；不再連本機 MySQL。

## 5. 預計異動的檔案

`<A>` = `mall-tiny-01`、`03`、`04`、`plus`、`boot`、`redis`；`<A5>` = `<A>` 去掉 `plus`。

| 檔案 | 動作 | 說明 |
|------|------|------|
| `<A>/pom.xml`（6 個） | 修改 | §4.1 driver |
| `<A>/src/main/resources/application.yml`（6 個） | 修改 | §4.2 datasource；`<A5>` 加 pagehelper |
| `<A5>/src/main/resources/com/macro/mall/tiny/mbg/mapper/PmsBrandMapper.xml`（5 個） | 修改 | §4.3 `useGeneratedKeys` |
| `mall-tiny-plus/src/main/java/com/macro/mall/tiny/config/MyBatisConfig.java` | 修改 | §4.4 `DbType.POSTGRE_SQL` |
| `CODEBASE_MAP.md` | 修改 | §4.5／AC-12 |
| `docs/specs/postgresql-migration.md` | 修改 | 僅第 9 節 |

## 6. 驗證指令

前置條件：JDK 21 以上、Maven 3.6.3 以上與 `perl`（macOS／一般 Linux 內建）在 `PATH`；於 repo 根目錄執行。不需要資料庫或網路以外的外部服務。

```bash
mvn -B -ntp -DskipTests test-compile
A="mall-tiny-01 mall-tiny-03 mall-tiny-04 mall-tiny-plus mall-tiny-boot mall-tiny-redis"
A5="mall-tiny-01 mall-tiny-03 mall-tiny-04 mall-tiny-boot mall-tiny-redis"
export DS='spring:
  datasource:
    driver-class-name: org.postgresql.Driver
    url: jdbc:postgresql://127.0.0.1:15432/${PG_DATABASE:mall_tiny}?currentSchema=${PG_SCHEMA:public}
    username: ${PG_USER:mall_app}
    password: ${PG_PASSWORD}
'
for m in $A; do
  y="$m/src/main/resources/application.yml"
  perl -0ne 'exit(index($_, $ENV{DS}) >= 0 ? 0 : 1)' "$y" || { echo "FAIL(AC-2): $y 的 spring.datasource 與 mall-tiny-02 不同"; exit 1; }
  if grep -n 'jdbc:mysql' "$y"; then echo "FAIL(AC-2): $y 仍為 MySQL"; exit 1; fi
  if grep -n 'mysql-connector' "$m/pom.xml"; then echo "FAIL(AC-2): $m/pom.xml 仍含 MySQL driver"; exit 1; fi
  perl -0ne 'exit(m{<dependency>\s*<groupId>org\.postgresql</groupId>\s*<artifactId>postgresql</artifactId>\s*<scope>runtime</scope>\s*</dependency>} ? 0 : 1)' "$m/pom.xml" \
    || { echo "FAIL(AC-2): $m/pom.xml 的 PostgreSQL driver 不符（groupId／runtime scope／不得寫 version）"; exit 1; }
done
for m in $A5; do
  y="$m/src/main/resources/application.yml"
  x="$m/src/main/resources/com/macro/mall/tiny/mbg/mapper/PmsBrandMapper.xml"
  perl -0ne 'exit(/^pagehelper:\n  helper-dialect: postgresql\n/m ? 0 : 1)' "$y" || { echo "FAIL(AC-2): $y 缺 pagehelper.helper-dialect: postgresql"; exit 1; }
  if grep -n 'LAST_INSERT_ID' "$x"; then echo "FAIL(AC-2): $x 仍含 LAST_INSERT_ID"; exit 1; fi
  for id in insert insertSelective; do
    grep -qE "<insert id=\"$id\" [^>]*useGeneratedKeys=\"true\" keyProperty=\"id\" keyColumn=\"id\">" "$x" \
      || { echo "FAIL(AC-2): $x 的 $id 缺 useGeneratedKeys"; exit 1; }
  done
done
if grep -n '^pagehelper:' mall-tiny-plus/src/main/resources/application.yml; then echo 'FAIL(AC-2): plus 不應加 pagehelper'; exit 1; fi
grep -qF 'new PaginationInnerInterceptor(DbType.POSTGRE_SQL)' mall-tiny-plus/src/main/java/com/macro/mall/tiny/config/MyBatisConfig.java
if grep -n 'DbType.MYSQL' mall-tiny-plus/src/main/java/com/macro/mall/tiny/config/MyBatisConfig.java; then echo 'FAIL(AC-2): plus 仍為 MySQL 方言'; exit 1; fi
expected="mall-tiny mall-tiny-05 mall-tiny-06 mall-tiny-07 mall-tiny-08 mall-tiny-alipay mall-tiny-docker mall-tiny-generator mall-tiny-jenkins mall-tiny-mybatis mall-tiny-stream mall-tiny-swagger"
test "$(printf '%s\n' $expected | sort)" = "$(grep -l 'jdbc:mysql' mall-tiny*/src/main/resources/application.yml | cut -d/ -f1 | sort)"
grep -qF 'jdbc:postgresql://' mall-tiny-02/src/main/resources/application.yml
if grep -n '其餘品牌範例需要 MySQL\|其餘資料庫模組仍使用 MySQL\|其餘資料庫模組保留 MySQL' CODEBASE_MAP.md; then echo 'FAIL(AC-12): CODEBASE_MAP 仍寫只有 02 使用 PostgreSQL'; exit 1; fi
echo 'ALL CHECKS PASSED'
```

註：腳本由 `bash -eo pipefail` 執行；反向檢查寫成 `if grep …; then exit 1; fi`，因為 `set -e` 不會對 `! grep` 生效。多行結構（POM dependency 區塊、YAML 區塊）以 `perl -0` 讀入整檔比對；`DS` 以單引號定義，`${PG_…}` 保持字面值。

## 7. 測試要求

本 repo 根 POM 設 `skipTests=true`，既有測試只有需要外部服務的 `contextLoads()`，本任務**不新增**自動化測試（D-7）。驗收以「第 6 節機器關卡＋手動驗證」完成，手動結果由實作者記錄於 §9。手動驗證需 SSH tunnel（`./db-tunnel.sh start`）、`PG_PASSWORD` 環境變數與本機 Redis（`localhost:6379`）；各模組大多使用 port 8080，必須逐一啟動、驗證後停止。

| AC | 驗證方式 | 位置／步驟 | 對應升級 spec 延後項目（D-18） |
|----|----------|------------|------|
| AC-1～AC-3 | 機器關卡 | §6 | — |
| AC-4 | 手動 | `mvn -pl mall-tiny-01 spring-boot:run` + curl | AC-6 |
| AC-5 | 手動 | `mvn -pl mall-tiny-plus spring-boot:run` + curl | AC-7 |
| AC-6 | 手動 | `mvn -pl mall-tiny-04 spring-boot:run` + curl | AC-9 步驟 4 |
| AC-7 | 手動 | `mvn -pl mall-tiny-boot spring-boot:run` + curl | AC-16 步驟 2 |
| AC-8 | 手動 | `mvn -pl mall-tiny-03 spring-boot:run` + curl + `redis-cli` | AC-11（本 AC 步驟 2） |
| AC-9 | 手動 | `mvn -pl mall-tiny-redis spring-boot:run` + curl + `redis-cli` | AC-12（新寫入部分） |
| AC-10 | 手動（邊界／錯誤） | 同 AC-4、AC-9、AC-6 環境 | — |
| AC-11 | 手動（資料清理） | `psql` 或唯讀查詢比對驗證前後 | — |
| AC-12 | 程式碼審查＋§6 grep | `CODEBASE_MAP.md` | — |

升級 spec 的 AC-13 不在本任務，延後到 C 組任務。

## 8. 邊界情況、風險、開放問題與決議

- **邊界情況**：
  - 所有 A 組模組與 `mall-tiny-02` 連同一個資料庫、同一張 `pms_brand`；手動驗證會新增與刪除資料，必須依 AC-11 清理，且不可同時對同一模組並行驗證。
  - `useGeneratedKeys` 與 `keyColumn="id"`：PostgreSQL JDBC 在未指定 keyColumn 時會回傳整列，指定後只回傳 `id`，與 `mall-tiny-02` 相同。
  - 未設定 `PG_PASSWORD` 時，應用仍可能啟動（Druid 首次查詢才連線），但第一次存取資料庫會失敗；這是 D-2 的預期行為，不需處理。
  - `mall-tiny-redis` 中既有的 MySQL 時期快取值不需相容（升級 spec D-18）；驗證前若 Redis 有舊 key，可直接刪除。
- **風險**：
  - **MBG 產碼器無法執行**：A 組 5 個模組的 `generator.properties` 仍指向 MySQL 而 classpath 已無 MySQL driver；若日後恢復 MySQL driver 重新產碼，會覆蓋 `useGeneratedKeys` 並產生 `LAST_INSERT_ID()`。以 AC-12 的文件說明處理（D-4）。
  - **共用遠端資料庫**：驗證資料寫入使用者既有的 PostgreSQL；identity sequence 會前進（不重設）。
  - **回滾方式**：所有變更在 `postgresql-migration` 分支，未合併前捨棄分支即可；不涉及資料庫結構變更。
- **開放問題**：無。

### 8.1 決議紀錄

| ID | 日期 | 決議 | 理由 | 來源 |
|----|------|------|------|------|
| D-1 | 2026-10-17 | 本任務只遷移 A 組 6 個模組（`01`、`03`、`04`、`plus`、`boot`、`redis`）；B 組（只需 PostgreSQL）與 C 組（另需 ES／MongoDB／RabbitMQ／MinIO）分別為後續任務 | 一步一步完成；A 組剛好涵蓋升級 spec D-18 延後的 AC（AC-13 除外），完成條件明確 | 人類 |
| D-2 | 2026-10-17 | 連線設定與 `mall-tiny-02` 完全相同：經 SSH tunnel `127.0.0.1:15432`，database／user／schema 預設 `mall_tiny`／`mall_app`／`public`，可由 `PG_DATABASE`／`PG_USER`／`PG_SCHEMA` 覆寫，密碼只來自 `PG_PASSWORD` | 7 個 PostgreSQL 模組設定一致；資料表已在該資料庫中，不需匯入 | 人類 |
| D-3 | 2026-10-17 | 改法完全比照 `mall-tiny-02`：driver `runtime` scope 不寫版本、PageHelper 明確設 `helper-dialect: postgresql`、mapper 以 `useGeneratedKeys` + `keyColumn="id"` 取代 `LAST_INSERT_ID()` | 該做法已在 `mall-tiny-02` 對同一張表實測通過（升級 spec §9.3）；明確設定方言避免依 JDBC URL 自動偵測的差異 | Claude |
| D-4 | 2026-10-17 | 不遷移 MBG／MyBatis-Plus 產碼設定，只在 `CODEBASE_MAP.md` 說明其現況與風險 | 與 D-17 一致；產碼器設定遷移涉及 `sqlStatement`、identity 設定與重新產碼，屬另一個任務 | Claude |
| D-5 | 2026-10-17 | 升級 spec AC-12 的「讀取升級前寫入的快取」不驗證，只驗新寫入值格式、TTL 與 `@CacheEvict` | 依升級 spec D-18：無既有線上快取 | 人類（D-18） |
| D-6 | 2026-10-17 | 手動驗證只透過 HTTP API 寫入驗證資料，結束後刪除並比對 id 集合；不重設 identity sequence | 驗證對象是使用者既有的遠端資料庫，不得留下測試資料或改動 schema | Claude |
| D-7 | 2026-10-17 | 不新增自動化測試 | 與升級任務一致；既有測試皆需外部服務且 `skipTests=true` | Claude |
| D-8 | 2026-10-17 | `mall-tiny-03` 的手動驗收（AC-8）加入 `GET /brand/list` 分頁查詢，不只驗 Redis 驗證碼 | 驗證碼流程只用 Redis，無法證明該模組的 PostgreSQL 連線與 PageHelper 方言生效；應用能啟動不代表資料庫連得上（Druid 延遲連線） | Codex P1-1 |
| D-9 | 2026-10-17 | AC-2 的細項（POM dependency 的 groupId／runtime scope／無 version、datasource 區塊位置與順序、pagehelper 為頂層區塊、`useGeneratedKeys` 分別位於 `insert` 與 `insertSelective`、`plus` 不加 pagehelper）全部改由 §6 的結構檢查（`perl -0` 整檔比對、以 `id` 定位的 `grep -E`）驗證，而非改標為程式碼審查 | 讓「AC-1～AC-3 由機器關卡自動驗證」的宣稱成立；檢查已對 `mall-tiny-02` 正向實測通過、對未遷移的 `mall-tiny-01` 反向實測失敗 | Codex P1-2 |
| D-10 | 2026-10-17 | `CODEBASE_MAP.md` 擴寫為 7 個模組時須逐項註明差異（`boot` 用 8088、`01` 無 Swagger UI、`plus` 用 MyBatis-Plus 分頁與 `IdType.AUTO`），並納入 AC-12 | 原文只適用 `mall-tiny-02`，直接沿用會給出錯誤的網址與設定指引 | Codex P1-3 |

---

## 9. 實作備註（由實作者填寫）

實作日期：2026-10-17。分支為 `postgresql-migration`，基準 HEAD 為 `96bbfcbea24ea549fec6b30cf7f5f1a9488492a9`；本次變更尚未 commit。

- **偏離 spec 之處與原因**：應用實作依 §4 完成。驗收環境依使用者本次對話的補充，Redis 改由 PostgreSQL 所在 Droplet 的 `mall-redis` container 提供，經 SSH tunnel 對應本機 `127.0.0.1:6379`。使用者另明確要求把兩條通道整合進同一個 `db-tunnel.sh`，因此依此補充授權修改該腳本及 `CODEBASE_MAP.md` 的 tunnel 導覽；這是對 §3.2 不修改腳本與 §4.5 文件範圍的例外。`.db-tunnel.env`、應用 Redis 設定與本 spec 第 1～8 節保持原文。
- **未完成的項目**：無；AC-1～AC-12 均已完成對應的機器關卡、手動驗收或程式碼審查。升級 spec 的 AC-13 仍依原非目標排除。
- **需要審查者特別注意的地方**：6 個 POM／datasource、5 個 PageHelper／mapper，以及 `plus` 分頁方言均已修改。YAML 的其他鍵與註解、mapper SQL 本體、根 POM、A 組以外模組、產碼設定、安全與 Redis 實作均未改動；沒有新增或修改測試類別、執行產碼器或匯入 SQL。工作開始前的 index 保持原樣，`db-tunnel.sh` 的授權增補留在未 staged 的工作目錄。密碼只經隱藏輸入傳入驗證程序記憶體與子程序環境，JWT 在保存輸出前遮蔽。

### 9.1 第 6 節機器關卡與範圍檢查

- 環境：macOS arm64、Eclipse Temurin JDK `21.0.12.1`、Maven `3.10.0`。
- 將第 6 節 bash 區塊原樣取出，於 repo 根目錄執行 `bash -eo pipefail /tmp/mall-postgresql-migration-20261017/verify-section6.sh`；exit `0`。完整輸出在 `/tmp/mall-postgresql-migration-20261017/section6.log`。
- 根 reactor 的 21 個項目（根專案＋20 個模組）全部 `SUCCESS`；AC-1～AC-3 與 AC-12 的文字檢查通過。這是 `test-compile` 與結構檢查，沒有執行測試類別。

```text
[INFO] BUILD SUCCESS
[INFO] Total time:  33.699 s
[INFO] Finished at: 2026-10-17T19:23:07+08:00
ALL CHECKS PASSED
```

- `git diff --check` 通過。以初始 SHA-256 核對本 spec 第 9 節前的全部內容、既有 staged diff 與 `.db-tunnel.env` 均未變動；HEAD 與分支未變動。`db-tunnel.sh` 的授權擴充另見 §9.4。
- AC-12 程式碼審查：`CODEBASE_MAP.md` 已列出 7 個 PostgreSQL 模組，補上 `boot` 的 8088、`01` 無 Swagger UI／OpenAPI、`plus` 的 MyBatis-Plus 分頁與 `IdType.AUTO` 差異，以及 A 組產碼設定仍為 MySQL、無法直接執行與 MBG 重新產碼覆蓋回填設定的限制。更新區域的本地連結均可解析。

### 9.2 手動 AC 結果

實際以 `mvn -B -ntp -pl <模組> spring-boot:run` 分兩批依序啟動 `01`、`plus`、`boot`，再啟動 `04`、`03`、`redis`，透過 `15432`／`6379` tunnel 連到 Droplet 上的 PostgreSQL／Redis，以 `curl` 呼叫 HTTP API，逐一完成後停止應用。Redis 查核經 SSH 執行 `docker exec mall-redis redis-cli --raw ...`。下表為回應中驗收欄位的節錄；完整已遮蔽回應在 `/tmp/mall-postgresql-migration-20261017/live-postgres.json` 與 `live-redis.json`，各模組 log 在同目錄的 `mall-tiny-<模組>.log`。

| AC | 結果 | 關鍵輸出與說明 |
|----|------|----------------|
| AC-4 | 通過 | `01`：`GET /brand/list?pageNum=1&pageSize=3` → HTTP 200、`code=200`、`list` 的 id 為 `[1,2,3]`、`total=12`。建立 `pg-migration-20261017-01-57999cdb` → `code=200`、`data.id=61`；讀回同名 id 61。刪除 → `code=200`，再讀回 → `{"code":200,"message":"操作成功","data":null}`。log 有 `{dataSource-1} inited`，無 `HikariPool`。 |
| AC-5 | 通過 | `plus`：`GET /brand/list?pageNum=1&pageSize=2` → HTTP 200、`code=200`、`list` 的 id 為 `[1,2]`、`total=12`。建立 `pg-migration-20261017-plus-38229382` → `code=200`、`data.id=62`；讀回同名 id 62。刪除 → `code=200`，再讀回 → `{"code":200,"message":"操作成功","data":null}`。 |
| AC-6 | 通過 | `04`：匿名 `GET /brand/listAll` → HTTP 200、`code=401` JSON；admin 登入取得 token 後 → HTTP 200、`code=200`、`data` 長度 12。macro 登入取得 token 後，`GET /brand/list` → HTTP 200、`{"code":403,"message":"没有相关权限","data":"Access Denied"}`。兩次登入皆 `code=200`，token 已遮蔽。 |
| AC-7 | 通過 | `boot`，port 8088：匿名 `GET /brand/listAll` → HTTP 200、`{"code":401,"message":"暂未登录或token已经过期","data":"Full authentication is required to access this resource"}`。admin 登入 → `{"code":200,"message":"操作成功","data":{"tokenHead":"Bearer","token":"<redacted>"}}`；帶入 token 後 → HTTP 200、`code=200`、`data` 長度 12，id 集合與驗證前一致。 |
| AC-8 | 通過 | `03`：`GET /brand/list?pageNum=1&pageSize=3` → HTTP 200、`code=200`、`list` 的 id 為 `[1,2,3]`、`total=12`。取得驗證碼 → `code=200`，`data` 經檢查為 6 位數；`redis-cli EXISTS portal:authCode:13800000000` → `1`，`TTL` → `115`。帶入該碼校驗 → `{"code":200,"message":"验证码校验成功","data":null}`；完成後刪除本次驗證碼 key，`DEL` → `1`。 |
| AC-9 | 通過 | `redis`：建立 `pg-migration-20261017-redis-cf747fd0` → `code=200`、`data.id=63`；`GET /brand/63` → `code=200`。`redis-cli GET mall::pms:brand:63` 以 `["com.macro.mall.tiny.mbg.model.PmsBrand",{` 開頭，不含 `@class`；`TTL` → `86397`。刪除 id 63 → `code=200`；快取 `EXISTS` → `0`，再讀品牌 → `code=200`、`data=null`。 |
| AC-10 | 通過 | 步驟 1，`01`：第 1000 頁 → HTTP 200、`{"code":200,"message":"操作成功","data":{"pageNum":1000,"pageSize":3,"totalPage":4,"total":12,"list":[]}}`。步驟 2，`redis`：`GET /brand/999999` → HTTP 200、`{"code":200,"message":"操作成功","data":null}`，`redis-cli EXISTS mall::pms:brand:999999` → `0`。步驟 3，`04`：帶有效 admin token 呼叫 `/brand/abc` → HTTP 400、`{"status":400,"error":"Bad Request","path":"/brand/abc"}`（省略 timestamp）。 |
| AC-11 | 通過 | 全部手動驗證結束後仍為 `N=12`，id 集合與兩批驗證前完全相同；驗證品牌 61、62、63 均已刪除，見 §9.3。 |

AC-4 的連線池 log 節錄：

```text
2026-10-17T19:35:37.083+08:00 INFO 93274 --- [main] com.alibaba.druid.pool.DruidDataSource : {dataSource-1} inited
```

AC-9 的 Redis 值與 TTL 節錄：

```text
GET mall::pms:brand:63
["com.macro.mall.tiny.mbg.model.PmsBrand",{"id":63,"name":"pg-migration-20261017-redis-cf747fd0","firstLetter":null,"sort":null,"factoryStatus":null,"showStatus":null,"productCount":null,"productCommentCount":null,"logo":null,"bigPic":null,"brandStory":null}]
TTL mall::pms:brand:63
86397
EXISTS mall::pms:brand:63（HTTP 刪除品牌後）
0
```

### 9.3 資料清理

透過 PostgreSQL JDBC 的唯讀連線，在每批驗證前後執行以下查詢；查詢完成後 rollback：

```sql
SELECT json_build_object(
  'count', count(*),
  'ids', coalesce(json_agg(id ORDER BY id), '[]'::json)
)::text FROM pms_brand;
```

最初驗證前、兩批驗證交界與全部驗證結束後的結果均為：

```json
{"count":12,"ids":[1,2,3,4,5,6,21,49,50,51,58,59]}
```

比對結果：筆數相同、id 集合相同，驗證資料 61／62／63 不在集合內。沒有修改 schema／資料表／sequence，也未重設已前進的 identity。6 個模組的驗證程序皆已停止；PostgreSQL 與 Redis 兩條正式 tunnel 保持運作。原始基準另存於 `/tmp/mall-postgresql-migration-20261017/database-before.json`。

### 9.4 使用者補充：同一腳本管理 PostgreSQL 與 Redis tunnel

使用者要求「直接放在同一個 db-tunnel.sh，這樣可以直接全部啟動」。實作沿用原有 SSH 設定與 PostgreSQL control socket，新增獨立的 Redis control socket；同一命令依序管理兩條連線，既有 PostgreSQL 連線不需重建。

- `./db-tunnel.sh start`：在背景啟動缺少的通道，預設為本機 `15432 → Droplet 127.0.0.1:5432` 與本機 `6379 → Droplet 127.0.0.1:6379`；重複執行不重建已運作的連線。
- `./db-tunnel.sh status`：分別回報 PostgreSQL／Redis，只有兩條 SSH 通道皆執行中才回傳 0。這是 tunnel 狀態，遠端服務仍須另外啟動。
- `./db-tunnel.sh stop`：關閉兩條由此腳本管理的通道，重複停止可成功返回。
- 可選設定為 `TUNNEL_REDIS_LOCAL_PORT`／`TUNNEL_REDIS_HOST`／`TUNNEL_REDIS_PORT`；現有 `.db-tunnel.env` 不需增加欄位，內容未改動。兩服務不可使用相同本機 port。

驗證：`bash -n db-tunnel.sh` 與 `git diff --check` 通過。在獨立的本機 `25432`／`26379` 與 `/tmp` 狀態目錄完成下列實測；證據為 `/tmp/mall-postgresql-migration-20261017/tunnel-verification.json`：

1. 先以原腳本建立僅 PostgreSQL 的通道；新 `status` 正確回傳 1 並顯示 Redis 未執行。
2. 模擬 Redis 本機 port 被其他程序占用；`start` 回傳 1，PostgreSQL 連線 PID 不變，`status` 不誤報 Redis 已啟動。
3. 釋放測試 port 後，`start` 補上 Redis；重複 `start` 時兩條連線 PID 均不變，`status` 回傳 0。
4. PostgreSQL SSLRequest 得到協定回應 `N`，Redis `PING` 回傳 `+PONG`。
5. `stop` 後兩個測試 port 均已釋放；重複 `stop` 回傳 0，`status` 回傳 1。相同本機 port 的設定會被拒絕。
6. 原有正式 PostgreSQL PID 全程保持不變。測試後已執行正式 `start` 補上本機 `6379` 通道，`status` 回傳 0；兩條正式通道保持啟動，遠端 container 未被腳本重啟或修改。

### 9.5 使用者複驗（2026-10-18）

使用者在 §9.2 之後親自重跑全部手動 AC。環境與 §9.2 相同：`./db-tunnel.sh start` 建立 `15432`／`6379` 兩條 tunnel，連到 Droplet 上的 PostgreSQL 18.6 與 `mall-redis`（Redis 7.4.11）。應用以 `mvn -pl <模組> spring-boot:run` 逐一啟動，驗證後停止。PostgreSQL 與 Redis 的查詢在 DataGrip 執行，兩個連線分別為 `jdbc:postgresql://localhost:15432/mall_tiny` 與 `jdbc:redis://127.0.0.1:6379/0`，都直接走上述 tunnel，沒有使用 DataGrip 內建的 SSH。驗證基準沿用 §9.3：`N=12`，id 集合 `[1,2,3,4,5,6,21,49,50,51,58,59]`。

| AC | 結果 | 關鍵輸出與說明 |
|----|------|----------------|
| AC-4 | 通過 | `01`：`GET /brand/list?pageNum=1&pageSize=3` → `code=200`、`list` 的 id 為 `[1,2,3]`、`total=12`、`totalPage=4`。建立 `manual-test-01` → `data.id=64`；讀回 → `code=200`、`name="manual-test-01"`。刪除 → `code=200`，再讀回 → `{"code":200,"message":"操作成功","data":null}`。使用者確認 log 有 `{dataSource-1} inited`，沒有 `HikariPool`。 |
| AC-5 | 通過 | `plus`：`GET /brand/list?pageNum=1&pageSize=2` → `code=200`、`total=12`、`list` 長度 2。建立 `manual-test-plus` → `data.id=65`；讀回同名資料。刪除 → `code=200`，再讀回 → `data=null`。 |
| AC-6 | 通過 | `04`：匿名 `GET /brand/listAll` → `code=401`。admin 登入取得 token（已遮蔽）後 → `code=200`、`data` 長度 12。macro 的 token 呼叫 `GET /brand/list` → `{"code":403,"message":"没有相关权限","data":"Access Denied"}`。 |
| AC-7 | 通過 | `boot`，port 8088：匿名 `GET /brand/listAll` → `{"code":401,"message":"暂未登录或token已经过期","data":"Full authentication is required to access this resource"}`。admin token 呼叫 → `code=200`、`data` 長度 12。 |
| AC-8 | 通過 | `03`：`GET /brand/list?pageNum=1&pageSize=3` → `code=200`、`total=12`、`list` 長度 3。取得 6 位數驗證碼；帶入校驗 → `{"code":200,"message":"验证码校验成功","data":null}`。第一組驗證碼校驗前沒有查 TTL，因此另取一組新驗證碼，在 DataGrip 執行 `TTL portal:authCode:13800000000` → `113`。校驗成功不會刪除 key（`UmsMemberServiceImpl.verifyAuthCode`），這次沒有手動 `DEL`，key 會在 120 秒後自然過期。 |
| AC-9 | 通過 | `redis`：建立 `manual-test-redis` → `data.id=66`；`GET /brand/66` → `code=200`。使用者第一次在 DataGrip 執行 `TTL mall::pms:brand:66` 得到 `-2`，詳見下方說明。再次 `GET /brand/66` 後，經 `6379` tunnel 唯讀查詢：`EXISTS` → `1`、`TTL` → `86220`，值的前 60 字元為 `["com.macro.mall.tiny.mbg.model.PmsBrand",{"id":66,"name":"ma`，符合 `WRAPPER_ARRAY`。這次只讀取前 60 字元，沒有檢查完整值是否含 `@class`（§9.2 已確認不含）。刪除 id 66 → `code=200`；使用者在 DataGrip 確認 `EXISTS mall::pms:brand:66` → `0`。 |
| AC-10 | 通過 | 步驟 1，`01`：`GET /brand/list?pageNum=1000&pageSize=3` → `HTTP 200`、`{"code":200,"message":"操作成功","data":{"pageNum":1000,"pageSize":3,"totalPage":4,"total":12,"list":[]}}`。步驟 2，`redis`：使用者回報 `GET /brand/999999` 後，`EXISTS mall::pms:brand:999999` → `0`。步驟 3，`04`：帶 admin token 呼叫 `GET /brand/abc` → `HTTP 400`。 |
| AC-11 | 通過 | 全部驗證結束後，DataGrip 查詢 `SELECT count(*), json_agg(id ORDER BY id) FROM pms_brand` → `12`、`[1, 2, 3, 4, 5, 6, 21, 49, 50, 51, 58, 59]`，與基準相同。`SELECT id, name FROM pms_brand WHERE name LIKE 'manual-test%' OR name LIKE 'pg-migration%'` 沒有結果。 |

**AC-9 第一次 TTL 為 `-2` 的說明**：比對 DataGrip 的資料來源設定（`~/DataGripProjects/default/.idea/dataSources.xml`），Redis 連線與應用相同，都是 `127.0.0.1:6379`、database 0，沒有開 SSH，console 指令也正確，因此排除連到不同 Redis 或 database 的可能。之後查到的 `TTL=86220`，代表 key 約在查詢前 180 秒寫入，時間點與第二次 `GET /brand/66` 相符。因此推測使用者查到 `-2` 時快取確實還不存在，但第一次 `GET` 為什麼沒有寫入快取，沒有查明原因。第二次 `GET` 證實 `@Cacheable` 會寫入正確格式與 TTL 的快取；使用者其後回報以另一筆驗證品牌重測，連同 id 66 與 999999，三個 `EXISTS` 都是 `0`。重測品牌的 id 與 TTL 觀察值沒有記錄在本節，該品牌已刪除（見 AC-11）。

本輪 identity sequence 前進到 66 以上，屬預期行為，沒有重設。
