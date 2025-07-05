# 🕸️ WeaverMacros

**Weaver를 위한 강력한 매크로: Swift 의존성 주입(DI)의 보일러플레이트를 제거하세요.**

`WeaverMacros`는 [Weaver](https://github.com/AxiomOrient/Weaver) 프레임워크를 위한 매크로 라이브러리로, 의존성 등록 과정에서 발생하는 반복적인 코드를 획기적으로 줄여줍니다. `@Register`와 `@Module` 두 가지 매크로를 통해, 개발자는 더 이상 수동으로 `DependencyKey`를 정의하거나 등록 코드를 작성할 필요 없이, 비즈니스 로직에만 집중할 수 있습니다.

## ✨ 주요 특징

*   🚀 **코드량 최소화**: `@Register` 매크로 하나로 `DependencyKey` 정의와 `WeaverBuilder` 등록 로직을 자동으로 생성합니다.
*   🧠 **자동화된 모듈 구성**: `@Module` 매크로가 프로젝트 내의 모든 `@Register` 선언을 스캔하여 `configure` 메서드를 자동으로 구현해줍니다.
*   🛡️ **타입 안전성 유지**: 컴파일 타임에 코드를 생성하므로, `Weaver`의 강력한 타입 안전성을 그대로 유지합니다.
*   🧩 **유연한 설정**: `scope`, `name` 등 `Weaver`의 다양한 등록 옵션을 매크로 파라미터로 손쉽게 지정할 수 있습니다.
*    seamlessly **기존 프로젝트와 완벽 호환**: 기존 `Weaver` 설정과 점진적으로 함께 사용할 수 있습니다.

---

## 🏁 시작하기

### 전제 조건

이 라이브러리는 `Weaver` 프레임워크에 대한 의존성을 가지고 있습니다. 먼저 `Weaver`에 대한 이해가 필요합니다.

### 📦 설치

Swift Package Manager를 사용하여 `WeaverMacros`를 프로젝트에 추가합니다.

```swift
// Package.swift

dependencies: [
    .package(url: "https://github.com/AxiomOrient/Weaver.git", from: "1.0.0"),
    .package(url: "https://github.com/AxiomOrient/WeaverMacros.git", from: "0.0.1")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            "Weaver",
            "WeaverMacros"
        ]
    )
]
```

### 🌿 사용법: Before vs. After

`WeaverMacros`가 어떻게 코드를 단순화하는지 비교해 보세요.

#### **Before: 표준 Weaver 방식**

기존 방식에서는 서비스, 키, 모듈을 각각 수동으로 정의해야 했습니다.

```swift
// 1. 서비스 정의
protocol MyService: Sendable {
    func doSomething() -> String
}
final class MyServiceImpl: MyService {
    func doSomething() -> String { "Hello, Weaver!" }
}

// 2. 의존성 키 정의
struct MyServiceKey: DependencyKey {
    static var defaultValue: MyService = MyServiceImpl()
}

// 3. 모듈에서 수동 등록
struct AppModules: Module {
    func configure(_ builder: WeaverBuilder) async {
        builder.register(MyServiceKey.self, scope: .container) { resolver in
            return MyServiceImpl()
        }
    }
}
```

#### **After: WeaverMacros 방식 ✨**

`@Register`와 `@Module`을 사용하면 모든 것이 간결해집니다.

```swift
import Weaver
import WeaverMacros

// 1. 서비스 정의 (동일)
protocol MyService: Sendable {
    func doSomething() -> String
}

// 2. @Register 매크로로 구현체에 바로 등록
// - MyService.self에 대한 DependencyKey 자동 생성
// - WeaverBuilder에 등록하는 로직 자동 생성
@Register(MyService.self, scope: .container)
final class MyServiceImpl: MyService {
    // 의존성이 없는 경우, init()을 명시할 필요가 없습니다.
    func doSomething() -> String { "Hello, Weaver!" }
}

// 3. @Module 매크로로 모듈 자동화
// - 프로젝트 내의 모든 @Register를 찾아 configure 메서드를 자동으로 구현합니다.
@Module
struct AppModules: Module {
    // 이제 configure 메서드를 직접 작성할 필요가 없습니다!
}
```

### 💉 의존성 주입 및 사용

의존성을 사용하는 코드는 기존 `Weaver`와 완전히 동일합니다.

```swift
import SwiftUI
import Weaver

struct ContentView: View {
    // 자동 생성된 키를 사용하여 의존성을 주입합니다.
    // WeaverMacros는 'MyServiceKey'를 내부적으로 생성하고 사용합니다.
    @Inject(MyService.self) private var myService

    var body: some View {
        Text(myService.doSomething())
    }
}
```

---

## 🔬 고급 예제

### 의존성을 가지는 서비스 등록

`@Register` 매크로는 클래스의 `init` 메서드를 분석하여 필요한 의존성을 자동으로 해결(resolve)하는 코드를 생성합니다.

```swift
// AuthService
protocol AuthService: Sendable { /* ... */ }
@Register(AuthService.self)
final class AuthServiceImpl: AuthService { /* ... */ }

// UserService는 AuthService에 의존합니다.
protocol UserService: Sendable {
    func getCurrentUserName() -> String
}

@Register(UserService.self)
final class UserServiceImpl: UserService {
    private let authService: AuthService

    // 매크로가 이 init을 분석하여 authService를 자동으로 주입합니다.
    init(authService: AuthService) {
        self.authService = authService
    }

    func getCurrentUserName() -> String { /* ... */ }
}
```

#### **위 코드가 생성하는 등록 로직 (예시)**

```swift
// WeaverMacros가 생성하는 코드
builder.register(UserServiceKey.self) { resolver in
    let authService = try await resolver.resolve(AuthServiceKey.self)
    return UserServiceImpl(authService: authService)
}
```

### 이름으로 의존성 구분 (Named Dependencies)

동일한 프로토콜에 대해 여러 구현체가 있을 경우, `name` 파라미터로 구분할 수 있습니다.

```swift
protocol ImageCache: Sendable { /* ... */ }

@Register(ImageCache.self, name: "local")
final class LocalImageCache: ImageCache { /* ... */ }

@Register(ImageCache.self, name: "remote")
final class RemoteImageCache: ImageCache { /* ... */ }

// 주입 시점
struct MyView: View {
    @Inject(ImageCache.self, name: "local") private var localCache
    @Inject(ImageCache.self, name: "remote") private var remoteCache
    // ...
}
```

### 커스텀 `DependencyKey` 사용

특별한 `defaultValue`가 필요하거나 직접 키를 제어하고 싶을 때, `key` 파라미터로 커스텀 키를 지정할 수 있습니다.

```swift
// 1. 커스텀 키 정의
struct CustomServiceKey: DependencyKey {
    static var defaultValue: MyService = MockMyService()
}

// 2. @Register에 커스텀 키 전달
@Register(key: CustomServiceKey.self, scope: .container)
final class MyServiceImpl: MyService {
    // ...
}

// 3. 주입 시 커스텀 키 사용
struct MyView: View {
    @Inject(CustomServiceKey.self) private var myService
    // ...
}
```

## 📄 라이선스

`WeaverMacros`는 MIT 라이선스에 따라 배포됩니다.
