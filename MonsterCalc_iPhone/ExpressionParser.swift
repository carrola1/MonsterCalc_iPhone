import Foundation

enum ParserError: LocalizedError, Equatable {
    case unexpectedToken
    case unknownIdentifier(String)
    case invalidNumber
    case invalidString
    case invalidArguments(String)
    case typeMismatch(String)
    case unexpectedEnd

    var errorDescription: String? {
        switch self {
        case .unexpectedToken:
            return "Unexpected token"
        case let .unknownIdentifier(name):
            return "Unknown identifier: \(name)"
        case .invalidNumber:
            return "Invalid number"
        case .invalidString:
            return "Invalid string"
        case let .invalidArguments(message):
            return message
        case let .typeMismatch(message):
            return message
        case .unexpectedEnd:
            return "Unexpected end of expression"
        }
    }
}

enum Token: Equatable {
    case number(Double)
    case string(String)
    case identifier(String)
    case comma
    case leftParen
    case rightParen
    case plus
    case minus
    case star
    case slash
    case percent
    case power
    case pipe
    case ampersand
    case xorKeyword
    case tilde
    case shiftLeft
    case shiftRight
    case end
}

struct ExpressionParser {
    let text: String
    let context: EvaluationContext
    let functionProvider: (String, [CalculatorValue]) throws -> CalculatorValue

    private let tokens: [Token]
    private var index: Int = 0

    init(
        text: String,
        context: EvaluationContext,
        functionProvider: @escaping (String, [CalculatorValue]) throws -> CalculatorValue
    ) {
        self.text = text
        self.context = context
        self.functionProvider = functionProvider
        self.tokens = Tokenizer(text: text).tokenize()
    }

    mutating func parseAndEvaluate() throws -> CalculatorValue {
        let value = try parseExpression()
        guard currentToken == .end else {
            throw ParserError.unexpectedToken
        }
        return value
    }

    private mutating func parseExpression() throws -> CalculatorValue {
        try parseBitwiseOr()
    }

    private mutating func parseBitwiseOr() throws -> CalculatorValue {
        var value = try parseBitwiseXor()
        while currentToken == .pipe {
            advance()
            value = .number(Double(try requireInteger(value) | requireInteger(try parseBitwiseXor())))
        }
        return value
    }

    private mutating func parseBitwiseXor() throws -> CalculatorValue {
        var value = try parseBitwiseAnd()
        while currentToken == .xorKeyword {
            advance()
            value = .number(Double(try requireInteger(value) ^ requireInteger(try parseBitwiseAnd())))
        }
        return value
    }

    private mutating func parseBitwiseAnd() throws -> CalculatorValue {
        var value = try parseShift()
        while currentToken == .ampersand {
            advance()
            value = .number(Double(try requireInteger(value) & requireInteger(try parseShift())))
        }
        return value
    }

    private mutating func parseShift() throws -> CalculatorValue {
        var value = try parseAdditive()
        while true {
            switch currentToken {
            case .shiftLeft:
                advance()
                value = .number(Double(try requireInteger(value) << requireInteger(try parseAdditive())))
            case .shiftRight:
                advance()
                value = .number(Double(try requireInteger(value) >> requireInteger(try parseAdditive())))
            default:
                return value
            }
        }
    }

    private mutating func parseAdditive() throws -> CalculatorValue {
        var value = try parseMultiplicative()
        while true {
            switch currentToken {
            case .plus:
                advance()
                value = .number(try requireNumber(value) + requireNumber(try parseMultiplicative()))
            case .minus:
                advance()
                value = .number(try requireNumber(value) - requireNumber(try parseMultiplicative()))
            default:
                return value
            }
        }
    }

    private mutating func parseMultiplicative() throws -> CalculatorValue {
        var value = try parsePower()
        while true {
            switch currentToken {
            case .star:
                advance()
                value = .number(try requireNumber(value) * requireNumber(try parsePower()))
            case .slash:
                advance()
                value = .number(try requireNumber(value) / requireNumber(try parsePower()))
            default:
                return value
            }
        }
    }

    private mutating func parsePower() throws -> CalculatorValue {
        var value = try parsePercent()
        if currentToken == .power {
            advance()
            value = .number(pow(try requireNumber(value), try requireNumber(try parsePower())))
        }
        return value
    }

    private mutating func parsePercent() throws -> CalculatorValue {
        var value = try parseUnary()
        while currentToken == .percent {
            advance()
            value = .number(try requireNumber(value) / 100)
        }
        return value
    }

    private mutating func parseUnary() throws -> CalculatorValue {
        switch currentToken {
        case .plus:
            advance()
            return try parseUnary()
        case .minus:
            advance()
            return .number(-(try requireNumber(try parseUnary())))
        case .tilde:
            advance()
            return .number(Double(~(try requireInteger(try parseUnary()))))
        default:
            return try parsePrimary()
        }
    }

    private mutating func parsePrimary() throws -> CalculatorValue {
        switch currentToken {
        case let .number(value):
            advance()
            return .number(value)
        case let .string(value):
            advance()
            return .text(value)
        case let .identifier(name):
            advance()
            if currentToken == .leftParen {
                advance()
                let arguments = try parseFunctionArguments(for: name)
                guard currentToken == .rightParen else {
                    throw ParserError.unexpectedToken
                }
                advance()
                return try functionProvider(name, arguments)
            }
            return try resolveIdentifier(name)
        case .leftParen:
            advance()
            let value = try parseExpression()
            guard currentToken == .rightParen else {
                throw ParserError.unexpectedToken
            }
            advance()
            return value
        case .end:
            throw ParserError.unexpectedEnd
        default:
            throw ParserError.unexpectedToken
        }
    }

    private mutating func parseFunctionArguments(for functionName: String) throws -> [CalculatorValue] {
        if currentToken == .rightParen {
            return []
        }

        if functionName == "a2h" {
            let argument: CalculatorValue
            switch currentToken {
            case let .identifier(value):
                advance()
                argument = .text(value)
            case let .string(value):
                advance()
                argument = .text(value)
            default:
                argument = try parseExpression()
            }

            if currentToken == .comma {
                throw ParserError.invalidArguments("a2h expects a single text input")
            }
            return [argument]
        }

        var arguments: [CalculatorValue] = []
        while true {
            arguments.append(try parseExpression())
            if currentToken == .comma {
                advance()
                continue
            }
            break
        }
        return arguments
    }

    private func resolveIdentifier(_ name: String) throws -> CalculatorValue {
        if name == "pi" {
            return .number(Double.pi)
        }
        if name == "e" {
            return .number(M_E)
        }
        if name == "ans", let ans = context.ans {
            return ans
        }
        if let value = context.variables[name] {
            return value
        }
        throw ParserError.unknownIdentifier(name)
    }

    private func requireNumber(_ value: CalculatorValue) throws -> Double {
        guard case let .number(number) = value else {
            throw ParserError.typeMismatch("Expected numeric input")
        }
        return number
    }

    private func requireInteger(_ value: CalculatorValue) throws -> Int {
        Int(floor(try requireNumber(value)))
    }

    private var currentToken: Token {
        tokens[index]
    }

    private mutating func advance() {
        if index < tokens.count - 1 {
            index += 1
        }
    }
}

private struct Tokenizer {
    let text: String

    func tokenize() -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]

            if character.isWhitespace {
                index = text.index(after: index)
                continue
            }

            if character == "," {
                tokens.append(.comma)
                index = text.index(after: index)
                continue
            }

            if character == "(" {
                tokens.append(.leftParen)
                index = text.index(after: index)
                continue
            }

            if character == ")" {
                tokens.append(.rightParen)
                index = text.index(after: index)
                continue
            }

            if character == "+" {
                tokens.append(.plus)
                index = text.index(after: index)
                continue
            }

            if character == "-" {
                tokens.append(.minus)
                index = text.index(after: index)
                continue
            }

            if character == "/" {
                tokens.append(.slash)
                index = text.index(after: index)
                continue
            }

            if character == "%" {
                tokens.append(.percent)
                index = text.index(after: index)
                continue
            }

            if character == "|" {
                tokens.append(.pipe)
                index = text.index(after: index)
                continue
            }

            if character == "&" {
                tokens.append(.ampersand)
                index = text.index(after: index)
                continue
            }

            if character == "~" {
                tokens.append(.tilde)
                index = text.index(after: index)
                continue
            }

            if character == "^" {
                tokens.append(.power)
                index = text.index(after: index)
                continue
            }

            if character == "<" {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "<" {
                    tokens.append(.shiftLeft)
                    index = text.index(after: next)
                    continue
                }
            }

            if character == ">" {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == ">" {
                    tokens.append(.shiftRight)
                    index = text.index(after: next)
                    continue
                }
            }

            if character == "*" {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "*" {
                    tokens.append(.power)
                    index = text.index(after: next)
                } else {
                    tokens.append(.star)
                    index = next
                }
                continue
            }

            if character == "\"" {
                do {
                    let (value, nextIndex) = try parseString(from: index)
                    tokens.append(.string(value))
                    index = nextIndex
                } catch {
                    tokens.append(.end)
                    return tokens
                }
                continue
            }

            if character.isNumber || character == "." {
                let (token, nextIndex) = parseNumber(from: index)
                tokens.append(token)
                index = nextIndex
                continue
            }

            if character.isLetter || character == "_" {
                var end = text.index(after: index)
                while end < text.endIndex, text[end].isLetter || text[end].isNumber || text[end] == "_" {
                    end = text.index(after: end)
                }
                let identifier = String(text[index..<end])
                if identifier == "xor" {
                    tokens.append(.xorKeyword)
                } else {
                    tokens.append(.identifier(identifier))
                }
                index = end
                continue
            }

            index = text.index(after: index)
        }

        tokens.append(.end)
        return tokens
    }

    private func parseNumber(from start: String.Index) -> (Token, String.Index) {
        if text[start] == "0" {
            let next = text.index(after: start)
            if next < text.endIndex {
                if text[next] == "x" || text[next] == "X" {
                    var end = text.index(after: next)
                    while end < text.endIndex, text[end].isHexDigit {
                        end = text.index(after: end)
                    }
                    let value = String(text[text.index(after: next)..<end])
                    return (.number(Double(Int(value, radix: 16) ?? 0)), end)
                }
                if text[next] == "b" || text[next] == "B" {
                    var end = text.index(after: next)
                    while end < text.endIndex, text[end] == "0" || text[end] == "1" {
                        end = text.index(after: end)
                    }
                    let value = String(text[text.index(after: next)..<end])
                    return (.number(Double(Int(value, radix: 2) ?? 0)), end)
                }
            }
        }

        var end = start
        var hasDecimal = false
        while end < text.endIndex {
            let character = text[end]
            if character.isNumber {
                end = text.index(after: end)
                continue
            }
            if character == ".", !hasDecimal {
                hasDecimal = true
                end = text.index(after: end)
                continue
            }
            break
        }

        let numberText = String(text[start..<end])
        var value = Double(numberText) ?? 0

        if end < text.endIndex {
            let suffix = text[end]
            let multipliers: [Character: Double] = [
                "p": 1e-12,
                "n": 1e-9,
                "u": 1e-6,
                "m": 1e-3,
                "k": 1e3,
                "M": 1e6,
                "G": 1e9,
            ]
            if let multiplier = multipliers[suffix] {
                value *= multiplier
                end = text.index(after: end)
            }
        }

        return (.number(value), end)
    }

    private func parseString(from start: String.Index) throws -> (String, String.Index) {
        var index = text.index(after: start)
        var output = ""
        var escaped = false

        while index < text.endIndex {
            let character = text[index]
            if escaped {
                switch character {
                case "\"":
                    output.append("\"")
                case "\\":
                    output.append("\\")
                case "n":
                    output.append("\n")
                case "t":
                    output.append("\t")
                default:
                    output.append(character)
                }
                escaped = false
                index = text.index(after: index)
                continue
            }

            if character == "\\" {
                escaped = true
                index = text.index(after: index)
                continue
            }

            if character == "\"" {
                return (output, text.index(after: index))
            }

            output.append(character)
            index = text.index(after: index)
        }

        throw ParserError.invalidString
    }
}
