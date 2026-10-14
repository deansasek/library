import Foundation

/// Answers for Quick Open: arithmetic such as `12*8`, and unit conversions such as `5 km in miles`.
enum QuickAnswers {
    static func answer(for query: String) -> (value: String, detail: String)? {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.contains(where: \.isNumber) else { return nil }
        if let converted = convert(text) { return (converted, text) }
        var calculator = Calculator(text)
        return calculator.evaluate().map { (format($0), text) }
    }

    /// A number as people write it: no grouping, no trailing zeros, up to eight decimals.
    static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 8
        formatter.decimalSeparator = "."
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    // MARK: Units

    private static let units: [String: Dimension] = [
        "m": UnitLength.meters, "meter": UnitLength.meters, "meters": UnitLength.meters,
        "km": UnitLength.kilometers, "kilometer": UnitLength.kilometers, "kilometers": UnitLength.kilometers,
        "cm": UnitLength.centimeters, "mm": UnitLength.millimeters,
        "mi": UnitLength.miles, "mile": UnitLength.miles, "miles": UnitLength.miles,
        "ft": UnitLength.feet, "foot": UnitLength.feet, "feet": UnitLength.feet,
        "inch": UnitLength.inches, "inches": UnitLength.inches,
        "yd": UnitLength.yards, "yard": UnitLength.yards, "yards": UnitLength.yards,
        "g": UnitMass.grams, "gram": UnitMass.grams, "grams": UnitMass.grams,
        "kg": UnitMass.kilograms, "kilogram": UnitMass.kilograms, "kilograms": UnitMass.kilograms,
        "lb": UnitMass.pounds, "lbs": UnitMass.pounds, "pound": UnitMass.pounds, "pounds": UnitMass.pounds,
        "oz": UnitMass.ounces, "ounce": UnitMass.ounces, "ounces": UnitMass.ounces,
        "l": UnitVolume.liters, "liter": UnitVolume.liters, "liters": UnitVolume.liters,
        "ml": UnitVolume.milliliters, "gal": UnitVolume.gallons, "gallon": UnitVolume.gallons,
        "gallons": UnitVolume.gallons, "cup": UnitVolume.cups, "cups": UnitVolume.cups,
        "qt": UnitVolume.quarts, "pt": UnitVolume.pints,
        "c": UnitTemperature.celsius, "°c": UnitTemperature.celsius, "celsius": UnitTemperature.celsius,
        "f": UnitTemperature.fahrenheit, "°f": UnitTemperature.fahrenheit, "fahrenheit": UnitTemperature.fahrenheit,
        "k": UnitTemperature.kelvin, "kelvin": UnitTemperature.kelvin,
        "mph": UnitSpeed.milesPerHour, "kph": UnitSpeed.kilometersPerHour, "km/h": UnitSpeed.kilometersPerHour,
        "m/s": UnitSpeed.metersPerSecond,
        "s": UnitDuration.seconds, "sec": UnitDuration.seconds, "second": UnitDuration.seconds,
        "seconds": UnitDuration.seconds, "min": UnitDuration.minutes, "minute": UnitDuration.minutes,
        "minutes": UnitDuration.minutes, "h": UnitDuration.hours, "hr": UnitDuration.hours,
        "hour": UnitDuration.hours, "hours": UnitDuration.hours,
        "kb": UnitInformationStorage.kilobytes, "mb": UnitInformationStorage.megabytes,
        "gb": UnitInformationStorage.gigabytes, "tb": UnitInformationStorage.terabytes,
    ]

    /// `5 km in miles`, `72 f to c`. Both units must measure the same thing.
    private static func convert(_ text: String) -> String? {
        let pattern = #"^(-?[\d.]+)\s*([a-zA-Z°/]+)\s+(?:in|to|as)\s+([a-zA-Z°/]+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges == 4 else { return nil }
        func group(_ index: Int) -> String? {
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
        guard let number = group(1).flatMap({ Double($0) }), let fromName = group(2), let toName = group(3),
              let from = units[fromName.lowercased()], let to = units[toName.lowercased()],
              type(of: from) == type(of: to) else { return nil }
        let result = Measurement(value: number, unit: from).converted(to: to).value
        return "\(format(result)) \(toName)"
    }

    // MARK: Arithmetic

    /// Reads `+ - * / % ^` and brackets by precedence. It never crashes on odd input, which is why it replaces
    /// NSExpression, whose parser raises uncatchable exceptions.
    private struct Calculator {
        private let characters: [Character]
        private var index = 0
        private var usedOperator = false

        init(_ text: String) {
            characters = Array(text.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
                .replacingOccurrences(of: ",", with: "").filter { !$0.isWhitespace })
        }

        /// The value, only when the whole text was one expression with at least one operator.
        mutating func evaluate() -> Double? {
            guard let value = expression(), index == characters.count, usedOperator, value.isFinite else { return nil }
            return value
        }

        private var peek: Character? { index < characters.count ? characters[index] : nil }

        private mutating func expression() -> Double? {
            guard var left = term() else { return nil }
            while let op = peek, op == "+" || op == "-" {
                index += 1
                usedOperator = true
                guard let right = term() else { return nil }
                left = op == "+" ? left + right : left - right
            }
            return left
        }

        private mutating func term() -> Double? {
            guard var left = power() else { return nil }
            while let op = peek, op == "*" || op == "/" || op == "%" || op == "x" {
                index += 1
                usedOperator = true
                guard let right = power() else { return nil }
                switch op {
                case "/":
                    guard right != 0 else { return nil }
                    left /= right
                case "%":
                    guard right != 0 else { return nil }
                    left = left.truncatingRemainder(dividingBy: right)
                default:
                    left *= right
                }
            }
            return left
        }

        private mutating func power() -> Double? {
            guard let base = unary() else { return nil }
            if peek == "^" {
                index += 1
                usedOperator = true
                guard let exponent = power() else { return nil }
                return pow(base, exponent)
            }
            return base
        }

        private mutating func unary() -> Double? {
            if peek == "-" {
                index += 1
                return unary().map { -$0 }
            }
            return primary()
        }

        private mutating func primary() -> Double? {
            if peek == "(" {
                index += 1
                guard let value = expression(), peek == ")" else { return nil }
                index += 1
                return value
            }
            let start = index
            while let character = peek, character.isNumber || character == "." { index += 1 }
            return start == index ? nil : Double(String(characters[start..<index]))
        }
    }
}
