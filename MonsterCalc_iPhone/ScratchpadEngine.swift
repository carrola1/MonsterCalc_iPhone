import Foundation

enum ResultFormat: String, CaseIterable, Identifiable {
    case scientific
    case engineering
    case si

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scientific:
            return "Scientific"
        case .engineering:
            return "Engineering"
        case .si:
            return "SI"
        }
    }
}

struct ScratchpadEngineConfig: Equatable {
    var sigFigures: Int = 5
    var resultFormat: ResultFormat = .si
}

struct LineResult: Identifiable, Equatable {
    let id: Int
    let lineNumber: Int
    let source: String
    let expression: String
    let display: String
    let error: String?
    let assignmentName: String?
    let value: CalculatorValue?

    var isEmpty: Bool {
        display.isEmpty && (error == nil || error?.isEmpty == true)
    }
}

struct EvaluationContext {
    var variables: [String: CalculatorValue] = [:]
    var ans: CalculatorValue?
}

struct ScratchpadEngine {
    var config = ScratchpadEngineConfig()

    func evaluateDocument(_ text: String) -> [LineResult] {
        var context = EvaluationContext()
        let lines = text.components(separatedBy: "\n")

        return lines.enumerated().map { index, rawLine in
            let lineNumber = index + 1
            let result = evaluateLine(rawLine, lineNumber: lineNumber, context: &context)
            if let value = result.value, result.error == nil, !result.display.isEmpty {
                context.ans = value
                context.variables["line\(lineNumber)"] = value
                if let assignmentName = result.assignmentName {
                    context.variables[assignmentName] = value
                }
            }
            return result
        }
    }

    private func evaluateLine(
        _ line: String,
        lineNumber: Int,
        context: inout EvaluationContext
    ) -> LineResult {
        let cleaned = stripInlineComment(line).trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return LineResult(
                id: lineNumber,
                lineNumber: lineNumber,
                source: line,
                expression: "",
                display: "",
                error: nil,
                assignmentName: nil,
                value: nil
            )
        }

        if isIncompleteAssignment(cleaned) {
            return LineResult(
                id: lineNumber,
                lineNumber: lineNumber,
                source: line,
                expression: cleaned,
                display: "",
                error: nil,
                assignmentName: nil,
                value: nil
            )
        }

        if let assignment = parseAssignment(cleaned) {
            do {
                let value = try evaluateExpression(assignment.expression, context: context)
                return LineResult(
                    id: lineNumber,
                    lineNumber: lineNumber,
                    source: line,
                    expression: assignment.expression,
                    display: format(value),
                    error: nil,
                    assignmentName: assignment.name,
                    value: value
                )
            } catch {
                if shouldSuppressError(error, for: assignment.expression) {
                    return LineResult(
                        id: lineNumber,
                        lineNumber: lineNumber,
                        source: line,
                        expression: assignment.expression,
                        display: "",
                        error: nil,
                        assignmentName: assignment.name,
                        value: nil
                    )
                }
                return LineResult(
                    id: lineNumber,
                    lineNumber: lineNumber,
                    source: line,
                    expression: assignment.expression,
                    display: "",
                    error: error.localizedDescription,
                    assignmentName: assignment.name,
                    value: nil
                )
            }
        }

        do {
            let value = try evaluateExpression(cleaned, context: context)
            return LineResult(
                id: lineNumber,
                lineNumber: lineNumber,
                source: line,
                expression: cleaned,
                display: format(value),
                error: nil,
                assignmentName: nil,
                value: value
            )
        } catch {
            if shouldSuppressError(error, for: cleaned) {
                return LineResult(
                    id: lineNumber,
                    lineNumber: lineNumber,
                    source: line,
                    expression: cleaned,
                    display: "",
                    error: nil,
                    assignmentName: nil,
                    value: nil
                )
            }
            return LineResult(
                id: lineNumber,
                lineNumber: lineNumber,
                source: line,
                expression: cleaned,
                display: "",
                error: error.localizedDescription,
                assignmentName: nil,
                value: nil
            )
        }
    }

    private func evaluateExpression(_ expression: String, context: EvaluationContext) throws -> CalculatorValue {
        if let conversion = parseConversion(expression) {
            var parser = ExpressionParser(
                text: conversion.valueExpression,
                context: context,
                functionProvider: evaluateFunction(name:arguments:)
            )
            let sourceValue = try parser.parseAndEvaluate()
            let numericValue = try requireNumber(sourceValue)
            return .number(try convert(value: numericValue, from: conversion.fromUnit, to: conversion.toUnit))
        }

        var parser = ExpressionParser(
            text: expression,
            context: context,
            functionProvider: evaluateFunction(name:arguments:)
        )
        return try parser.parseAndEvaluate()
    }

    private func isIncompleteAssignment(_ line: String) -> Bool {
        guard let equalsIndex = line.firstIndex(of: "=") else {
            return false
        }
        let name = line[..<equalsIndex].trimmingCharacters(in: .whitespaces)
        let expression = line[line.index(after: equalsIndex)...].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, expression.isEmpty else {
            return false
        }
        guard name.unicodeScalars.first?.properties.isAlphabetic == true || name.first == "_" else {
            return false
        }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private func parseAssignment(_ line: String) -> (name: String, expression: String)? {
        guard let equalsIndex = line.firstIndex(of: "=") else {
            return nil
        }
        let name = line[..<equalsIndex].trimmingCharacters(in: .whitespaces)
        let expression = line[line.index(after: equalsIndex)...].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !expression.isEmpty else {
            return nil
        }
        guard name.unicodeScalars.first?.properties.isAlphabetic == true || name.first == "_" else {
            return nil
        }
        guard name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            return nil
        }
        return (name, expression)
    }

    private func parseConversion(_ expression: String) -> (valueExpression: String, fromUnit: String, toUnit: String)? {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*(.+?)\s+([A-Za-z][A-Za-z0-9]*)\s+to\s+([A-Za-z][A-Za-z0-9]*)\s*$"#) else {
            return nil
        }
        let nsExpression = expression as NSString
        let range = NSRange(location: 0, length: nsExpression.length)
        guard let match = regex.firstMatch(in: expression, range: range), match.numberOfRanges == 4 else {
            return nil
        }

        let valueExpression = nsExpression.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        let fromUnit = nsExpression.substring(with: match.range(at: 2))
        let toUnit = nsExpression.substring(with: match.range(at: 3))
        guard !valueExpression.isEmpty else {
            return nil
        }
        return (valueExpression, fromUnit, toUnit)
    }

    private func stripInlineComment(_ line: String) -> String {
        var inString = false
        var escaped = false

        for (offset, char) in line.enumerated() {
            if escaped {
                escaped = false
                continue
            }
            if char == "\\" {
                escaped = true
                continue
            }
            if char == "\"" {
                inString.toggle()
                continue
            }
            if char == "#" && !inString {
                return String(line.prefix(offset))
            }
        }

        return line
    }

    private func shouldSuppressError(_ error: Error, for expression: String) -> Bool {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }

        if let parserError = error as? ParserError {
            switch parserError {
            case .unexpectedEnd:
                return true
            case .unexpectedToken:
                return looksIncomplete(trimmed)
            case let .unknownIdentifier(name):
                return looksIncomplete(trimmed) || looksLikePartialFunctionArgument(trimmed, identifier: name)
            default:
                return false
            }
        }

        return false
    }

    private func looksLikePartialFunctionArgument(_ expression: String, identifier: String) -> Bool {
        guard expression.contains("("),
              expression.hasSuffix(")"),
              expression.range(of: #"^[A-Za-z_]\w*\(.*\)$"#, options: .regularExpression) != nil
        else {
            return false
        }

        let escapedIdentifier = NSRegularExpression.escapedPattern(for: identifier)
        let trailingArgumentPatterns = [
            #"\#(escapedIdentifier)\s*\)$"#,
            #"\#(escapedIdentifier)\s*,"#,
        ]

        return trailingArgumentPatterns.contains { pattern in
            expression.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func looksIncomplete(_ expression: String) -> Bool {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        if looksLikePartialConversion(trimmed) {
            return true
        }

        if trimmed.hasSuffix("(") || trimmed.hasSuffix(",") {
            return true
        }

        if let last = trimmed.last, "+-*/%&|^=<".contains(last) {
            return true
        }

        var balance = 0
        for char in trimmed {
            if char == "(" { balance += 1 }
            if char == ")" { balance -= 1 }
        }
        if balance > 0 {
            return true
        }

        if trimmed.range(of: #"^[A-Za-z_]\w*$"#, options: .regularExpression) != nil {
            return true
        }

        if trimmed.range(of: #"^[A-Za-z_]\w*\([^)]*$"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }

    private func looksLikePartialConversion(_ expression: String) -> Bool {
        if expression.range(of: #"^\s*.+\s+[A-Za-z][A-Za-z0-9]*\s*$"#, options: .regularExpression) != nil {
            return true
        }
        if expression.range(of: #"^\s*.+\s+[A-Za-z][A-Za-z0-9]*\s+to\s*$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private func evaluateFunction(name: String, arguments: [CalculatorValue]) throws -> CalculatorValue {
        switch name {
        case "abs":
            return .number(abs(try requireNumberArgument(arguments, 0)))
        case "sqrt":
            return .number(sqrt(try requireNumberArgument(arguments, 0)))
        case "sin":
            return .number(sin(try requireNumberArgument(arguments, 0)))
        case "cos":
            return .number(cos(try requireNumberArgument(arguments, 0)))
        case "tan":
            return .number(tan(try requireNumberArgument(arguments, 0)))
        case "asin":
            return .number(asin(try requireNumberArgument(arguments, 0)))
        case "acos":
            return .number(acos(try requireNumberArgument(arguments, 0)))
        case "atan":
            return .number(atan(try requireNumberArgument(arguments, 0)))
        case "log":
            return .number(log(try requireNumberArgument(arguments, 0)))
        case "log10":
            return .number(log10(try requireNumberArgument(arguments, 0)))
        case "log2":
            return .number(log2(try requireNumberArgument(arguments, 0)))
        case "exp":
            return .number(exp(try requireNumberArgument(arguments, 0)))
        case "floor":
            return .number(floor(try requireNumberArgument(arguments, 0)))
        case "ceil":
            return .number(ceil(try requireNumberArgument(arguments, 0)))
        case "rad":
            return .number(try requireNumberArgument(arguments, 0) * .pi / 180)
        case "deg":
            return .number(try requireNumberArgument(arguments, 0) * 180 / .pi)
        case "pdf":
            return .number(normalPDF(try requireNumberArgument(arguments, 0)))
        case "cdf":
            return .number(normalCDF(try requireNumberArgument(arguments, 0)))
        case "min":
            return .number(try arguments.map(requireNumber).min() ?? 0)
        case "max":
            return .number(try arguments.map(requireNumber).max() ?? 0)
        case "sum":
            return .number(try arguments.map(requireNumber).reduce(0, +))
        case "hex":
            let value = try requireIntegerArgument(arguments, 0)
            if arguments.count > 1 {
                let width = max(1, try requireIntegerArgument(arguments, 1))
                return .text(String(format: "0x%0\(width)x", value))
            }
            return .text(String(format: "0x%x", value))
        case "bin":
            let value = try requireIntegerArgument(arguments, 0)
            if arguments.count > 1 {
                let width = max(1, try requireIntegerArgument(arguments, 1))
                let binary = String(value, radix: 2)
                return .text("0b" + String(repeating: "0", count: max(0, width - binary.count)) + binary)
            }
            return .text("0b" + String(value, radix: 2))
        case "bitget":
            return .text(try bitget(arguments))
        case "bitpunch":
            return .number(Double(try bitpunch(arguments)))
        case "a2h":
            return .text(try asciiToHex(arguments))
        case "h2a":
            return .text(try hexToASCII(arguments))
        case "vdiv":
            let vin = try requireNumberArgument(arguments, 0)
            let r1 = try requireNumberArgument(arguments, 1)
            let r2 = try requireNumberArgument(arguments, 2)
            return .number(vin * r2 / (r1 + r2))
        case "rpar":
            let numbers = try arguments.map(requireNumber)
            let reciprocal = numbers.reduce(0.0) { partial, value in
                partial + (1 / value)
            }
            return .number(1 / reciprocal)
        case "findres":
            let target = try requireNumberArgument(arguments, 0)
            let tolerance = arguments.count > 1 ? try requireNumberArgument(arguments, 1) : 1.0
            return .number(findResistor(target: target, tolerance: tolerance))
        case "findrdiv":
            let vin = try requireNumberArgument(arguments, 0)
            let vout = try requireNumberArgument(arguments, 1)
            let tolerance = arguments.count > 2 ? try requireNumberArgument(arguments, 2) : 1.0
            let (r1, r2) = try findResistorDivider(vin: vin, vout: vout, tolerance: tolerance)
            return .text("[\(r1), \(r2)]")
        default:
            throw ParserError.unknownIdentifier(name)
        }
    }

    private func requireArgument(_ values: [CalculatorValue], _ index: Int) throws -> CalculatorValue {
        guard values.indices.contains(index) else {
            throw ParserError.invalidArguments("Missing argument")
        }
        return values[index]
    }

    private func requireNumber(_ value: CalculatorValue) throws -> Double {
        guard case let .number(number) = value else {
            throw ParserError.typeMismatch("Expected a numeric value")
        }
        return number
    }

    private func requireString(_ value: CalculatorValue) throws -> String {
        guard case let .text(text) = value else {
            throw ParserError.typeMismatch("Expected a text value")
        }
        return text
    }

    private func requireNumberArgument(_ arguments: [CalculatorValue], _ index: Int) throws -> Double {
        try requireNumber(requireArgument(arguments, index))
    }

    private func requireIntegerArgument(_ arguments: [CalculatorValue], _ index: Int) throws -> Int {
        Int(floor(try requireNumberArgument(arguments, index)))
    }

    private func bitget(_ arguments: [CalculatorValue]) throws -> String {
        let value = try requireIntegerArgument(arguments, 0)
        let msb = try requireIntegerArgument(arguments, 1)
        let lsb = try requireIntegerArgument(arguments, 2)
        guard msb >= lsb, lsb >= 0 else {
            throw ParserError.invalidArguments("bitget expects msb >= lsb >= 0")
        }
        let width = msb - lsb + 1
        let mask = ((1 << width) - 1) << lsb
        let result = (value & mask) >> lsb
        let binary = String(result, radix: 2)
        return "0b" + String(repeating: "0", count: max(0, width - binary.count)) + binary
    }

    private func bitpunch(_ arguments: [CalculatorValue]) throws -> Int {
        let value = try requireIntegerArgument(arguments, 0)
        let bit = try requireIntegerArgument(arguments, 1)
        let state = try requireIntegerArgument(arguments, 2)

        guard bit >= 0 else {
            throw ParserError.invalidArguments("bit number must be non-negative")
        }
        guard state == 0 || state == 1 else {
            throw ParserError.invalidArguments("bit value must be 0 or 1")
        }

        if state == 1 {
            return value | (1 << bit)
        }
        return value & ~(1 << bit)
    }

    private func asciiToHex(_ arguments: [CalculatorValue]) throws -> String {
        let input = try requireString(requireArgument(arguments, 0))
        let encoded = input.utf8.map { String(format: "%02x", $0) }.joined()
        return "0x\(encoded)"
    }

    private func hexToASCII(_ arguments: [CalculatorValue]) throws -> String {
        let raw = try requireArgument(arguments, 0)
        let hexString: String
        switch raw {
        case let .text(text):
            hexString = text
        case let .number(number):
            hexString = String(format: "%llx", Int64(number))
        }

        let cleaned = hexString
            .replacingOccurrences(of: "0x", with: "")
            .replacingOccurrences(of: " ", with: "")

        guard cleaned.count.isMultiple(of: 2) else {
            throw ParserError.invalidArguments("Hex string must contain an even number of digits")
        }

        var bytes: [UInt8] = []
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            let byteString = cleaned[index..<next]
            guard let byte = UInt8(byteString, radix: 16) else {
                throw ParserError.invalidArguments("Invalid hex text")
            }
            bytes.append(byte)
            index = next
        }

        guard let output = String(bytes: bytes, encoding: .utf8) else {
            throw ParserError.invalidArguments("Hex text is not valid UTF-8")
        }
        return output
    }

    private func findResistor(target: Double, tolerance: Double) -> Double {
        let series = tolerance <= 0.1 ? onePercentTightSeries : onePercentSeries
        var normalized = target
        var multiplier = 0

        while normalized >= 100 {
            normalized /= 10
            multiplier += 1
        }

        while normalized < 10 {
            normalized *= 10
            multiplier -= 1
        }

        let match = series.min(by: { abs($0 - normalized) < abs($1 - normalized) }) ?? normalized
        return match * pow(10, Double(multiplier))
    }

    private func findResistorDivider(vin: Double, vout: Double, tolerance: Double) throws -> (Double, Double) {
        guard vin != 0 else {
            throw ParserError.invalidArguments("vin must be non-zero")
        }

        let series = tolerance <= 0.1 ? onePercentTightSeries : onePercentSeries
        let resistorDecades: [Double] = [1, 10, 100, 1000]
        let largeSeries = resistorDecades.flatMap { scale in
            series.map { $0 * scale }
        }

        let ratio = vout / vin
        var bestR1 = 0.0
        var bestR2 = 0.0
        var bestDiff = Double.greatestFiniteMagnitude

        if ratio <= 0.5 {
            for r2 in series {
                for r1 in largeSeries.reversed() {
                    let newRatio = r2 / (r1 + r2)
                    let diff = abs(newRatio - ratio)
                    if diff < bestDiff {
                        bestDiff = diff
                        bestR1 = r1
                        bestR2 = r2
                    }
                }
            }
        } else {
            for r2 in largeSeries {
                for r1 in series {
                    let newRatio = r2 / (r1 + r2)
                    let diff = abs(newRatio - ratio)
                    if diff < bestDiff {
                        bestDiff = diff
                        bestR1 = r1
                        bestR2 = r2
                    }
                }
            }
        }

        return (bestR1, bestR2)
    }

    private func convert(value: Double, from fromUnit: String, to toUnit: String) throws -> Double {
        if let result = convertTemperature(value: value, from: fromUnit, to: toUnit) {
            return result
        }

        if let from = linearUnitMap[fromUnit], let to = linearUnitMap[toUnit], from.dimension == to.dimension {
            let baseValue = value * from.toBaseScale
            return baseValue / to.toBaseScale
        }

        throw ParserError.invalidArguments("Unsupported conversion: \(fromUnit) to \(toUnit)")
    }

    private func convertTemperature(value: Double, from fromUnit: String, to toUnit: String) -> Double? {
        switch (fromUnit, toUnit) {
        case ("C", "F"):
            return (value * 9 / 5) + 32
        case ("F", "C"):
            return (value - 32) * 5 / 9
        case ("C", "C"), ("F", "F"):
            return value
        default:
            return nil
        }
    }

    private func normalPDF(_ x: Double) -> Double {
        exp(-0.5 * x * x) / sqrt(2 * .pi)
    }

    private func normalCDF(_ x: Double) -> Double {
        0.5 * (1 + erf(x / sqrt(2)))
    }

    private func format(_ value: CalculatorValue) -> String {
        switch value {
        case let .text(text):
            return text
        case let .number(number):
            return formatNumber(number)
        }
    }

    private func formatNumber(_ value: Double) -> String {
        if value.isNaN || value.isInfinite {
            return String(value)
        }
        if value == 0 {
            return "0"
        }
        if abs(value.rounded() - value) < 1e-10 && abs(value) < 1000 {
            return String(Int(value.rounded()))
        }
        switch config.resultFormat {
        case .scientific:
            return formatScientific(value)
        case .engineering:
            return formatEngineering(value)
        case .si:
            return formatSI(value)
        }
    }

    private func formatScientific(_ value: Double) -> String {
        let exponent = Int(floor(log10(abs(value))))
        let mantissa = value / pow(10, Double(exponent))
        return "\(formatSignificant(mantissa))e\(exponent)"
    }

    private func formatEngineering(_ value: Double) -> String {
        let exponent = engineeringExponent(for: value)
        let mantissa = value / pow(10, Double(exponent))
        return "\(formatSignificant(mantissa))e\(exponent)"
    }

    private func formatSI(_ value: Double) -> String {
        let exponent = engineeringExponent(for: value)
        let mantissa = value / pow(10, Double(exponent))
        let suffixes: [Int: String] = [-12: "p", -9: "n", -6: "u", -3: "m", 3: "k", 6: "M", 9: "G"]

        if let suffix = suffixes[exponent] {
            return "\(formatSignificant(mantissa))\(suffix)"
        }
        if exponent == 0 {
            return formatSignificant(value)
        }
        return "\(formatSignificant(mantissa))e\(exponent)"
    }

    private func engineeringExponent(for value: Double) -> Int {
        Int(floor(log10(abs(value)) / 3.0) * 3.0)
    }

    private func formatSignificant(_ value: Double) -> String {
        let digits = max(1, min(12, config.sigFigures))
        let formatted = String(format: "%.\(digits)g", value)
        return normalizeExponent(formatted)
    }

    private func normalizeExponent(_ value: String) -> String {
        guard let exponentRange = value.range(of: "e") else {
            return value
        }

        let mantissa = value[..<exponentRange.lowerBound]
        let exponentText = value[value.index(after: exponentRange.lowerBound)...]
        if let exponent = Int(exponentText) {
            return "\(mantissa)e\(exponent)"
        }
        return value
    }
}

private let onePercentSeries: [Double] = [
    10.0, 10.2, 10.5, 10.7, 11.0, 11.3, 11.5, 11.8, 12.1, 12.4,
    12.7, 13.0, 13.3, 13.7, 14.0, 14.3, 14.7, 15.0, 15.4, 15.8,
    16.2, 16.5, 16.9, 17.4, 17.8, 18.2, 18.7, 19.1, 19.6, 20.0,
    20.5, 21.0, 21.5, 22.1, 22.6, 23.2, 23.7, 24.3, 24.9, 25.5,
    26.1, 26.7, 27.4, 28.0, 28.7, 29.4, 30.1, 30.9, 31.6, 32.4,
    33.2, 34.0, 34.8, 35.7, 36.5, 37.4, 38.3, 39.2, 40.2, 41.2,
    42.2, 43.2, 44.2, 45.3, 46.4, 47.5, 48.7, 49.9, 51.1, 52.3,
    53.6, 54.9, 56.2, 57.6, 59.0, 60.4, 61.9, 63.4, 64.9, 66.5,
    68.1, 69.8, 71.5, 73.2, 75.0, 76.8, 78.7, 80.6, 82.5, 84.5,
    86.6, 88.7, 90.9, 93.1, 95.3, 97.6,
]

private let onePercentTightSeries: [Double] = [
    10.0, 10.1, 10.2, 10.5, 10.7, 11.0, 11.3, 11.5, 11.8, 12.1,
    12.4, 12.7, 13.0, 13.3, 13.7, 14.0, 14.3, 14.7, 15.0, 15.4,
    15.8, 16.2, 16.5, 16.9, 17.4, 17.8, 18.2, 18.7, 19.1, 19.6,
    20.0, 20.5, 21.0, 21.5, 22.1, 22.6, 23.2, 23.7, 24.3, 24.9,
    25.5, 26.1, 26.7, 27.4, 28.0, 28.7, 29.4, 30.1, 30.9, 31.6,
    32.4, 33.2, 34.0, 34.8, 35.7, 36.5, 37.4, 38.3, 39.2, 40.2,
    41.2, 42.2, 43.2, 44.2, 45.3, 46.4, 47.5, 48.7, 49.9, 51.1,
    52.3, 53.6, 54.9, 56.2, 57.6, 59.0, 60.4, 61.9, 63.4, 64.9,
    66.5, 68.1, 69.8, 71.5, 73.2, 75.0, 76.8, 78.7, 80.6, 82.5,
    84.5, 86.6, 88.7, 90.9, 93.1, 95.3, 97.6,
]

private struct LinearConversionUnit {
    let dimension: String
    let toBaseScale: Double
}

private let linearUnitMap: [String: LinearConversionUnit] = [
    "mm": .init(dimension: "length", toBaseScale: 0.001),
    "cm": .init(dimension: "length", toBaseScale: 0.01),
    "m": .init(dimension: "length", toBaseScale: 1.0),
    "km": .init(dimension: "length", toBaseScale: 1000.0),
    "mil": .init(dimension: "length", toBaseScale: 0.0000254),
    "in": .init(dimension: "length", toBaseScale: 0.0254),

    "mg": .init(dimension: "weight", toBaseScale: 0.001),
    "g": .init(dimension: "weight", toBaseScale: 1.0),
    "kg": .init(dimension: "weight", toBaseScale: 1000.0),
    "lbs": .init(dimension: "weight", toBaseScale: 453.59237),
    "oz": .init(dimension: "weight", toBaseScale: 28.349523125),

    "mL": .init(dimension: "volume", toBaseScale: 1.0),
    "L": .init(dimension: "volume", toBaseScale: 1000.0),
    "tsp": .init(dimension: "volume", toBaseScale: 4.92892159375),
    "tbl": .init(dimension: "volume", toBaseScale: 14.78676478125),
    "pt": .init(dimension: "volume", toBaseScale: 473.176473),
    "qt": .init(dimension: "volume", toBaseScale: 946.352946),
    "gal": .init(dimension: "volume", toBaseScale: 3785.411784),

    "N": .init(dimension: "force", toBaseScale: 1.0),
    "kN": .init(dimension: "force", toBaseScale: 1000.0),
    "lbf": .init(dimension: "force", toBaseScale: 4.4482216152605),

    "bits": .init(dimension: "memory", toBaseScale: 1.0),
    "bytes": .init(dimension: "memory", toBaseScale: 8.0),
    "KB": .init(dimension: "memory", toBaseScale: 8_000.0),
    "MB": .init(dimension: "memory", toBaseScale: 8_000_000.0),
    "GB": .init(dimension: "memory", toBaseScale: 8_000_000_000.0),
    "Tb": .init(dimension: "memory", toBaseScale: 1_000_000_000_000.0),
]
