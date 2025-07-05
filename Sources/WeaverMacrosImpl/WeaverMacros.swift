// Weaver/Sources/WeaverMacros/WeaverMacros.swift

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct WeaverMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        RegisterMacro.self,
        RegistrarMacro.self,
    ]
}

// MARK: - @Register Macro
public struct RegisterMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let info = RegistrationInfo(declaration) else {
            throw WeaverMacroError.notAttachedToFunctionOrVariable
        }

        let keyName = "_\(info.name)Key"
        let keyStruct: DeclSyntax =
            """
            private struct \(raw: keyName): DependencyKey {
                static var defaultValue: \(raw: info.typeName) {
                    fatalError("'\(raw: info.typeName)'에 대한 의존성이 등록되지 않았습니다. 매크로로 등록된 의존성은 반드시 해결 가능해야 합니다.")
                }
            }
            """
        return [keyStruct]
    }
}

// MARK: - @Registrar Macro
public struct RegistrarMacro: ExtensionMacro, MemberMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {

        let registrationCalls = declaration.memberBlock.members
            .compactMap { member -> String? in
                guard let info = RegistrationInfo(member.decl) else { return nil }
                
                let scope = info.scope ?? ".container"
                let keyName = "_\(info.name)Key"
                let depsArrayString = info.dependencies.map { "\"\($0)\"" }.joined(separator: ", ")
                
                // async/throws 키워드에 따라 호출 구문을 동적으로 생성
                var callPrefix = ""
                if info.isThrows { callPrefix += "try " }
                if info.isAsync { callPrefix += "await " }

                let factoryCall = "\(callPrefix)self.\(info.name)\(info.factoryArgument)"
                
                return """
                await builder.register(
                    \(keyName).self,
                    scope: \(scope),
                    dependencies: [\(depsArrayString)]) { \(info.factoryParameter) in
                    \(factoryCall)
                }
                """
            }

        let configureMethod: DeclSyntax =
            """
            public func configure(_ builder: WeaverBuilder) async {
                \(raw: registrationCalls.joined(separator: "\n        "))
            }
            """
        return [configureMethod]
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        
        // 1. 사용자가 이미 ': Module'을 직접 작성했는지 확인
        if let inheritance = declaration.inheritanceClause {
            let hasModuleConformance = inheritance.inheritedTypes.contains { inheritedType in
                inheritedType.type.trimmedDescription == "Module"
            }
            if hasModuleConformance {
                return [] // 이미 Module을 채택하고 있으므로 확장을 추가하지 않음
            }
        }
        
        // 2. 다른 매크로에 의해 Module 채택이 이미 진행 중인지 확인
        if protocols.contains(where: { $0.trimmedDescription == "Module" }) {
            return []
        }
        
        let moduleExtension = try ExtensionDeclSyntax("extension \(type.trimmed): Module {}")
        return [moduleExtension]
    }
}

// MARK: - Helper Types & Logic

private class ResolveCallVisitor: SyntaxVisitor {
    var resolvedDependencies = [String]()

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let calledExpression = node.calledExpression.as(MemberAccessExprSyntax.self),
              calledExpression.declName.baseName.text == "resolve" else {
            return .visitChildren
        }
        
        guard let base = calledExpression.base else {
            return .visitChildren
        }
        
        // 문자열 변환 및 트림 처리를 Foundation 없이 수행
        let baseDescription = base.description
        let trimmedBase = trimWhitespace(baseDescription)
        
        guard trimmedBase == "resolver" || trimmedBase.hasSuffix("container") else {
            return .visitChildren
        }

        if let firstArgument = node.arguments.first?.expression.as(MemberAccessExprSyntax.self),
           firstArgument.declName.baseName.text == "self",
           let keyType = firstArgument.base?.as(DeclReferenceExprSyntax.self) {
            
            let keyTypeName = keyType.baseName.text
            resolvedDependencies.append(keyTypeName)
        }
        
        return .visitChildren
    }
}

// Foundation 없이 공백 제거 함수
private func trimWhitespace(_ string: String) -> String {
    var start = string.startIndex
    var end = string.endIndex
    
    // 앞쪽 공백 제거
    while start < end && (string[start] == " " || string[start] == "\t" || string[start] == "\n" || string[start] == "\r") {
        start = string.index(after: start)
    }
    
    // 뒤쪽 공백 제거
    while end > start {
        let prevIndex = string.index(before: end)
        if string[prevIndex] == " " || string[prevIndex] == "\t" || string[prevIndex] == "\n" || string[prevIndex] == "\r" {
            end = prevIndex
        } else {
            break
        }
    }
    
    return String(string[start..<end])
}

private enum WeaverMacroError: Error, CustomStringConvertible, Sendable {
    case notAttachedToFunctionOrVariable
    var description: String {
        "@Register 매크로는 함수 또는 계산 프로퍼티에만 붙일 수 있습니다."
    }
}

private struct RegistrationInfo {
    let name: String
    let typeName: String
    let scope: String?
    let factoryParameter: String
    let factoryArgument: String
    let dependencies: [String]
    
    let isAsync: Bool
    let isThrows: Bool

    init?(_ declaration: some DeclSyntaxProtocol) {
        let attributes: AttributeListSyntax?
        var isAsync = false
        var isThrows = false
        
        // --- 1. 선언 타입(함수/변수)에 따라 기본 정보 추출 ---
        if let funcDecl = declaration.as(FunctionDeclSyntax.self) {
            guard let returnType = funcDecl.signature.returnClause?.type.trimmedDescription else { return nil }
            attributes = funcDecl.attributes
            
            // 함수의 effect specifiers 확인
            if let effectSpecifiers = funcDecl.signature.effectSpecifiers {
                isAsync = effectSpecifiers.asyncSpecifier != nil
                isThrows = effectSpecifiers.throwsClause != nil
            }
            
            self.name = funcDecl.name.text
            self.typeName = returnType
            
            // 파라미터 처리 로직 개선
            let parameters = funcDecl.signature.parameterClause.parameters
            if parameters.isEmpty {
                self.factoryParameter = "_"
                self.factoryArgument = "()"
            } else {
                self.factoryParameter = "resolver"
                // 첫 번째 파라미터의 레이블을 정확히 파악
                let firstParam = parameters.first!
                let paramLabel = firstParam.firstName.text
                
                // 레이블이 있는 경우 "functionName(label: resolver)" 형태로 생성
                if paramLabel != "_" {
                    self.factoryArgument = "(\(paramLabel): resolver)"
                } else {
                    self.factoryArgument = "(resolver)"
                }
            }
            
        } else if let varDecl = declaration.as(VariableDeclSyntax.self),
                  let binding = varDecl.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  let type = binding.typeAnnotation?.type.trimmedDescription {
            
            // 계산 프로퍼티의 getter에서 effect specifiers를 찾습니다.
            if let accessorBlock = binding.accessorBlock,
               let getter = getFirstGetter(from: accessorBlock) {
                if let effectSpecifiers = getter.effectSpecifiers {
                    isAsync = effectSpecifiers.asyncSpecifier != nil
                    isThrows = effectSpecifiers.throwsClause != nil
                }
            }
            
            attributes = varDecl.attributes
            self.name = identifier
            self.typeName = type
            self.factoryParameter = "_"
            self.factoryArgument = ""
        } else {
            return nil
        }
        
        // --- 2. @Register 매크로 존재 여부 및 scope 인자 추출 ---
        guard let registerAttribute = attributes?.first(where: { $0.as(AttributeSyntax.self)?.isRegisterMacro == true })?.as(AttributeSyntax.self) else {
            return nil
        }
        self.scope = registerAttribute.scopeArgument

        // --- 3. async / throws 키워드 존재 여부 저장 ---
        self.isAsync = isAsync
        self.isThrows = isThrows
        
        // --- 4. 팩토리 본문을 분석하여 의존 관계 추출 ---
        let dependencyVisitor = ResolveCallVisitor()
        dependencyVisitor.walk(declaration)
        self.dependencies = dependencyVisitor.resolvedDependencies
    }
}

// AccessorBlockSyntax에서 첫 번째 getter를 찾는 헬퍼 함수
private func getFirstGetter(from accessorBlock: AccessorBlockSyntax) -> AccessorDeclSyntax? {
    switch accessorBlock.accessors {
    case .accessors(let accessorList):
        return accessorList.first { accessor in
            accessor.accessorSpecifier.tokenKind == .keyword(.get)
        }
    case .getter:
        // 단일 getter 표현식의 경우 effect specifiers는 없음
        return nil
    }
}

private extension AttributeSyntax {
    var isRegisterMacro: Bool {
        self.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Register"
    }
    
    var scopeArgument: String? {
        guard let labeledExpression = self.arguments?.as(LabeledExprListSyntax.self)?.first,
              labeledExpression.label?.text == "scope" else { return nil }
        return labeledExpression.expression.description
    }
}
