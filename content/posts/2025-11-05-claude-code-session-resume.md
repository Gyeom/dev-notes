---
title: "Claude Code Session Resume로 토큰 30-40% 절감하기"
date: 2025-11-05
draft: false
tags: ["Claude Code", "AI", "Token Optimization", "Session Management", "Prompt Caching"]
categories: ["AI Development"]
summary: "Claude Code의 --resume 옵션과 세션 관리로 토큰 비용을 대폭 줄이는 방법. 실제 구현 코드와 함께 알아본다."
---

> 이 글은 [Claude Flow](https://github.com/Gyeom/claude-flow) 프로젝트를 개발하면서 정리한 내용이다. 전체 아키텍처는 [개발기](/dev-notes/posts/2024-12-22-claude-flow-development-story/)에서 확인할 수 있다.

## 왜 세션 관리가 중요한가

Claude Code로 개발할 때 매번 새 세션을 시작하면 같은 컨텍스트를 반복해서 전달하게 된다. 프로젝트 구조, 코딩 컨벤션, 이전 대화 내용을 매번 다시 입력하면 토큰 낭비가 심하다.

세션을 재개(resume)하면 이전 대화 히스토리와 컨텍스트를 그대로 유지하면서 작업을 이어갈 수 있다. 이를 통해 **토큰을 30-40% 절감**할 수 있다.

## Claude Code의 세션 재개 옵션

### 기본 사용법

```bash
# 가장 최근 대화 계속하기
claude -c
claude --continue

# 특정 세션 ID로 재개
claude -r abc123
claude --resume abc123

# 대화 목록에서 선택
claude --resume
```

세션을 재개하면 전체 메시지 히스토리가 복원되고, 이전 대화의 도구 사용 기록과 결과도 함께 보존된다.

### 자동화 환경에서 사용

스크립트나 CI/CD 파이프라인에서는 `--resume`에 세션 ID를 명시하는 것이 좋다. `--continue`는 비대화형 모드에서 새 세션을 만들 수 있기 때문이다.

```bash
# 비대화형 모드에서 세션 재개
claude --resume session-abc123 --print "다음 단계 진행해줘"
```

## 실제 구현: claude-flow 프로젝트

claude-flow 프로젝트는 Slack 봇으로 Claude Code를 래핑하여 팀 협업을 지원한다. 여기서 세션 관리가 핵심 기능이다.

### 세션 캐시 구조

ClaudeExecutor.kt에서 세션을 캐싱한다:

```kotlin
// Session 캐시: key = userId:threadTs, value = sessionId
private val sessionCache = ConcurrentHashMap<String, SessionInfo>()

// Session TTL: 30분
private val sessionTtlMs = 30 * 60 * 1000L

data class SessionInfo(
    val sessionId: String,
    val createdAt: Long = System.currentTimeMillis(),
    val lastUsedAt: Long = System.currentTimeMillis()
) {
    fun isExpired(ttlMs: Long): Boolean =
        System.currentTimeMillis() - lastUsedAt > ttlMs
}
```

각 사용자와 Slack 스레드 조합별로 세션을 유지한다. 30분 동안 활동이 없으면 세션이 만료된다.

### 세션 조회 및 갱신

유효한 세션을 조회하고 마지막 사용 시간을 갱신한다:

```kotlin
private fun getValidSession(key: String): SessionInfo? {
    val session = sessionCache[key] ?: return null
    if (session.isExpired(sessionTtlMs)) {
        sessionCache.remove(key)
        return null
    }
    // 마지막 사용 시간 갱신
    sessionCache[key] = session.copy(lastUsedAt = System.currentTimeMillis())
    return session
}
```

세션이 만료되지 않았으면 재사용하고, 만료되었으면 캐시에서 제거한다.

### CLI 인자 구성

세션이 있으면 `--resume` 플래그를 추가한다:

```kotlin
private fun buildArgs(request: ExecutionRequest, resumeSessionId: String? = null): List<String> {
    val config = request.config ?: defaultConfig
    val args = mutableListOf<String>()

    // Session 재개 (--resume 플래그)
    if (resumeSessionId != null) {
        args.addAll(listOf("--resume", resumeSessionId))
    } else {
        // 새 세션: 프롬프트 모드
        args.add("-p")
    }

    // 출력 형식 - stream-json으로 실시간 도구 로깅 지원
    val outputFormat = when (config.outputFormat) {
        OutputFormat.STREAM_JSON -> "stream-json"
        OutputFormat.STREAM -> "stream-json"
        else -> config.outputFormat.name.lowercase()
    }
    args.addAll(listOf("--output-format", outputFormat))

    // 모델 (새 세션일 때만)
    if (resumeSessionId == null) {
        args.addAll(listOf("--model", request.model ?: config.model))
    }

    // 프롬프트
    args.add(request.prompt)
    return args
}
```

세션을 재개할 때는 모델 옵션을 전달하지 않는다. 세션에 이미 모델 설정이 포함되어 있기 때문이다.

### 세션 ID 저장

Claude CLI 실행이 성공하면 세션 ID를 캐시에 저장한다:

```kotlin
// Session ID 저장 (성공 시)
if (result.status == ExecutionStatus.SUCCESS && result.sessionId != null && sessionKey != null) {
    sessionCache[sessionKey] = SessionInfo(result.sessionId)
    logManager.info(requestId, "Session cached: ${result.sessionId}")
}
```

다음 요청에서 이 세션 ID를 사용하여 대화를 이어간다.

### 만료된 세션 정리

주기적으로 만료된 세션을 제거한다:

```kotlin
fun cleanupExpiredSessions() {
    val expiredKeys = sessionCache.entries
        .filter { it.value.isExpired(sessionTtlMs) }
        .map { it.key }
    expiredKeys.forEach { sessionCache.remove(it) }
    if (expiredKeys.isNotEmpty()) {
        logger.info { "Cleaned up ${expiredKeys.size} expired sessions" }
    }
}
```

메모리 누수를 방지하고 캐시 크기를 적정 수준으로 유지한다.

## SessionManager: 대화 히스토리 관리

SessionManager.kt는 Slack 스레드 기반으로 세션을 관리한다:

```kotlin
class SessionManager(
    private val sessionTtlMinutes: Long = 60,  // 기본 1시간
    private val maxSessions: Int = 1000
) {
    private val sessions = ConcurrentHashMap<String, Session>()

    fun getOrCreate(
        threadId: String,
        channel: String,
        userId: String
    ): Session {
        cleanupExpired()
        return sessions.getOrPut(threadId) {
            val session = Session(
                id = threadId,
                channel = channel,
                userId = userId,
                createdAt = Instant.now(),
                lastActivityAt = Instant.now()
            )
            logger.info { "Created new session: $threadId" }
            session
        }.also {
            it.lastActivityAt = Instant.now()
        }
    }
}
```

### 대화 히스토리 추적

세션에 메시지를 추가하고 최근 50개만 유지한다:

```kotlin
fun addMessage(threadId: String, role: String, content: String) {
    sessions[threadId]?.let { session ->
        session.messages.add(
            SessionMessage(
                role = role,
                content = content,
                timestamp = Instant.now()
            )
        )
        session.lastActivityAt = Instant.now()

        // 메시지 수 제한 (최근 50개만 유지)
        while (session.messages.size > 50) {
            session.messages.removeAt(0)
        }
    }
}
```

오래된 메시지를 제거하여 메모리 사용을 제한한다.

### 컨텍스트 조회

최근 N개 메시지를 가져와서 컨텍스트로 사용한다:

```kotlin
fun getContext(threadId: String, maxMessages: Int = 10): List<SessionMessage> {
    return sessions[threadId]?.messages?.takeLast(maxMessages) ?: emptyList()
}
```

## 토큰 절감 효과

### 프롬프트 캐싱과의 시너지

Claude Code는 자동으로 프롬프트 캐싱을 활성화한다. 세션을 재개하면 이전에 분석한 코드베이스를 다시 처리하지 않고 캐시된 상태를 로드한다.

- **캐시 쓰기**: 기본 입력 토큰 가격의 125%
- **캐시 읽기**: 기본 입력 토큰 가격의 10%

세션을 재개하면 캐시 읽기로 대부분의 컨텍스트를 처리하므로 비용이 크게 줄어든다.

### 실제 절감률

- CLAUDE.md 최적화 + 세션 재개: **약 62% 토큰 절감** (세션당 1,300 토큰 절감)
- 시작 시 토큰: 약 800 토큰으로 감소
- 월간 비용: 팀 단위로 상당한 절감 효과

### 캐시 지속 시간

- 기본: 5분 (무료로 갱신)
- 옵션: 1시간 (추가 비용)

캐시는 사용할 때마다 무료로 갱신된다. 5분 안에 다시 요청하면 추가 비용 없이 캐시를 유지한다.

## 구현 시 고려사항

### TTL 설정

세션 TTL을 너무 길게 설정하면 메모리 사용량이 증가한다. 너무 짧게 설정하면 세션 재사용 효과가 줄어든다.

```kotlin
// 30분 TTL: 활발한 작업 중에는 유지, 휴식 후에는 정리
private val sessionTtlMs = 30 * 60 * 1000L

// SessionManager는 1시간 TTL 사용
private val sessionTtlMinutes: Long = 60
```

ClaudeExecutor는 30분, SessionManager는 1시간 TTL을 사용한다. 용도에 맞게 조정한다.

### 캐시 크기 제한

최대 세션 수를 설정하여 무한정 증가를 방지한다:

```kotlin
private val maxSessions: Int = 1000

// 최대 세션 수 초과 시 가장 오래된 세션 제거
if (sessions.size > maxSessions) {
    val toRemove = sessions.entries
        .sortedBy { it.value.lastActivityAt }
        .take(sessions.size - maxSessions)
    toRemove.forEach { (id, _) ->
        sessions.remove(id)
    }
}
```

### 세션 키 설계

사용자와 컨텍스트를 조합한 키를 사용한다:

```kotlin
private fun buildSessionKey(request: ExecutionRequest): String? {
    val userId = request.userId ?: return null
    val threadTs = request.threadTs ?: return null
    return "$userId:$threadTs"
}
```

Slack 봇이라면 `userId:threadTs`, 웹 앱이라면 `userId:projectId` 등으로 설계한다.

### 메시지 히스토리 제한

메시지를 무제한 저장하면 메모리가 부족해진다:

```kotlin
// 메시지 수 제한 (최근 50개만 유지)
while (session.messages.size > 50) {
    session.messages.removeAt(0)
}
```

Claude Code는 이미 자체적으로 대화 히스토리를 관리한다. SessionManager의 메시지는 앱 레벨 추적용이므로 제한을 둔다.

## 베스트 프랙티스

### CLAUDE.md 활용

세션 재개만으로는 부족하다. CLAUDE.md에 프로젝트 컨텍스트를 정리하면 시너지가 생긴다.

```markdown
# 프로젝트 개요
Slack 기반 Claude Code 봇

## 아키텍처
- ClaudeExecutor: CLI 실행 및 세션 관리
- SessionManager: 대화 히스토리 추적
- SlackHandler: Slack 이벤트 처리

## 코딩 컨벤션
- Kotlin 코루틴 사용
- 테스트는 Kotest BehaviorSpec
```

Claude는 세션 시작 시 CLAUDE.md를 자동으로 로드한다. 5,000 토큰 이하로 유지하는 것이 좋다.

### 세션 정리 전략

작업이 완료되면 세션을 명시적으로 종료한다:

```kotlin
fun close(threadId: String) {
    sessions.remove(threadId)?.let {
        logger.info { "Closed session: $threadId" }
    }
}
```

종료되지 않은 세션은 TTL 만료까지 메모리를 차지한다.

### 세션 요약 활용

Claude Code는 `--resume` 목록 표시를 위해 백그라운드에서 세션을 요약한다. 이 과정에서 소량의 토큰이 소비된다.

오래된 세션을 재개할 때 이전 에러 극복 방법을 물어보고 그 내용을 CLAUDE.md에 반영하면 다음 세션에서 같은 실수를 줄일 수 있다.

```bash
# 며칠 전 세션 재개
claude --resume old-session-123

# 질문
"이 세션에서 API 인증 에러를 어떻게 해결했어?"

# 답변을 CLAUDE.md에 추가
```

### Document & Clear 패턴

대규모 작업에서는 "Document & Clear" 패턴이 유용하다:

1. Claude에게 계획과 진행 상황을 .md 파일로 작성하게 한다
2. `/clear`로 세션을 초기화한다
3. 새 세션에서 .md를 읽고 작업을 계속한다

자동 compaction보다 이 패턴이 더 안정적이다.

## 결론

세션 재개는 토큰 절감의 핵심이다. claude-flow 프로젝트의 구현을 참고하면:

1. **세션 키 설계**: 사용자와 컨텍스트 조합
2. **TTL 관리**: 30분~1시간 적절히 설정
3. **캐시 정리**: 만료된 세션 주기적 제거
4. **메시지 제한**: 최근 N개만 유지

CLAUDE.md와 프롬프트 캐싱을 함께 활용하면 **30-40% 이상 토큰을 절감**할 수 있다.

## Sources

- [Claude Code Session Management | Steve Kinney](https://stevekinney.com/courses/ai-development/claude-code-session-management)
- [Claude Code CLI Cheatsheet | Shipyard](https://shipyard.build/blog/claude-code-cheat-sheet/)
- [Practical workflow for reducing token usage](https://gist.github.com/artemgetmann/74f28d2958b53baf50597b669d4bce43)
- [Manage costs effectively - Claude Code Docs](https://code.claude.com/docs/en/costs)
- [Prompt caching - Claude Docs](https://docs.claude.com/en/docs/build-with-claude/prompt-caching)
- [Supercharge your development with prompt caching | AWS](https://aws.amazon.com/blogs/machine-learning/supercharge-your-development-with-claude-code-and-amazon-bedrock-prompt-caching/)
