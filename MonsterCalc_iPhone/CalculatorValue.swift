import Foundation

enum CalculatorValue: Equatable {
    case number(Double)
    case text(String)

    var numberValue: Double? {
        if case let .number(value) = self {
            return value
        }
        return nil
    }

    var textValue: String? {
        if case let .text(value) = self {
            return value
        }
        return nil
    }
}
