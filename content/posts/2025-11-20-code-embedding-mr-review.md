---
title: "코드베이스 임베딩으로 MR 리뷰 컨텍스트 자동 제공"
date: 2025-11-20
draft: false
tags: ["RAG", "Vector-Search", "Code-Embedding", "Qdrant", "MR-Review", "AI"]
categories: ["Backend"]
summary: "코드를 의미 단위로 청킹하고 벡터화하여 MR 리뷰 시 관련 코드를 자동으로 검색하는 RAG 시스템 구현"
---

> 이 글은 [Claude Flow](https://github.com/Gyeom/claude-flow) 프로젝트를 개발하면서 정리한 내용이다. 전체 아키텍처는 [개발기](/dev-notes/posts/2024-12-22-claude-flow-development-story/)에서 확인할 수 있다.

## 문제 상황

MR 리뷰를 할 때 변경된 코드만 보면 전체 맥락을 파악하기 어렵다. 리뷰어는 관련 코드를 직접 찾아가며 확인해야 한다. 이 과정을 자동화할 수 있을까?

Claude-Flow 프로젝트에서는 코드베이스를 임베딩하고 MR 변경사항과 관련된 코드를 자동으로 주입하는 RAG 시스템을 구현했다.

## 코드 청킹 전략

코드는 일반 텍스트와 다르게 함수, 클래스 등 명확한 구조를 가진다. 이를 활용한 언어별 청킹 전략이 핵심이다.

### 언어별 패턴 인식

**Kotlin/Java**
```kotlin
// 클래스, 함수, 프로퍼티 단위로 분할
val patterns = listOf(
    Regex("""^\s*(class|interface|object|enum)\s+\w+"""),
    Regex("""^\s*(fun|override fun|suspend fun)\s+\w+"""),
    Regex("""^\s*(val|var)\s+\w+\s*:""")
)
```

**TypeScript/JavaScript**
```kotlin
val patterns = listOf(
    Regex("""^\s*(export\s+)?(async\s+)?function\s+\w+"""),
    Regex("""^\s*(export\s+)?(class|interface)\s+\w+"""),
    Regex("""^\s*(export\s+)?const\s+\w+\s*=""")
)
```

**Python**
```kotlin
val patterns = listOf(
    Regex("""^class\s+\w+"""),
    Regex("""^def\s+\w+"""),
    Regex("""^async\s+def\s+\w+""")
)
```

### 중괄호 균형 기반 청킹

단순히 패턴만 인식하면 중첩된 블록을 제대로 처리할 수 없다. 중괄호 카운팅으로 완전한 블록을 추출한다.

```kotlin
var braceCount = 0

for ((index, line) in lines.withIndex()) {
    val isNewBlock = patterns.any { it.containsMatchIn(line) } && braceCount == 0

    if (isNewBlock && currentChunkLines.isNotEmpty()) {
        // 이전 청크 저장 (braceCount == 0일 때만 분할)
        chunks.add(createChunk(currentChunkLines))
        currentChunkLines = mutableListOf()
    }

    currentChunkLines.add(line)
    braceCount += line.count { it == '{' } - line.count { it == '}' }
}
```

`braceCount == 0`일 때만 새 블록으로 인식한다. 중첩된 클래스나 함수 내부에서는 분할하지 않는다.

### 청크 크기 제어

```kotlin
class CodeChunker(
    private val maxChunkSize: Int = 1500,    // 최대 크기
    private val minChunkSize: Int = 100,     // 최소 크기 (너무 작은 청크 제거)
    private val overlapSize: Int = 100       // 향후 컨텍스트 보존용
)
```

- **maxChunkSize**: 임베딩 모델 컨텍스트 제한 고려 (보통 512~2048 토큰)
- **minChunkSize**: 의미 없는 작은 코드 조각 필터링
- **overlapSize**: 청크 간 컨텍스트 보존 (현재 미사용, 향후 확장 가능)

2025년 RAG 베스트 프랙티스는 400-512 토큰에 10-20% 오버랩을 권장한다.

### 설정 파일 처리

YAML, JSON 등 설정 파일은 전체를 하나의 청크로 처리한다.

```kotlin
private fun chunkConfigFile(content: String, filePath: String): List<CodeChunk> {
    return if (content.length <= maxChunkSize) {
        listOf(createChunk(
            content = content,
            chunkType = "config"
        ))
    } else {
        chunkGeneric(content, filePath)  // 크기 초과 시 일반 청킹
    }
}
```

설정 파일은 구조가 중요하므로 분할하지 않는 것이 좋다.

## 벡터화와 인덱싱

### Ollama 기반 임베딩

```kotlin
class EmbeddingService(
    private val model: String = "qwen3-embedding:0.6b"  // 1024차원
) {
    fun embed(text: String): FloatArray? {
        val requestBody = mapOf(
            "model" to model,
            "prompt" to text
        )

        val response = httpClient.send(
            HttpRequest.newBuilder()
                .uri(URI.create("$ollamaUrl/api/embeddings"))
                .POST(HttpRequest.BodyPublishers.ofString(
                    objectMapper.writeValueAsString(requestBody)
                ))
                .build(),
            HttpResponse.BodyHandlers.ofString()
        )

        val result: Map<String, Any> = objectMapper.readValue(response.body())
        return result["embedding"] as? List<Number>
            ?.map { it.toFloat() }
            ?.toFloatArray()
    }
}
```

**qwen3-embedding:0.6b** 모델 사용 이유:
- MTEB Multilingual 1위, Code 1위
- 1024차원 벡터 (코드 의미 포착에 충분)
- 100+ 언어 지원 (한국어 주석 처리)
- 로컬 실행 가능 (API 비용 없음)

### 임베딩 텍스트 구성

단순히 코드만 임베딩하지 않고 메타데이터를 포함한다.

```kotlin
val textToEmbed = """
    File: ${chunk.filePath}
    Type: ${chunk.chunkType}
    ${chunk.content}
""".trimIndent()
```

파일 경로와 청크 타입(class, function, config 등)을 포함하면 검색 정확도가 높아진다. "UserService의 save 함수" 같은 쿼리에 더 잘 매칭된다.

### Qdrant 인덱싱

```kotlin
val payload = mapOf(
    "project_id" to projectId,
    "file_path" to chunk.filePath,
    "start_line" to chunk.startLine,
    "end_line" to chunk.endLine,
    "language" to chunk.language,
    "chunk_type" to chunk.chunkType,
    "content_preview" to chunk.contentPreview,
    "indexed_at" to Instant.now().toString()
)

val requestBody = mapOf(
    "points" to listOf(
        mapOf(
            "id" to pointId,
            "vector" to embedding.toList(),
            "payload" to payload
        )
    )
)
```

Qdrant는 벡터와 함께 메타데이터(payload)를 저장한다. 검색 시 필터링과 결과 표시에 활용한다.

**인덱스 생성**
```kotlin
listOf(
    "project_id" to "keyword",
    "file_path" to "text",
    "language" to "keyword",
    "chunk_type" to "keyword"
).forEach { (field, schema) ->
    createIndex(field, schema)
}
```

프로젝트 ID, 언어, 청크 타입으로 필터링 가능하다.

## MR 리뷰 시 컨텍스트 주입

### 전체 흐름

```kotlin
fun reviewMergeRequestWithRag(project: String, mrId: Int): PluginResult {
    // 1. MR 정보 및 변경사항 가져오기
    val mrInfo = getMergeRequestDetails(project, mrId)
    val changes = getMergeRequestChanges(project, mrId)

    // 2. Diff 분석
    val allDiffs = changes.map { change ->
        "${change["old_path"]} -> ${change["new_path"]}\n${change["diff"]}"
    }.joinToString("\n\n")

    // 3. 관련 코드베이스 검색 (RAG)
    val relatedCode = mutableListOf<CodeChunk>()
    for (change in changes.take(5)) {
        val filePath = change["new_path"] as? String ?: continue
        val fileContext = codeKnowledgeService.findRelevantCode(
            query = "file: $filePath code changes",
            projectId = project,
            topK = 3,
            minScore = 0.5f
        )
        relatedCode.addAll(fileContext)
    }

    // 4. 리뷰 가이드라인 생성
    val guidelines = codeKnowledgeService.findReviewGuidelines(allDiffs, project)

    // 5. 리뷰 프롬프트 구성
    return buildReviewResult(mrInfo, changes, relatedCode, guidelines)
}
```

### 벡터 검색

```kotlin
fun findRelevantCode(
    query: String,
    projectId: String? = null,
    topK: Int = 5,
    minScore: Float = 0.6f
): List<CodeChunk> {
    val queryEmbedding = embeddingService.embed(query) ?: return emptyList()

    val requestBody = buildMap {
        put("vector", queryEmbedding.toList())
        put("limit", topK)
        put("score_threshold", minScore)
        put("with_payload", true)

        // 프로젝트 필터
        projectId?.let {
            put("filter", mapOf(
                "must" to listOf(
                    mapOf("key" to "project_id", "match" to mapOf("value" to it))
                )
            ))
        }
    }

    val response = httpClient.send(
        HttpRequest.newBuilder()
            .uri(URI.create("$qdrantUrl/collections/$collectionName/points/search"))
            .POST(HttpRequest.BodyPublishers.ofString(
                objectMapper.writeValueAsString(requestBody)
            ))
            .build(),
        HttpResponse.BodyHandlers.ofString()
    )

    return parseCodeSearchResults(response.body())
}
```

Qdrant의 코사인 유사도 검색을 사용한다. `minScore`로 유사도 임계값을 설정해 관련 없는 코드를 필터링한다.

### 리뷰 가이드라인 자동 생성

Diff에서 보안, 성능 패턴을 휴리스틱 기반으로 탐지한다.

```kotlin
// 보안 관련 패턴 체크
val securityPatterns = listOf(
    "password" to "하드코딩된 비밀번호 주의",
    "secret" to "비밀 정보 노출 주의",
    "token" to "토큰 노출 주의",
    "api.key" to "API 키 노출 주의"
)

for ((pattern, message) in securityPatterns) {
    if (diff.lowercase().contains(pattern)) {
        guidelines.add(ReviewGuideline(
            rule = message,
            category = "security",
            severity = "error"
        ))
    }
}
```

단순하지만 실용적이다. 향후 LLM 기반 분석으로 확장할 수 있다.

### Claude에게 전달할 프롬프트

```kotlin
fun generateReviewPrompt(
    mrInfo: Map<String, Any>,
    changes: List<Map<String, Any>>,
    guidelines: List<ReviewGuideline>,
    relatedCode: List<CodeChunk>
): String {
    return buildString {
        appendLine("## MR 리뷰 요청")
        appendLine("- 제목: ${mrInfo["title"]}")
        appendLine("- 브랜치: ${mrInfo["source_branch"]} → ${mrInfo["target_branch"]}")

        if (guidelines.isNotEmpty()) {
            appendLine("## 자동 검출된 리뷰 포인트")
            guidelines.forEach { g ->
                val icon = when (g.severity) {
                    "error" -> "🚨"
                    "warning" -> "⚠️"
                    else -> "ℹ️"
                }
                appendLine("$icon [${g.category}] ${g.rule}")
            }
        }

        if (relatedCode.isNotEmpty()) {
            appendLine("## 관련 코드베이스 (RAG)")
            relatedCode.take(3).forEach { chunk ->
                appendLine("- ${chunk.filePath}:${chunk.startLine}-${chunk.endLine}")
                appendLine("  ${chunk.contentPreview.take(80)}...")
            }
        }

        appendLine("## 변경된 파일 목록")
        changes.forEach { change ->
            val status = when {
                change["new_file"] == true -> "[신규]"
                change["deleted_file"] == true -> "[삭제]"
                change["renamed_file"] == true -> "[이름변경]"
                else -> "[수정]"
            }
            appendLine("$status ${change["new_path"]}")
        }
    }
}
```

Claude는 이 프롬프트를 받아 관련 코드베이스와 가이드라인을 참고하여 리뷰한다.

## 프로젝트 인덱싱

GitLab API를 통해 프로젝트 전체를 인덱싱한다.

```kotlin
fun indexProjectToKnowledgeBase(project: String, branch: String): PluginResult {
    codeKnowledgeService.initCollection()

    val files = getProjectFileTree(project, branch)

    var filesProcessed = 0
    var chunksIndexed = 0

    for (file in files.take(100)) {  // 최대 100개 파일
        val path = file["path"] as? String ?: continue
        val ext = path.substringAfterLast(".", "")

        if (ext !in SUPPORTED_EXTENSIONS) continue

        val content = getFileContent(project, path, branch)
        if (content.isNotBlank()) {
            val chunks = codeKnowledgeService.indexRemoteFile(project, path, content)
            if (chunks > 0) {
                filesProcessed++
                chunksIndexed += chunks
            }
        }
    }

    return PluginResult(
        success = true,
        message = "프로젝트 인덱싱 완료: ${filesProcessed}개 파일, ${chunksIndexed}개 청크"
    )
}
```

**지원 확장자**
```kotlin
val SUPPORTED_EXTENSIONS = setOf(
    "kt", "java", "ts", "tsx", "js", "py", "go", "rs",
    "yaml", "yml", "json", "toml", "md", "sql"
)
```

**제외 디렉토리**
```kotlin
val IGNORED_DIRS = setOf(
    "node_modules", ".git", "build", "dist", "target",
    ".gradle", ".idea", "__pycache__"
)
```

## 실제 사용 예시

### 1. 프로젝트 인덱싱
```bash
/gitlab index-project my-project main
```

결과:
```
프로젝트 'my-project' 인덱싱 완료: 87개 파일, 342개 청크
```

### 2. MR 리뷰
```bash
/gitlab mr-review my-project 123
```

결과:
```
MR !123 리뷰가 완료되었습니다.
- 3개의 가이드라인
- 8개의 관련 코드 발견

🚨 [security] 하드코딩된 비밀번호 주의
⚠️ [performance] 루프 내 불필요한 연산 확인

관련 코드베이스:
- src/service/UserService.kt:15-42 (유사도: 0.78)
  class UserService(private val repository: UserRepository)
- src/repository/UserRepository.kt:8-25 (유사도: 0.72)
  interface UserRepository { fun findById(id: String): User? }
```

### 3. 통계 조회
```bash
/gitlab knowledge-stats my-project
```

결과:
```
프로젝트 'my-project': 342개 청크 인덱싱됨
마지막 업데이트: 2024-12-22T10:30:00Z
```

## 성능 고려사항

### 임베딩 캐시

```kotlin
class EmbeddingCache(
    private val maxSize: Int = 10000
) {
    private val cache = LRUCache<String, FloatArray>(maxSize)

    fun get(text: String): FloatArray? {
        return cache.get(text)
    }

    fun put(text: String, embedding: FloatArray) {
        cache.put(text, embedding)
    }
}
```

같은 텍스트를 반복 임베딩하지 않도록 캐싱한다. LRU 정책으로 메모리 사용량을 제한한다.

### 배치 인덱싱

```kotlin
fun indexRemoteFiles(projectId: String, files: Map<String, String>): Int {
    var totalChunks = 0
    for ((path, content) in files) {
        totalChunks += indexRemoteFile(projectId, path, content)
    }
    return totalChunks
}
```

여러 파일을 한 번에 인덱싱할 수 있다. 향후 벡터 배치 삽입으로 최적화 가능하다.

### 검색 최적화

- **topK 제한**: 너무 많은 결과는 오히려 노이즈
- **minScore 설정**: 유사도 0.5~0.6 이하는 관련 없는 코드
- **프로젝트 필터링**: 동일 프로젝트 내에서만 검색

## 향후 개선 방향

### 1. Late Chunking
현재는 청킹 후 임베딩하지만, Late Chunking은 전체 문서를 먼저 임베딩한 뒤 청킹한다. 문서 전체 컨텍스트를 보존하여 10-12% 정확도 향상이 가능하다.

### 2. 하이브리드 검색
벡터 검색과 키워드 검색을 결합한다. Qdrant는 Full-Text Search를 지원하므로 함수명, 클래스명 같은 정확한 매칭에 유용하다.

### 3. LLM 기반 가이드라인
현재는 간단한 패턴 매칭이지만, LLM으로 Diff를 분석하여 더 정교한 리뷰 포인트를 생성할 수 있다.

### 4. 재순위화(Re-ranking)
벡터 검색 결과를 추가 신호(파일 수정 날짜, 작성자, 참조 빈도)로 재정렬한다.

```kotlin
fun rerankResults(
    results: List<CodeChunk>,
    boostRecent: Boolean = true
): List<CodeChunk> {
    return results.map { chunk ->
        var adjustedScore = chunk.score

        // 최근 수정된 파일 가중치 증가
        if (boostRecent) {
            val hoursSince = Duration.between(
                chunk.lastModified,
                Instant.now()
            ).toHours()
            val recencyBoost = when {
                hoursSince < 24 -> 1.2f
                hoursSince < 168 -> 1.1f
                else -> 1.0f
            }
            adjustedScore *= recencyBoost
        }

        chunk.copy(score = adjustedScore)
    }.sortedByDescending { it.score }
}
```

## 결론

코드베이스 임베딩은 MR 리뷰뿐만 아니라 코드 검색, 중복 코드 탐지, 리팩토링 후보 발견 등 다양하게 활용할 수 있다. 핵심은 언어별 청킹 전략과 메타데이터 활용이다.

Qdrant와 Ollama를 사용하면 API 비용 없이 로컬에서 운영 가능하다. 프로덕션 환경에서는 OpenAI 임베딩 API나 클라우드 벡터 DB를 고려할 수 있다.

코드는 [GitHub](https://github.com/Gyeom/claude-flow)에서 확인할 수 있다.

## 참고 자료

- [Chunking Strategies for LLM Applications | Pinecone](https://www.pinecone.io/learn/chunking-strategies/)
- [Best Chunking Strategies for RAG in 2025](https://www.firecrawl.dev/blog/best-chunking-strategies-rag-2025)
- [Search Through Your Codebase - Qdrant](https://qdrant.tech/documentation/advanced-tutorials/code-search/)
- [Building a Semantic Code Search Agent with Qdrant](https://mihirinamdar.medium.com/building-a-semantic-code-search-agent-with-qdrant-a-modern-approach-to-code-metadata-indexing-ac3a53ded594)
