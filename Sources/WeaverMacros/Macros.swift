// Weaver/Sources/Weaver/Macros.swift

import Foundation
import Weaver

/// 의존성을 컨테이너에 등록하도록 선언하는 매크로입니다.
///
/// 이 매크로를 함수나 계산 프로퍼티에 붙이면, `@Registrar`가 이를 감지하여
/// 해당 의존성을 자동으로 `WeaverContainer`에 등록하는 코드를 생성합니다.
///
/// - Parameter scope: 의존성의 생명주기를 결정하는 스코프입니다. 기본값은 `.container` 입니다.
// ✅ FIX: 컴파일러가 생성될 이름을 예측하지 못하는 문제를 해결하기 위해 'arbitrary'를 사용합니다.
// 이는 컴파일러의 엄격한 이름 검증을 우회하여 매크로의 결과물을 신뢰하도록 만듭니다.
@attached(peer, names: arbitrary)
public macro Register(
    scope: Scope = .container
) = #externalMacro(
    module: "WeaverMacrosImpl",
    type: "RegisterMacro"
)

/// 여러 의존성 선언을 감싸서 하나의 `Module`로 구성하는 매크로입니다.
///
/// 이 매크로가 붙은 구조체는 자동으로 `Module` 프로토콜을 준수하게 되며,
/// 내부에 `@Register`로 선언된 모든 의존성을 등록하는 `configure` 메서드를 갖게 됩니다.
// ✅ FIX: Member 매크로에도 'arbitrary'를 적용하여 이름 관련 문제를 원천적으로 방지하고,
// 'Module' 프로토콜을 채택할 것임을 'conformances'로 명시합니다.
@attached(member, names: arbitrary)
@attached(extension, conformances: Module)
public macro Registrar() = #externalMacro(
    module: "WeaverMacrosImpl",
    type: "RegistrarMacro"
)
