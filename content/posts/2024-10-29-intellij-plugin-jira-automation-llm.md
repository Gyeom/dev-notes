---
title: "IntelliJ 플러그인으로 Git Diff → Jira 티켓 자동화하기"
date: 2024-10-29
draft: false
tags: ["IntelliJ", "Plugin", "Jira", "LLM", "OpenAI", "Claude", "Kotlin", "자동화"]
categories: ["개발도구"]
summary: "코드 변경사항을 AI가 분석해서 Jira 티켓을 자동 생성하는 IntelliJ 플러그인을 만들었다. 프롬프트 엔지니어링부터 IDE 플러그인 개발까지."
---

긴급 핫픽스 상황에서 코드 수정은 5분이면 끝나는데, Jira 티켓 작성에 10분이 걸렸다. Jira 웹 접속, 프로젝트 선택, 제목/설명 작성, 담당자 설정... 코드 변경 내용을 이미 알고 있는데 왜 또 타이핑해야 하지?

Git diff에 모든 정보가 있다. 이걸 AI가 읽고 티켓을 만들어주면 된다.

**자동화 목표**: IDE에서 코드 변경 → 원클릭 → Jira 티켓 생성

---

## 아키텍처

```mermaid
flowchart LR
    subgraph IDE ["IntelliJ IDEA"]
        Git4Idea["Git4Idea<br/>(Diff 추출)"]
        UI["Tool Window<br/>Dialog"]
    end

    subgraph Services ["서비스 레이어"]
        Diff["DiffAnalysisService"]
        AI["AIService"]
        Jira["JiraApiService"]
    end

    subgraph External ["외부 API"]
        OpenAI["OpenAI API"]
        Claude["Anthropic API"]
        JiraCloud["Jira Cloud API"]
    end

    Git4Idea --> Diff
    Diff --> AI
    AI --> OpenAI
    AI --> Claude
    AI --> UI
    UI --> Jira
    Jira --> JiraCloud

    style IDE fill:#e3f2fd
    style Services fill:#fff3e0
    style External fill:#e8f5e9
```

핵심은 세 개의 서비스다.

| 서비스 | 역할 |
|--------|------|
| **DiffAnalysisService** | Git4Idea로 uncommitted changes 추출 |
| **AIService** | OpenAI/Claude API로 티켓 내용 생성 |
| **JiraApiService** | Jira Cloud REST API로 이슈 생성 |

---

## Git Diff 분석

IntelliJ의 `Git4Idea` 플러그인은 VCS 기능을 제공한다. 이걸 활용해서 변경사항을 추출한다.

```kotlin
@Service(Service.Level.PROJECT)
class DiffAnalysisService(private val project: Project) {

    data class DiffAnalysisResult(
        val filesChanged: Int,
        val linesAdded: Int,
        val linesDeleted: Int,
        val fileList: List<String>,
        val diffContent: String,
        val branchName: String?
    )

    fun analyzeUncommittedChanges(): DiffAnalysisResult? {
        val changeListManager = ChangeListManager.getInstance(project)
        val changes = changeListManager.allChanges

        if (changes.isEmpty()) return null

        return analyzeChanges(changes.toList(), getCurrentBranch())
    }

    fun analyzeChanges(changes: List<Change>, branchName: String?): DiffAnalysisResult {
        var linesAdded = 0
        var linesDeleted = 0
        val fileList = mutableListOf<String>()
        val diffContentBuilder = StringBuilder()

        for (change in changes) {
            val filePath = getFilePath(change)
            fileList.add(filePath)

            val beforeContent = change.beforeRevision?.content ?: ""
            val afterContent = change.afterRevision?.content ?: ""

            val diff = computeDiff(beforeContent, afterContent)
            linesAdded += diff.added
            linesDeleted += diff.deleted

            diffContentBuilder.append("File: $filePath\n")
            diffContentBuilder.append(diff.content)
            diffContentBuilder.append("\n---\n\n")
        }

        return DiffAnalysisResult(
            filesChanged = fileList.size,
            linesAdded = linesAdded,
            linesDeleted = linesDeleted,
            fileList = fileList,
            diffContent = diffContentBuilder.toString(),
            branchName = branchName
        )
    }
}
```

`ChangeListManager`가 현재 uncommitted changes를 반환하고, 각 `Change`에서 before/after 내용을 비교한다.

---

## 프롬프트 엔지니어링

AI에게 좋은 티켓을 생성하게 하려면 프롬프트가 중요하다.

```kotlin
const val DEFAULT_PROMPT_TEMPLATE = """Given the following code changes, generate a Jira ticket in {{LANGUAGE}}.

{{DIFF_SUMMARY}}

Detailed Changes:
{{DIFF_CONTENT}}

Please generate:
1. A concise Jira ticket title (max 100 characters, in {{LANGUAGE}})
   - Should clearly describe what was changed
   - Format: Brief description
   - Example (Korean): 사용자 인증 로직 구현
   - Example (English): Implement user authentication

2. A detailed description (in {{LANGUAGE}}) with the following sections:
   - **What was changed**: Specific changes made to the code
   - **Why it was changed**: Reasoning and motivation behind the changes
   - **Impact**: Potential effects on the system, dependencies, or users
   - **Technical details**: Any important implementation notes

Format your response EXACTLY as JSON:
{
  "title": "your title here",
  "description": "## What was changed\n...\n\n## Why it was changed\n...\n\n## Impact\n...\n\n## Technical details\n..."
}

Important:
- Use {{LANGUAGE}} for all text
- Keep the title under 100 characters
- Use markdown formatting in the description
- Be specific and concise"""
```

### 프롬프트 설계 포인트

1. **구조화된 출력**: JSON 형식을 명시해서 파싱을 쉽게 한다
2. **언어 지원**: `{{LANGUAGE}}` 변수로 8개 언어 지원
3. **섹션 가이드**: What/Why/Impact/Technical 구조를 제시
4. **예시 제공**: 한국어/영어 예시로 기대 형식을 보여줌
5. **제약 조건**: 제목 100자 제한, 마크다운 사용 등

### Diff 크기 제한

토큰 오버플로우를 방지하기 위해 diff를 잘라낸다.

```kotlin
private fun buildPrompt(
    diffSummary: String,
    diffContent: String,
    language: OutputLanguage
): String {
    // 3000자로 제한
    val truncatedDiff = if (diffContent.length > 3000) {
        diffContent.substring(0, 3000) + "\n... (truncated)"
    } else {
        diffContent
    }

    return DEFAULT_PROMPT_TEMPLATE
        .replace("{{LANGUAGE}}", language.displayName)
        .replace("{{DIFF_SUMMARY}}", diffSummary)
        .replace("{{DIFF_CONTENT}}", truncatedDiff)
}
```

---

## AI 프로바이더 통합

OpenAI와 Anthropic 두 가지 프로바이더를 지원한다.

```kotlin
fun generateTicketFromDiff(
    diffSummary: String,
    diffContent: String,
    language: OutputLanguage
): Result<GeneratedTicket> {
    val state = settings.state

    if (state.aiApiKey.isEmpty()) {
        return Result.failure(Exception("AI API key not configured"))
    }

    return when (state.aiProvider.lowercase()) {
        "openai" -> generateWithOpenAI(diffSummary, diffContent, language)
        "anthropic" -> generateWithAnthropic(diffSummary, diffContent, language)
        else -> Result.failure(Exception("Unsupported AI provider"))
    }
}
```

### OpenAI 호출

```kotlin
private fun generateWithOpenAIPrompt(prompt: String): Result<GeneratedTicket> {
    val requestJson = JsonObject().apply {
        addProperty("model", state.aiModel)
        add("messages", gson.toJsonTree(listOf(
            mapOf("role" to "system", "content" to "You are a helpful assistant that creates Jira tickets from code changes."),
            mapOf("role" to "user", "content" to prompt)
        )))
        addProperty("temperature", 0.7)
        addProperty("max_tokens", 1500)
    }

    val request = Request.Builder()
        .url("https://api.openai.com/v1/chat/completions")
        .addHeader("Authorization", "Bearer ${state.aiApiKey}")
        .addHeader("Content-Type", "application/json")
        .post(requestJson.toString().toRequestBody("application/json".toMediaType()))
        .build()

    return client.newCall(request).execute().use { response ->
        if (response.isSuccessful) {
            val content = parseOpenAIResponse(response.body?.string())
            parseGeneratedTicket(content)
        } else {
            Result.failure(Exception("OpenAI API error: ${response.code}"))
        }
    }
}
```

### Anthropic 호출

```kotlin
private fun generateWithAnthropicPrompt(prompt: String): Result<GeneratedTicket> {
    val requestJson = JsonObject().apply {
        addProperty("model", state.aiModel)
        addProperty("max_tokens", 1500)
        add("messages", gson.toJsonTree(listOf(
            mapOf("role" to "user", "content" to prompt)
        )))
    }

    val request = Request.Builder()
        .url("https://api.anthropic.com/v1/messages")
        .addHeader("x-api-key", state.aiApiKey)
        .addHeader("anthropic-version", "2023-06-01")
        .addHeader("Content-Type", "application/json")
        .post(requestJson.toString().toRequestBody("application/json".toMediaType()))
        .build()

    // ... 응답 처리
}
```

API 형식이 다르므로 각각 처리한다. Anthropic은 `x-api-key` 헤더와 `anthropic-version`이 필요하다.

---

## 응답 파싱

AI 응답에서 JSON을 추출하는 로직이다.

```kotlin
private fun parseGeneratedTicket(content: String): Result<GeneratedTicket> {
    return try {
        // JSON 부분만 추출
        val jsonStart = content.indexOf("{")
        val jsonEnd = content.lastIndexOf("}") + 1

        if (jsonStart == -1 || jsonEnd <= jsonStart) {
            // Fallback: raw content 사용
            return Result.success(
                GeneratedTicket(title = "Code Changes", description = content)
            )
        }

        val jsonString = content.substring(jsonStart, jsonEnd)
        val jsonObject = gson.fromJson(jsonString, JsonObject::class.java)

        val title = jsonObject.get("title")?.asString ?: "Code Changes"
        val description = jsonObject.get("description")?.asString ?: content

        Result.success(GeneratedTicket(title, description))
    } catch (e: Exception) {
        // 파싱 실패 시 raw content 반환
        Result.success(GeneratedTicket(title = "Code Changes", description = content))
    }
}
```

AI가 가끔 JSON 앞뒤에 설명을 붙이는 경우가 있어서 `{...}` 부분만 추출한다.

---

## Jira API 연동

### Atlassian Document Format (ADF)

Jira Cloud API v3는 마크다운 대신 ADF를 사용한다.

```kotlin
private fun convertMarkdownToJiraFormat(markdown: String): JiraDescription {
    val lines = markdown.split("\n")
    val content = mutableListOf<JiraContent>()

    for (line in lines) {
        when {
            line.startsWith("## ") -> {
                content.add(JiraContent(
                    type = "heading",
                    attrs = mapOf("level" to 2),
                    content = listOf(JiraTextContent(type = "text", text = line.substring(3).trim()))
                ))
            }
            line.startsWith("- ") || line.startsWith("* ") -> {
                content.add(JiraContent(
                    type = "paragraph",
                    content = listOf(JiraTextContent(type = "text", text = "• ${line.substring(2).trim()}"))
                ))
            }
            else -> {
                // 일반 텍스트
                content.add(JiraContent(
                    type = "paragraph",
                    content = listOf(JiraTextContent(type = "text", text = line))
                ))
            }
        }
    }

    return JiraDescription(content = content)
}
```

### 이슈 생성

```kotlin
fun createIssue(
    title: String,
    description: String,
    projectKey: String,
    issueType: String,
    priority: String? = null,
    assigneeAccountId: String? = null,
    epicKey: String? = null,
    sprintId: Long? = null
): Result<JiraIssueResponse> {
    val descriptionContent = convertMarkdownToJiraFormat(description)

    val fields = JiraIssueFields(
        project = JiraProject(key = projectKey),
        summary = title,
        description = descriptionContent,
        issuetype = JiraIssueType(name = issueType),
        assignee = assigneeAccountId?.let { JiraAssignee(accountId = it) },
        priority = priority?.let { JiraPriority(id = it) },
        customfield_10014 = epicKey,  // Epic Link
        customfield_10020 = sprintId  // Sprint
    )

    val url = "${jiraUrl}/rest/api/3/issue"
    val credentials = Credentials.basic(username, apiToken)

    val request = Request.Builder()
        .url(url)
        .addHeader("Authorization", credentials)
        .addHeader("Content-Type", "application/json")
        .post(gson.toJson(JiraIssueRequest(fields = fields)).toRequestBody())
        .build()

    // ... 응답 처리
}
```

`customfield_10014`, `customfield_10020` 같은 커스텀 필드는 Jira 인스턴스마다 다를 수 있다.

---

## 사용 워크플로우

```
1. 코드 변경
2. Tool Window에서 "Create Ticket from Changes" 클릭
3. AI가 diff 분석해서 제목/설명 생성
4. 다이얼로그에서 확인/수정
5. Project, Issue Type, Priority 등 선택
6. Create 클릭 → Jira 티켓 생성 완료
```

### Tool Window

![Jira Ticket Creator Tool Window](/dev-notes/images/posts/jira-automation-main.png)

오른쪽 Tool Window에서 내 티켓 목록을 확인하고, "Create from Code Changes" 버튼으로 새 티켓을 생성할 수 있다.

### Settings

![Settings](/dev-notes/images/posts/jira-automation-settings.png)

Jira 연결 정보와 AI 프로바이더(OpenAI/Anthropic)를 설정한다. 출력 언어도 선택 가능하다.

### 티켓 생성 다이얼로그

![Create Jira Ticket](/dev-notes/images/posts/jira-automation-create.png)

AI가 생성한 제목과 설명을 확인하고 수정할 수 있다. "Regenerate" 버튼으로 다시 생성하거나, 직접 편집 후 생성한다.

### 생성 예시

코드 변경:
```kotlin
// UserService.kt
+ fun authenticate(email: String, password: String): AuthResult {
+     val user = userRepository.findByEmail(email)
+         ?: return AuthResult.Failure("User not found")
+
+     if (!passwordEncoder.matches(password, user.passwordHash)) {
+         return AuthResult.Failure("Invalid password")
+     }
+
+     return AuthResult.Success(jwtService.generateToken(user))
+ }
```

AI 생성 결과:
```
Title: 사용자 인증 로직 구현

## What was changed
- UserService에 authenticate 메서드 추가
- 이메일로 사용자 조회 후 비밀번호 검증
- JWT 토큰 생성 및 반환

## Why it was changed
- 로그인 기능 구현을 위한 인증 로직 필요

## Impact
- 기존 API에 영향 없음
- 새로운 /auth/login 엔드포인트에서 사용 예정

## Technical details
- BCrypt로 비밀번호 검증
- 인증 실패 시 AuthResult.Failure 반환
```

---

## IntelliJ Plugin 개발 팁

### 프로젝트 설정

`build.gradle.kts`:
```kotlin
plugins {
    id("org.jetbrains.kotlin.jvm") version "2.1.0"
    id("org.jetbrains.intellij.platform") version "2.0.0"
}

intellijPlatform {
    pluginConfiguration {
        id = "com.github.gyeom.jiraautomation"
        name = "Jira Automation"
        version = "0.0.1"
    }
}

dependencies {
    intellijPlatform {
        intellijIdeaCommunity("2024.3")
        bundledPlugin("Git4Idea")  // Git 기능 사용
    }

    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.google.code.gson:gson:2.10.1")
}
```

### Service 등록

`plugin.xml`:
```xml
<extensions defaultExtensionNs="com.intellij">
    <projectService
        serviceImplementation="com.github.gyeom.jiraautomation.services.AIService"/>
    <projectService
        serviceImplementation="com.github.gyeom.jiraautomation.services.DiffAnalysisService"/>
    <projectService
        serviceImplementation="com.github.gyeom.jiraautomation.services.JiraApiService"/>

    <toolWindow
        factoryClass="com.github.gyeom.jiraautomation.toolWindow.JiraToolWindowFactory"
        id="Jira Creator"
        anchor="right"/>

    <projectConfigurable
        instance="com.github.gyeom.jiraautomation.settings.JiraSettingsConfigurable"
        displayName="Jira Ticket Creator"
        parentId="tools"/>
</extensions>
```

### Settings 저장

```kotlin
@Service(Service.Level.PROJECT)
@State(
    name = "JiraSettingsState",
    storages = [Storage("JiraTicketCreator.xml")]
)
class JiraSettingsState : PersistentStateComponent<JiraSettingsState.State> {

    data class State(
        var jiraUrl: String = "",
        var jiraUsername: String = "",
        var jiraApiToken: String = "",
        var aiProvider: String = "openai",
        var aiApiKey: String = "",
        var aiModel: String = "gpt-4-turbo",
        var defaultLanguage: String = "ko"
    )

    private var state = State()

    override fun getState(): State = state
    override fun loadState(state: State) { this.state = state }
}
```

`PersistentStateComponent`를 구현하면 설정이 자동으로 저장/복원된다.

---

## 한계와 개선 방향

### 현재 한계

| 항목 | 설명 |
|------|------|
| Git 전용 | SVN, Mercurial 미지원 |
| Uncommitted만 | 커밋 비교 기능 없음 |
| Diff 크기 | 3000자 제한 (토큰 문제) |
| Jira Cloud만 | Server/Data Center API 차이 |
| ADF 변환 | 복잡한 마크다운 제한적 |

### 개선 가능 사항

**Phase 2**
- 브랜치 비교 모드 (feature vs main)
- 커밋 히스토리 분석 (여러 커밋 통합)
- 자동 라벨/컴포넌트 태깅
- 스토리 포인트 예측

**Phase 3**
- Diff 캐싱으로 성능 개선
- AI 응답 스트리밍
- 백그라운드 태스크로 비동기 처리

**Phase 4**
- GitHub Issues, Linear 등 다른 이슈 트래커 지원
- 커스텀 프롬프트 템플릿 편집기
- 팀 설정 공유 기능

---

## 정리

IntelliJ 플러그인으로 Git Diff → AI 분석 → Jira 티켓 생성 파이프라인을 만들었다.

**배운 점**
- IntelliJ Platform SDK로 IDE 기능 확장하기
- Git4Idea로 VCS 정보 접근하기
- LLM API 통합 시 프롬프트 설계의 중요성
- Jira ADF 포맷 변환 처리

**실용성**
- 반복적인 티켓 작성 시간 단축
- 일관된 티켓 포맷 유지
- 코드 변경과 티켓의 연결성 강화

## 참고 자료

- [IntelliJ Platform Plugin SDK](https://plugins.jetbrains.com/docs/intellij/welcome.html)
- [Jira Cloud REST API v3](https://developer.atlassian.com/cloud/jira/platform/rest/v3/)
- [OpenAI API Documentation](https://platform.openai.com/docs/api-reference)
- [Anthropic Claude API](https://docs.anthropic.com/claude/reference)
- [GitHub Repository](https://github.com/Gyeom/jira-automation)
