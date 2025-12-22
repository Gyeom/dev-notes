---
title: "SQLite WAL 모드로 고처리량 분석 데이터 저장"
date: 2025-11-18
draft: false
tags: ["SQLite", "WAL", "Database", "Performance", "Repository Pattern", "Kotlin"]
categories: ["Database"]
summary: "SQLite WAL 모드를 활용한 동시 읽기/쓰기 처리와 Repository Pattern 기반 분석 데이터 저장 시스템 설계"
---

> 이 글은 [Claude Flow](https://github.com/Gyeom/claude-flow) 프로젝트를 개발하면서 정리한 내용이다. 전체 아키텍처는 [개발기](/dev-notes/posts/2024-12-22-claude-flow-development-story/)에서 확인할 수 있다.

## 개요

AI 에이전트 플랫폼을 개발하면서 실행 이력, 피드백, 분석 데이터를 저장해야 했다. 초기에는 PostgreSQL을 고려했지만, 다음 이유로 SQLite를 선택했다.

- 단일 서버 환경에서 충분한 성능
- 별도 DB 서버 불필요 (배포 간소화)
- WAL 모드로 동시 읽기/쓰기 가능
- 파일 기반이라 백업과 마이그레이션이 단순함

하지만 기본 SQLite는 쓰기 작업 시 전체 DB를 잠근다. 이 문제를 WAL(Write-Ahead Logging) 모드로 해결했다.

## WAL 모드란

### 기본 Journal 모드의 문제

SQLite는 기본적으로 Rollback Journal 모드를 사용한다. 쓰기 트랜잭션이 시작되면 전체 데이터베이스를 잠그고, 읽기 작업도 차단된다.

```kotlin
// 기본 모드: 쓰기 중에는 읽기 불가
connection.prepareStatement("INSERT INTO executions ...").use { stmt ->
    stmt.executeUpdate()  // 이 동안 모든 SELECT 쿼리가 대기
}
```

고처리량 환경에서 이는 심각한 병목이다. 실시간 분석 쿼리와 새 실행 기록 저장이 서로를 차단하면서 응답 시간이 늘어난다.

### WAL 모드의 동작 원리

WAL 모드는 변경 사항을 별도의 WAL 파일(`db-wal`)에 먼저 기록한다. 읽기는 메인 DB 파일과 WAL 파일을 함께 조회하여 최신 상태를 본다.

```
[메인 DB 파일]  ← 주기적 Checkpoint
     ↑
[WAL 파일] ← 쓰기 작업이 여기에 기록
     ↓
[읽기 작업] → 메인 DB + WAL 합쳐서 읽기
```

핵심 특징:

- **읽기와 쓰기가 동시 진행**: 쓰기가 진행 중이어도 읽기는 차단되지 않음
- **다중 읽기 허용**: 여러 스레드가 동시에 읽기 가능
- **단일 쓰기**: 한 번에 하나의 쓰기 트랜잭션만 허용 (SQLite의 근본적 제약)

### Checkpoint 메커니즘

WAL 파일이 커지면 주기적으로 Checkpoint가 실행되어 내용을 메인 DB로 옮긴다.

```kotlin
// 자동 Checkpoint: WAL 파일이 1000 페이지 도달 시
// 또는 수동 실행
connection.prepareStatement("PRAGMA wal_checkpoint(PASSIVE)").use {
    it.executeUpdate()
}
```

Checkpoint 모드:

- `PASSIVE`: 읽기 작업과 충돌하지 않는 선에서 실행
- `FULL`: 가능한 모든 WAL 내용을 메인 DB로 이동
- `RESTART`: WAL 파일을 0부터 재시작
- `TRUNCATE`: WAL 파일 크기를 최소화

## WAL 모드 설정

SQLite 연결 초기화 시 PRAGMA로 설정한다.

```kotlin
Class.forName("org.sqlite.JDBC")
connection = DriverManager.getConnection("jdbc:sqlite:$dbPath")

// WAL 모드 활성화
connection.createStatement().use { stmt ->
    stmt.executeUpdate("PRAGMA journal_mode=WAL")
    stmt.executeUpdate("PRAGMA synchronous=NORMAL")
    stmt.executeUpdate("PRAGMA busy_timeout=5000")
}
```

주요 설정:

- `journal_mode=WAL`: WAL 모드 활성화
- `synchronous=NORMAL`: WAL 모드에서는 FULL 대신 NORMAL로 충분 (성능 향상)
- `busy_timeout`: 쓰기 경합 시 대기 시간 (밀리초)

## Repository Pattern 설계

SQLite를 직접 다루는 대신 Repository 패턴으로 추상화했다. 이렇게 하면 SQL을 비즈니스 로직에서 분리하고, 테스트와 유지보수가 쉬워진다.

### Repository 인터페이스

```kotlin
interface Repository<T, ID> {
    fun save(entity: T)
    fun findById(id: ID): T?
    fun findAll(): List<T>
    fun deleteById(id: ID): Boolean
    fun existsById(id: ID): Boolean
    fun count(): Long
}
```

표준 CRUD 작업을 정의한다. Spring Data JPA와 유사한 구조지만, SQLite에 최적화했다.

### BaseRepository 구현

모든 Repository가 상속받는 기본 클래스다.

```kotlin
abstract class BaseRepository<T, ID>(
    protected val connectionProvider: ConnectionProvider
) : Repository<T, ID> {

    protected abstract val tableName: String
    protected abstract val primaryKeyColumn: String
    protected abstract fun mapRow(rs: ResultSet): T
    protected abstract fun getId(entity: T): ID

    protected val connection: Connection
        get() = connectionProvider.getConnection()

    // Query Builder 헬퍼
    protected fun query(): QueryBuilder =
        QueryBuilder.from(connection, tableName)

    protected fun insert(): InsertBuilder =
        InsertBuilder(connection, tableName)

    protected fun update(): UpdateBuilder =
        UpdateBuilder(connection, tableName)

    protected fun delete(): DeleteBuilder =
        DeleteBuilder(connection, tableName)

    override fun findById(id: ID): T? {
        return query()
            .select("*")
            .where("$primaryKeyColumn = ?", id)
            .executeOne { mapRow(it) }
    }

    override fun count(): Long {
        return query()
            .select("COUNT(*)")
            .executeOne { it.getLong(1) } ?: 0L
    }
}
```

핵심 설계 결정:

1. **ConnectionProvider 의존성**: 테스트 시 Mock 연결 주입 가능
2. **Query Builder 통합**: SQL 문자열 직접 작성 대신 fluent API 사용
3. **Row Mapper 추상화**: ResultSet을 도메인 객체로 변환하는 로직 분리

### QueryBuilder 구현

SQL Injection을 방지하고 가독성을 높이기 위해 타입 안전한 쿼리 빌더를 만들었다.

```kotlin
class QueryBuilder(private val connection: Connection) {
    private var selectClause: String = "*"
    private var fromClause: String = ""
    private var whereConditions: MutableList<String> = mutableListOf()
    private var parameters: MutableList<Any?> = mutableListOf()
    private var orderByClause: String? = null
    private var limitValue: Int? = null

    fun select(columns: String): QueryBuilder {
        selectClause = columns
        return this
    }

    fun from(table: String): QueryBuilder {
        fromClause = table
        return this
    }

    fun where(condition: String, vararg params: Any?): QueryBuilder {
        whereConditions.add(condition)
        parameters.addAll(params)
        return this
    }

    fun whereBetween(column: String, from: Any, to: Any): QueryBuilder {
        whereConditions.add("$column BETWEEN ? AND ?")
        parameters.add(from)
        parameters.add(to)
        return this
    }

    fun orderBy(column: String, direction: SortDirection): QueryBuilder {
        orderByClause = "$column ${direction.sql}"
        return this
    }

    fun limit(limit: Int): QueryBuilder {
        limitValue = limit
        return this
    }

    fun <T> execute(mapper: (ResultSet) -> T): List<T> {
        val results = mutableListOf<T>()
        prepare().use { stmt ->
            stmt.executeQuery().use { rs ->
                while (rs.next()) {
                    results.add(mapper(rs))
                }
            }
        }
        return results
    }

    private fun prepare(): PreparedStatement {
        val sql = build()
        val stmt = connection.prepareStatement(sql)
        parameters.forEachIndexed { index, param ->
            setParameter(stmt, index + 1, param)
        }
        return stmt
    }

    private fun build(): String {
        val sql = StringBuilder()
        sql.append("SELECT $selectClause FROM $fromClause")

        if (whereConditions.isNotEmpty()) {
            sql.append(" WHERE ${whereConditions.joinToString(" AND ")}")
        }

        orderByClause?.let { sql.append(" ORDER BY $it") }
        limitValue?.let { sql.append(" LIMIT $it") }

        return sql.toString()
    }
}
```

장점:

- **PreparedStatement 자동 생성**: 파라미터 바인딩 자동화
- **Fluent API**: 메서드 체이닝으로 SQL 구조 명확화
- **타입 안전성**: 컴파일 타임에 오류 감지

## 실제 사용 예시

### ExecutionRepository 구현

AI 에이전트 실행 기록을 저장하는 Repository다.

```kotlin
class ExecutionRepository(
    connectionProvider: ConnectionProvider
) : BaseRepository<ExecutionRecord, String>(connectionProvider) {

    override val tableName = "executions"
    override val primaryKeyColumn = "id"

    override fun mapRow(rs: ResultSet): ExecutionRecord {
        return ExecutionRecord(
            id = rs.getString("id"),
            prompt = rs.getString("prompt"),
            result = rs.getString("result"),
            status = rs.getString("status"),
            agentId = rs.getString("agent_id"),
            durationMs = rs.getLong("duration_ms"),
            inputTokens = rs.getInt("input_tokens"),
            outputTokens = rs.getInt("output_tokens"),
            createdAt = Instant.parse(rs.getString("created_at"))
        )
    }

    override fun getId(entity: ExecutionRecord) = entity.id

    override fun save(entity: ExecutionRecord) {
        insert()
            .columns(
                "id" to entity.id,
                "prompt" to entity.prompt,
                "result" to entity.result,
                "status" to entity.status,
                "agent_id" to entity.agentId,
                "duration_ms" to entity.durationMs,
                "input_tokens" to entity.inputTokens,
                "output_tokens" to entity.outputTokens,
                "created_at" to entity.createdAt.toString()
            )
            .execute()
    }

    fun findRecent(limit: Int = 50): List<ExecutionRecord> {
        return query()
            .select("*")
            .orderBy("created_at", QueryBuilder.SortDirection.DESC)
            .limit(limit)
            .execute { mapRow(it) }
    }

    fun findByDateRange(dateRange: DateRange): List<ExecutionRecord> {
        return query()
            .select("*")
            .whereBetween("created_at",
                dateRange.from.toString(),
                dateRange.to.toString())
            .orderBy("created_at", QueryBuilder.SortDirection.DESC)
            .execute { mapRow(it) }
    }
}
```

### AnalyticsRepository 구현

분석 쿼리만 다루는 읽기 전용 Repository다.

```kotlin
class AnalyticsRepository(
    connectionProvider: ConnectionProvider,
    private val executionRepository: ExecutionRepository,
    private val feedbackRepository: FeedbackRepository
) : BaseRepository<Nothing, Nothing>(connectionProvider) {

    fun getOverviewStats(dateRange: DateRange): OverviewStats {
        // 현재 기간 통계
        val currentStats = executionRepository.getAggregatedStats(dateRange)

        // 이전 기간 통계 (비교용)
        val periodDuration = dateRange.to.epochSecond - dateRange.from.epochSecond
        val previousDateRange = DateRange(
            from = dateRange.from.minusSeconds(periodDuration),
            to = dateRange.from
        )
        val previousStats = executionRepository.getAggregatedStats(previousDateRange)

        // Percentile 계산
        val percentiles = getPercentiles(dateRange)

        return OverviewStats(
            totalRequests = currentStats.totalRequests,
            successRate = currentStats.successfulRequests.toDouble() /
                          currentStats.totalRequests,
            totalCostUsd = currentStats.totalCostUsd,
            percentiles = percentiles,
            comparison = ComparisonStats(
                requestsChangePct = calculateChangePct(
                    previousStats.totalRequests,
                    currentStats.totalRequests
                )
            )
        )
    }

    fun getPercentiles(dateRange: DateRange): PercentileStats {
        val durations = executionRepository.getSuccessfulDurations(dateRange)

        if (durations.isEmpty()) {
            return PercentileStats(0, 0, 0, 0)
        }

        return PercentileStats(
            p50 = calculatePercentile(durations, 50),
            p90 = calculatePercentile(durations, 90),
            p95 = calculatePercentile(durations, 95),
            p99 = calculatePercentile(durations, 99)
        )
    }

    private fun calculatePercentile(sortedList: List<Long>, percentile: Int): Long {
        val index = (percentile / 100.0 * sortedList.size)
            .toInt()
            .coerceIn(0, sortedList.size - 1)
        return sortedList[index]
    }

    fun getTimeSeries(
        dateRange: DateRange,
        granularity: TimeGranularity
    ): List<TimeSeriesPoint> {
        val dateFormat = when (granularity) {
            TimeGranularity.HOUR -> "%Y-%m-%dT%H:00:00"
            TimeGranularity.DAY -> "%Y-%m-%d"
            TimeGranularity.WEEK -> "%Y-W%W"
        }

        return executeQuery(
            """
            SELECT
                strftime('$dateFormat', created_at) as time_bucket,
                COUNT(*) as requests,
                SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) as successful,
                COALESCE(AVG(duration_ms), 0) as avg_duration
            FROM executions
            WHERE created_at BETWEEN ? AND ?
            GROUP BY time_bucket
            ORDER BY time_bucket
            """.trimIndent(),
            dateRange.from.toString(),
            dateRange.to.toString()
        ) {
            TimeSeriesPoint(
                timestamp = it.getString("time_bucket"),
                requests = it.getLong("requests"),
                successful = it.getLong("successful"),
                avgDurationMs = it.getLong("avg_duration")
            )
        }
    }
}
```

이 설계의 핵심:

- **도메인 분리**: ExecutionRepository는 CRUD, AnalyticsRepository는 집계 쿼리
- **타입 안전성**: Nothing 타입으로 save/findById 같은 불필요한 메서드 차단
- **조합 가능**: 여러 Repository를 조합해서 복잡한 분석 수행

## 성능 최적화

### 인덱스 전략

자주 조회되는 컬럼에 인덱스를 생성한다.

```kotlin
connection.createStatement().use { stmt ->
    stmt.executeUpdate(
        "CREATE INDEX IF NOT EXISTS idx_executions_created " +
        "ON executions(created_at)"
    )
    stmt.executeUpdate(
        "CREATE INDEX IF NOT EXISTS idx_executions_user " +
        "ON executions(user_id)"
    )
    stmt.executeUpdate(
        "CREATE INDEX IF NOT EXISTS idx_executions_channel " +
        "ON executions(channel)"
    )
}
```

날짜 범위 쿼리가 많으므로 `created_at`에 인덱스를 걸었다. WAL 모드에서는 인덱스 업데이트도 WAL 파일에 기록되므로 쓰기 성능 저하가 적다.

### Pagination 지원

대량 데이터 조회 시 페이징을 사용한다.

```kotlin
data class PageRequest(
    val page: Int = 0,
    val size: Int = 20,
    val sortBy: String? = null,
    val sortDirection: SortDirection = SortDirection.DESC
) {
    val offset: Int get() = page * size
}

fun findAll(pageRequest: PageRequest): Page<T> {
    val total = count()

    val query = query()
        .select("*")
        .limit(pageRequest.size)
        .offset(pageRequest.offset)

    pageRequest.sortBy?.let { sortBy ->
        query.orderBy(sortBy, pageRequest.sortDirection.toQueryBuilder())
    }

    val content = query.execute { mapRow(it) }

    return Page.of(content, pageRequest.page, pageRequest.size, total)
}
```

### 집계 쿼리 최적화

단일 쿼리로 여러 통계를 한 번에 계산한다.

```kotlin
fun getAggregatedStats(dateRange: DateRange): AggregatedStats {
    return executeQueryOne(
        """
        SELECT
            COUNT(*) as total,
            SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) as successful,
            COALESCE(SUM(cost), 0) as total_cost,
            COALESCE(SUM(input_tokens), 0) as input_tokens,
            COALESCE(SUM(output_tokens), 0) as output_tokens,
            COALESCE(AVG(duration_ms), 0) as avg_duration
        FROM executions
        WHERE created_at BETWEEN ? AND ?
        """.trimIndent(),
        dateRange.from.toString(),
        dateRange.to.toString()
    ) {
        AggregatedStats(
            totalRequests = it.getLong("total"),
            successfulRequests = it.getLong("successful"),
            totalCostUsd = it.getDouble("total_cost"),
            totalInputTokens = it.getLong("input_tokens"),
            totalOutputTokens = it.getLong("output_tokens"),
            avgDurationMs = it.getDouble("avg_duration")
        )
    } ?: AggregatedStats(0, 0, 0.0, 0, 0, 0.0)
}
```

6개의 통계를 하나의 쿼리로 계산한다. WAL 모드 덕분에 이런 집계 쿼리가 실행 중에도 새로운 데이터 삽입이 가능하다.

## WAL 모드 운영 고려사항

### 장점

1. **동시성**: 읽기와 쓰기가 서로 차단하지 않음
2. **성능**: 대부분의 경우 기본 모드보다 빠름
3. **안정성**: 쓰기 중단 시에도 데이터 무결성 보장

### 제약사항

1. **네트워크 파일시스템 불가**: 모든 프로세스가 같은 호스트에 있어야 함
2. **단일 쓰기**: 동시에 하나의 쓰기 트랜잭션만 가능
3. **WAL 파일 증가**: Checkpoint가 실행되지 않으면 WAL 파일이 계속 커짐

### Checkpoint 관리

장시간 실행되는 읽기 트랜잭션이 있으면 Checkpoint가 차단된다.

```kotlin
// 주기적으로 수동 Checkpoint 실행
@Scheduled(fixedDelay = 60000)
fun checkpoint() {
    try {
        connection.createStatement().use { stmt ->
            stmt.executeUpdate("PRAGMA wal_checkpoint(PASSIVE)")
        }
    } catch (e: Exception) {
        logger.warn { "Checkpoint failed: ${e.message}" }
    }
}
```

또는 읽기 쿼리에 타임아웃을 설정해서 "reader gap"을 만든다.

```kotlin
connection.createStatement().use { stmt ->
    stmt.queryTimeout = 30  // 30초 후 타임아웃
}
```

## WAL 모드의 기대 효과

WAL 모드를 활성화하면 다음과 같은 개선을 기대할 수 있다.

- **읽기/쓰기 동시성**: 기본 모드에서는 쓰기 시 읽기가 차단되지만, WAL 모드에서는 동시에 진행된다
- **쓰기 성능 향상**: 작은 트랜잭션이 많을 때 특히 효과적이다
- **지연시간 감소**: 락 경합이 줄어들어 P95/P99 지연시간이 개선된다

실제 성능은 워크로드, 하드웨어, 동시 연결 수에 따라 달라진다. SQLite 공식 문서에서는 일반적으로 읽기 동시성이 크게 향상된다고 설명한다.

## 정리

SQLite WAL 모드와 Repository 패턴을 조합하면 다음 이점을 얻는다.

1. **간단한 배포**: 별도 DB 서버 없이 단일 바이너리로 배포 가능
2. **높은 동시성**: 읽기와 쓰기가 서로 차단하지 않음
3. **타입 안전성**: QueryBuilder로 SQL Injection 방지
4. **유지보수성**: Repository 패턴으로 비즈니스 로직과 데이터 접근 분리

단일 서버 환경에서 분석 데이터를 저장해야 한다면, PostgreSQL 같은 무거운 DB 대신 SQLite WAL 모드를 고려해볼 만하다.

## 참고 자료

- [Write-Ahead Logging - SQLite](https://sqlite.org/wal.html)
- [How SQLite Scales Read Concurrency - Fly.io Blog](https://fly.io/blog/sqlite-internals-wal/)
- [WAL mode - High Performance SQLite](https://highperformancesqlite.com/watch/wal-mode)
- [Understanding WAL Mode in SQLite - Medium](https://mohit-bhalla.medium.com/understanding-wal-mode-in-sqlite-boosting-performance-in-sql-crud-operations-for-ios-5a8bd8be93d2)
