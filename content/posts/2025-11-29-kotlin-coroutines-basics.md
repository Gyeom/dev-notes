---
title: "Kotlin Coroutines 기초 가이드"
date: 2025-11-29
draft: true
tags: ["Kotlin", "Coroutines", "비동기", "동시성"]
categories: ["Programming"]
summary: "코틀린 코루틴의 기본 개념과 사용법을 정리한다"
---

## 코루틴이란

코루틴은 비동기 프로그래밍을 간결하게 작성할 수 있는 코틀린의 경량 스레드다. 콜백이나 RxJava 없이도 비동기 코드를 동기 코드처럼 작성할 수 있다.

## 기본 사용법

### 첫 번째 코루틴

```kotlin
import kotlinx.coroutines.*

fun main() = runBlocking {
    launch {
        delay(1000L)
        println("World!")
    }
    println("Hello")
}
```

`runBlocking`은 코루틴 스코프를 만들고, `launch`는 새 코루틴을 시작한다. `delay`는 코루틴을 일시 중단하지만 스레드는 차단하지 않는다.

### suspend 함수

코루틴 안에서 다른 suspend 함수를 호출할 수 있다.

```kotlin
suspend fun doSomething(): String {
    delay(1000L)
    return "Result"
}

fun main() = runBlocking {
    val result = doSomething()
    println(result)
}
```

`suspend` 키워드는 함수가 일시 중단될 수 있음을 표시한다.

## 코루틴 빌더

### launch

결과를 반환하지 않고 백그라운드에서 작업을 실행한다.

```kotlin
val job = launch {
    // 작업 수행
}
job.cancel() // 취소 가능
```

### async

결과를 반환하는 코루틴을 시작한다.

```kotlin
val deferred = async {
    computeValue()
}
val result = deferred.await()
```

### runBlocking

현재 스레드를 차단하면서 코루틴을 실행한다. 주로 메인 함수나 테스트에서 사용한다.

## Coroutine Scope

모든 코루틴은 특정 스코프 안에서 실행된다.

```kotlin
coroutineScope {
    launch { /* ... */ }
    async { /* ... */ }
}
```

스코프가 끝나면 모든 자식 코루틴이 완료될 때까지 대기한다.

### GlobalScope

애플리케이션 전체 생명주기를 갖는 코루틴을 시작한다. 주의해서 사용해야 한다.

```kotlin
GlobalScope.launch {
    // 전역 코루틴
}
```

## Dispatcher

코루틴이 실행될 스레드를 지정한다.

```kotlin
launch(Dispatchers.Default) {
    // CPU 집약적 작업
}

launch(Dispatchers.IO) {
    // I/O 작업
}

launch(Dispatchers.Main) {
    // UI 작업 (Android)
}
```

- `Dispatchers.Default`: CPU 작업용
- `Dispatchers.IO`: I/O 작업용 (파일, 네트워크)
- `Dispatchers.Main`: UI 작업용
- `Dispatchers.Unconfined`: 특정 스레드에 제한되지 않음

## 구조화된 동시성

부모 코루틴이 취소되면 모든 자식 코루틴도 취소된다.

```kotlin
val job = launch {
    val child = launch {
        delay(1000L)
        println("Child")
    }
    delay(500L)
    println("Parent")
}

job.cancelAndJoin()
// Parent만 출력되고 Child는 취소됨
```

## 예외 처리

### try-catch

일반 예외 처리와 동일하게 사용한다.

```kotlin
launch {
    try {
        riskyOperation()
    } catch (e: Exception) {
        println("Error: ${e.message}")
    }
}
```

### CoroutineExceptionHandler

코루틴 스코프 레벨에서 예외를 처리한다.

```kotlin
val handler = CoroutineExceptionHandler { _, exception ->
    println("Caught $exception")
}

launch(handler) {
    throw Exception("Error!")
}
```

## 실전 예제

### 병렬 작업

```kotlin
suspend fun fetchUser(): User = withContext(Dispatchers.IO) {
    // API 호출
}

suspend fun fetchPosts(): List<Post> = withContext(Dispatchers.IO) {
    // API 호출
}

fun loadData() = runBlocking {
    val user = async { fetchUser() }
    val posts = async { fetchPosts() }

    display(user.await(), posts.await())
}
```

### 타임아웃

```kotlin
withTimeout(1000L) {
    longRunningTask()
}
```

1초 내에 완료되지 않으면 `TimeoutCancellationException`이 발생한다.

## 정리

코틀린 코루틴은 비동기 코드를 직관적으로 작성할 수 있게 한다. `launch`, `async` 같은 빌더로 코루틴을 시작하고, `suspend` 함수로 일시 중단 로직을 작성한다. Dispatcher로 실행 스레드를 제어하고, 구조화된 동시성으로 안전하게 관리한다.

더 깊이 있는 내용은 [공식 문서](https://kotlinlang.org/docs/coroutines-overview.html)를 참고한다.
