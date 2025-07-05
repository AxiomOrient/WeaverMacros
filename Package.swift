// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "WeaverMacros",
    platforms: [
        .iOS(.v15),
        .watchOS(.v8),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "WeaverMacros",
            targets: ["WeaverMacros"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/AxiomOrient/Weaver.git", from: "0.0.2"),
        .package(url: "https://github.com/apple/swift-syntax.git", from: "601.0.1"),
    ],
    targets: [
        // 매크로를 사용하는 클라이언트 코드에 포함될 타겟 (선언부)
        // 사용자는 이 타겟을 import 합니다.
        .target(
            name: "WeaverMacros",
            dependencies: [
                "Weaver",
                "WeaverMacrosImpl"
            ]
        ),
        // 매크로 구현체 타겟 (컴파일러 플러그인)
        .macro(
            name: "WeaverMacrosImpl",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        ),
    ]
)
