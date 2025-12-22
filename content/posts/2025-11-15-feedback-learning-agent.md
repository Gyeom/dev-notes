---
title: "피드백 학습으로 에이전트 추천 정확도 높이기"
date: 2025-11-15
draft: false
tags: ["Machine Learning", "Feedback Learning", "Agent Routing", "Kotlin", "Claude Flow"]
categories: ["Architecture"]
summary: "사용자 피드백을 실시간으로 학습하여 에이전트 라우팅 정확도를 개선하는 방법"
---

> 이 글은 [Claude Flow](https://github.com/Gyeom/claude-flow) 프로젝트를 개발하면서 정리한 내용이다. 전체 아키텍처는 [개발기](/dev-notes/posts/2024-12-22-claude-flow-development-story/)에서 확인할 수 있다.

## 문제 정의

다중 에이전트 시스템에서 사용자 질문에 가장 적합한 에이전트를 선택하는 것은 중요하다. 키워드 매칭이나 정규식 패턴만으로는 한계가 있다. 같은 질문이라도 사용자마다 선호하는 에이전트가 다를 수 있고, 시간이 지나면서 에이전트 성능도 변한다.

Claude Flow 프로젝트에서는 이 문제를 **피드백 학습(Feedback Learning)**으로 해결한다. Slack 리액션(thumbsup/thumbsdown)을 수집하여 에이전트별 성공률을 계산하고, 이를 라우팅 스코어에 반영한다.

## 피드백 수집 메커니즘

### Slack 리액션 분류

모든 리액션이 피드백은 아니다. 리액션을 3가지 카테고리로 분류한다.

```kotlin
fun categorizeReaction(reaction: String): String = when (reaction) {
    "thumbsup", "thumbsdown", "+1", "-1", "heart", "tada" -> "feedback"
    "jira", "ticket", "bug", "gitlab", "github" -> "trigger"
    "wrench", "hammer", "one", "two", "three", "four", "five",
    "a", "b", "c", "d", "white_check_mark", "x" -> "action"
    else -> "other"
}
```

- **feedback**: 응답 품질 평가 (학습에 사용)
- **trigger**: 외부 시스템 연동 트리거 (Jira 티켓 생성 등)
- **action**: 선택지 응답 (Claude의 제안 중 선택)

### Verified Feedback

모든 사용자의 피드백을 동일하게 취급하면 노이즈가 섞인다. 실제 질문한 사람(requester)의 피드백만 **verified**로 처리한다.

```kotlin
fun createVerified(
    id: String,
    executionId: String,
    userId: String,
    reaction: String,
    requesterId: String  // 원래 요청한 사용자 ID
): FeedbackRecord {
    val isVerified = userId == requesterId
    return FeedbackRecord(
        id = id,
        executionId = executionId,
        userId = userId,
        reaction = reaction,
        category = categorizeReaction(reaction),
        isVerified = isVerified,
        verifiedAt = if (isVerified) Instant.now() else null
    )
}
```

타인이 남긴 리액션도 저장하지만, 성공률 계산 시에는 제외한다. 이를 통해 **신호 대비 노이즈 비율(Signal-to-Noise Ratio)**을 높인다.

## 학습 파이프라인

### 1. 피드백 기록

실행(execution) 완료 후 사용자가 리액션을 남기면, 피드백을 저장하고 메모리 캐시를 갱신한다.

```kotlin
fun recordFeedback(
    executionId: String,
    userId: String,
    isPositive: Boolean
): Boolean {
    return try {
        val execution = executionRepository.findById(executionId) ?: return false
        val agentId = execution.agentId

        // 벡터 DB 피드백 점수 업데이트
        val score = if (isPositive) 1.0 else -1.0
        conversationVectorService?.updateFeedbackScore(executionId, score)

        // 사용자 선호도 캐시 업데이트
        val preferences = preferenceCache.getOrPut(userId) {
            UserAgentPreferences(userId = userId)
        }
        preferences.recordFeedback(agentId, isPositive)
        preferences.lastUpdated = Instant.now()

        true
    } catch (e: Exception) {
        logger.error(e) { "Failed to record feedback" }
        false
    }
}
```

메모리 캐시를 사용하는 이유:
- **빠른 조회**: DB 쿼리 없이 즉시 선호도 확인
- **동시성 안전**: `ConcurrentHashMap` 사용
- **자동 만료**: 30분 후 캐시 만료

### 2. 성공률 계산

에이전트별로 긍정/부정 피드백 수를 집계하여 성공률을 계산한다.

```kotlin
class UserAgentPreferences(
    val userId: String,
    var lastUpdated: Instant = Instant.now()
) {
    // positive count, total count
    private val agentFeedback = ConcurrentHashMap<String, Pair<Int, Int>>()

    fun recordFeedback(agentId: String, isPositive: Boolean) {
        val current = agentFeedback.getOrDefault(agentId, Pair(0, 0))
        agentFeedback[agentId] = Pair(
            current.first + if (isPositive) 1 else 0,
            current.second + 1
        )
        lastUpdated = Instant.now()
    }

    fun calculatePreferenceScores(): Map<String, Float> {
        return agentFeedback.mapValues { (_, stats) ->
            if (stats.second > 0) {
                stats.first.toFloat() / stats.second
            } else {
                0.5f  // 기본값
            }
        }
    }
}
```

성공률은 0.0 ~ 1.0 범위다. 피드백이 없으면 중립값 0.5를 사용한다.

### 3. 라우팅 스코어 조정

기존 라우팅 스코어에 피드백 기반 조정 팩터를 곱한다.

```kotlin
fun adjustRoutingScore(
    userId: String,
    agentId: String,
    baseScore: Float,
    queryEmbedding: FloatArray? = null
): Float {
    val preferences = getAgentPreferences(userId)
    val preferenceScore = preferences[agentId] ?: 0.5f

    // 조정 알고리즘:
    // - 성공률 > 0.7: boost = 1.0 + (success_rate - 0.5) × 0.2
    // - 성공률 < 0.3: penalty = 1.0 - (0.5 - success_rate) × 0.3
    val adjustmentFactor = when {
        preferenceScore > 0.7f -> 1.0f + (preferenceScore - 0.5f) * 0.2f
        preferenceScore < 0.3f -> 1.0f - (0.5f - preferenceScore) * 0.3f
        else -> 1.0f
    }

    val adjustedScore = (baseScore * adjustmentFactor).coerceIn(0f, 1f)

    logger.debug {
        "Adjusted routing score for agent $agentId: " +
        "$baseScore -> $adjustedScore (preference: $preferenceScore)"
    }

    return adjustedScore
}
```

**조정 공식 해석**:
- 성공률 70% 이상: 최대 +4% 부스트 (0.7일 때 +4%, 1.0일 때 +10%)
- 성공률 30% 미만: 최대 -6% 페널티 (0.3일 때 -6%, 0.0일 때 -15%)
- 중간 범위: 조정 없음 (1.0배)

이 공식은 극단적 변화를 방지하면서도 충분한 피드백이 쌓인 경우 유의미한 영향을 준다.

### 4. 유사 쿼리 기반 추천

과거에 유사한 질문에서 높은 피드백을 받은 에이전트를 추천한다.

```kotlin
fun recommendAgentFromSimilar(
    query: String,
    userId: String?,
    topK: Int = 5
): AgentRecommendation? {
    if (conversationVectorService == null) return null

    // 유사 대화 검색
    val similar = conversationVectorService.findSimilarConversations(
        query = query,
        userId = userId,
        topK = topK * 2,  // 더 많이 검색하여 필터링
        minScore = 0.7f   // 높은 유사도만
    )

    if (similar.isEmpty()) return null

    // 피드백 기반 집계
    val agentScores = mutableMapOf<String, AgentScoreAccumulator>()

    for (conv in similar) {
        val feedback = feedbackRepository.findByExecutionId(conv.executionId)
        val positive = feedback.count { FeedbackRecord.isPositiveReaction(it.reaction) }
        val negative = feedback.count { FeedbackRecord.isNegativeReaction(it.reaction) }

        agentScores.getOrPut(conv.agentId) { AgentScoreAccumulator() }.also {
            it.addSample(conv.score, positive, negative)
        }
    }

    // 최고 점수 에이전트 선택
    val best = agentScores.entries
        .filter { it.value.sampleCount >= 2 }  // 최소 2개 샘플
        .maxByOrNull { it.value.combinedScore }
        ?: return null

    return AgentRecommendation(
        agentId = best.key,
        confidence = best.value.combinedScore,
        sampleCount = best.value.sampleCount,
        successRate = best.value.successRate,
        reason = "유사 질문 ${best.value.sampleCount}개 분석 결과"
    )
}
```

**점수 계산**:
```kotlin
val combinedScore: Float
    get() {
        val avgSimilarity = if (sampleCount > 0) totalSimilarity / sampleCount else 0f
        return avgSimilarity * 0.3f + successRate * 0.7f
    }
```

유사도 30%, 성공률 70%로 가중 평균한다. 벡터 유사도보다 실제 사용자 만족도를 더 중시한다.

## 라우팅 파이프라인 통합

`AgentRouter`는 다단계 파이프라인으로 에이전트를 선택한다.

```kotlin
fun route(message: String, userId: String? = null): AgentMatch {
    val normalizedMessage = message.lowercase()
    val enabledAgents = agents.filter { it.enabled }

    // 0. 피드백 학습 기반 추천 (유사 쿼리 분석)
    if (userId != null && feedbackLearningService != null) {
        feedbackLearningMatch(message, userId, enabledAgents)?.let {
            return it
        }
    }

    // 1. 키워드 매칭 (0.95 confidence)
    keywordMatch(normalizedMessage, enabledAgents)?.let { match ->
        val adjustedMatch = adjustMatchWithFeedback(match, userId)
        return adjustedMatch
    }

    // 2. 정규식 패턴 매칭 (0.85 confidence)
    patternMatch(normalizedMessage, enabledAgents)?.let { match ->
        val adjustedMatch = adjustMatchWithFeedback(match, userId)
        return adjustedMatch
    }

    // 3. 시맨틱 검색 (벡터 유사도)
    semanticRouter?.classify(message, enabledAgents)?.let { match ->
        val adjustedMatch = adjustMatchWithFeedback(match, userId)
        return adjustedMatch
    }

    // 4. 기본 에이전트로 폴백
    return AgentMatch(agent = defaultAgent, confidence = 0.5)
}
```

**우선순위 전략**:
1. 피드백 학습: 신뢰도 0.8 이상이면 최우선 (과거 유사 쿼리 기반)
2. 키워드 매칭: 빠르고 정확 (피드백으로 조정)
3. 정규식 패턴: 복잡한 패턴 (피드백으로 조정)
4. 시맨틱 검색: 벡터 유사도 (피드백으로 조정)
5. 폴백: 기본 에이전트

## ConcurrentHashMap 사용 이유

멀티스레드 환경에서 동시성 안전을 보장하기 위해 `ConcurrentHashMap`을 사용한다.

```kotlin
private val preferenceCache = ConcurrentHashMap<String, UserAgentPreferences>()

class UserAgentPreferences(...) {
    private val agentFeedback = ConcurrentHashMap<String, Pair<Int, Int>>()
}
```

**이유**:
1. **스레드 안전**: 여러 요청이 동시에 캐시를 업데이트해도 데이터 손실 없음
2. **락 프리 읽기**: `get()` 연산이 락 없이 수행되어 빠름
3. **세그먼트 락**: 전체 맵을 잠그지 않고 세그먼트만 잠궈 동시성 향상

일반 `HashMap`은 동기화되지 않아 race condition이 발생할 수 있고, `Collections.synchronizedMap()`은 전체 맵을 잠궈 성능이 떨어진다.

## 피드백 루프 문제와 대응

추천 시스템에서 피드백 루프는 잘 알려진 문제다. 시스템이 특정 에이전트를 자주 추천하면 그 에이전트의 피드백이 많아지고, 다시 더 많이 추천되는 악순환이 발생한다.

**대응 전략**:

1. **조정 팩터 제한**: 최대 ±15% 조정으로 극단적 변화 방지
2. **최소 샘플 요구**: 유사 쿼리 추천 시 최소 2개 샘플 요구
3. **신뢰도 임계값**: 피드백 학습 추천은 0.8 이상만 사용
4. **캐시 만료**: 30분 후 캐시 만료로 최신 데이터 반영
5. **Verified Feedback**: 실제 요청자의 피드백만 학습에 사용

이런 메커니즘이 없으면 인기 편향(popularity bias)이 심화되고, 소수 에이전트가 독점하게 된다.

## 온라인 학습의 이점

이 시스템은 전형적인 **온라인 학습(Online Learning)** 패턴이다. 배치 학습과 달리 실시간으로 학습한다.

**장점**:
- **빠른 적응**: 새로운 피드백이 즉시 반영됨
- **메모리 효율**: 전체 데이터를 메모리에 올리지 않음
- **지속적 개선**: 사용할수록 정확도 향상

**단점**:
- **노이즈 민감**: 잘못된 피드백의 영향이 즉시 나타남
- **안정성**: 모델이 안정되기까지 시간 필요
- **피드백 루프**: 부정 피드백 루프 가능성

Claude Flow는 **하이브리드 접근**을 사용한다. 키워드/패턴 매칭으로 안정성을 확보하고, 피드백 학습으로 정확도를 개선한다.

## 실전 적용 예시

### 시나리오 1: 버그 수정 요청

```
사용자: "로그인 API 에러 고쳐줘"
```

1. 키워드 매칭: "에러", "고쳐" → bug-fixer (confidence: 0.95)
2. 피드백 조정: 이 사용자가 bug-fixer에 80% 성공률 → 0.95 × 1.06 = 1.0
3. 최종 선택: bug-fixer

### 시나리오 2: 유사 쿼리 기반 추천

```
사용자: "결제 모듈 테스트 코드 짜줘"
```

1. 유사 쿼리 검색: "테스트 코드 작성해줘" (유사도 0.82)
2. 과거 피드백: test-writer 에이전트가 thumbsup 3개
3. 추천 신뢰도: 0.82 × 0.3 + 1.0 × 0.7 = 0.946
4. 최종 선택: test-writer (피드백 학습 추천)

### 시나리오 3: 성능 저하 에이전트 패널티

```
사용자: "코드 리뷰해줘"
```

1. 키워드 매칭: "리뷰" → code-reviewer (confidence: 0.95)
2. 피드백 조정: 최근 thumbsdown 많음 (25% 성공률) → 0.95 × 0.925 = 0.879
3. 대안 검색: refactor 에이전트가 유사 쿼리에서 높은 피드백
4. 최종 선택: refactor (대안 추천)

## 성능 모니터링

학습 통계를 조회하여 시스템 상태를 모니터링한다.

```kotlin
fun getLearningStats(userId: String? = null): LearningStats {
    val cached = if (userId != null) {
        listOfNotNull(preferenceCache[userId])
    } else {
        preferenceCache.values.toList()
    }

    val totalUsers = cached.size
    val totalFeedback = cached.sumOf { it.totalFeedback }
    val positiveRate = if (totalFeedback > 0) {
        cached.sumOf { it.positiveCount }.toDouble() / totalFeedback
    } else 0.0

    return LearningStats(
        totalUsers = totalUsers,
        totalFeedback = totalFeedback,
        positiveRate = positiveRate,
        cachedPreferences = cached.size,
        lastUpdated = cached.maxOfOrNull { it.lastUpdated }?.toString()
    )
}
```

**모니터링 지표**:
- 총 사용자 수
- 총 피드백 수
- 긍정 피드백 비율 (만족도)
- 캐시된 선호도 수
- 마지막 업데이트 시간

긍정 피드백 비율이 떨어지면 조정 공식이나 임계값을 재조정한다.

## 결론

피드백 학습은 규칙 기반 라우팅의 한계를 보완한다. 키워드 매칭이 빠르고 예측 가능하다면, 피드백 학습은 사용자별 맞춤화와 지속적 개선을 제공한다.

**핵심 원칙**:
1. **Verified Feedback**: 신호 대비 노이즈 비율 최적화
2. **점진적 조정**: 극단적 변화 방지 (±15% 제한)
3. **하이브리드 접근**: 규칙 기반 + 학습 기반 결합
4. **실시간 학습**: 메모리 캐시로 즉각 반영
5. **피드백 루프 완화**: 최소 샘플, 신뢰도 임계값 설정

이 방식은 RLHF(Reinforcement Learning from Human Feedback)와 유사하지만, 훨씬 단순하다. 모델 재학습 없이 간단한 통계 계산만으로 실시간 개선이 가능하다.

## 참고 자료

- [Navigating the Feedback Loop in Recommender Systems](https://dl.acm.org/doi/10.1145/3604915.3610246) - ACM RecSys 2023 컨퍼런스 논문
- [RLHF 101: Reinforcement Learning from Human Feedback](https://blog.ml.cmu.edu/2025/06/01/rlhf-101-a-technical-tutorial-on-reinforcement-learning-from-human-feedback/) - CMU Machine Learning Blog
- [Feedback Loop and Bias Amplification in Recommender Systems](https://arxiv.org/pdf/2007.13019) - ACM CIKM 2020 논문
- [Toward Harnessing User Feedback For Machine Learning](https://www.researchgate.net/publication/221608163_Toward_Harnessing_User_Feedback_For_Machine_Learning) - ResearchGate 논문
