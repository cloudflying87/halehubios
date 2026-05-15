import SwiftUI

struct TimeCalculatorView: View {
    @State private var operation = TimeOperation.add
    @State private var time1 = ""
    @State private var time2 = ""
    @State private var result: String?
    @State private var resultDetail: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Operation") {
                Picker("Operation", selection: $operation) {
                    ForEach(TimeOperation.allCases) { op in
                        Text(op.label).tag(op)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                TimeInputField(
                    label: operation == .difference ? "Start Time" : "Time 1",
                    placeholder: "HH:MM or HH:MM:SS",
                    text: $time1
                )
                TimeInputField(
                    label: operation == .difference ? "End Time" : "Time 2",
                    placeholder: "HH:MM or HH:MM:SS",
                    text: $time2
                )
            }

            Section {
                Button("Calculate") { calculate() }
                    .frame(maxWidth: .infinity)
                    .disabled(time1.isEmpty || time2.isEmpty)
            }

            if let error = errorMessage {
                Section {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }

            if let r = result {
                Section("Result") {
                    VStack(alignment: .center, spacing: 6) {
                        Text(r)
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity)
                        if let detail = resultDetail {
                            Text(detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            if operation == .convert && !time1.isEmpty {
                conversionSection
            }
        }
        .navigationTitle("Time Calculator")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: time1) { _, _ in result = nil; errorMessage = nil }
        .onChange(of: time2) { _, _ in result = nil; errorMessage = nil }
        .onChange(of: operation) { _, _ in result = nil; errorMessage = nil }
    }

    @ViewBuilder
    var conversionSection: some View {
        if let secs = parseTime(time1) {
            Section("Conversions") {
                ResultRow(label: "Total Minutes", value: String(format: "%.2f", Double(secs) / 60))
                ResultRow(label: "Total Hours", value: String(format: "%.4f", Double(secs) / 3600))
                ResultRow(label: "Total Seconds", value: "\(secs)")
            }
        }
    }

    private func calculate() {
        errorMessage = nil
        result = nil
        resultDetail = nil

        guard let secs1 = parseTime(time1) else {
            errorMessage = "Invalid format for Time 1. Use HH:MM or HH:MM:SS"
            return
        }
        guard let secs2 = parseTime(time2) else {
            errorMessage = "Invalid format for Time 2. Use HH:MM or HH:MM:SS"
            return
        }

        switch operation {
        case .add:
            let total = secs1 + secs2
            result = formatSeconds(total)
            resultDetail = "\(formatSeconds(secs1)) + \(formatSeconds(secs2))"
        case .subtract:
            let diff = abs(secs1 - secs2)
            result = formatSeconds(diff)
            resultDetail = secs1 >= secs2
                ? "\(formatSeconds(secs1)) − \(formatSeconds(secs2))"
                : "|\(formatSeconds(secs1)) − \(formatSeconds(secs2))| (absolute)"
        case .difference:
            var diff = secs2 - secs1
            var note = ""
            if diff < 0 {
                diff += 86400 // crossed midnight
                note = " (crosses midnight)"
            }
            result = formatSeconds(diff)
            resultDetail = "\(formatSeconds(secs1)) → \(formatSeconds(secs2))\(note)"
        case .convert:
            result = formatSeconds(secs1)
            resultDetail = "See conversions below"
        }
    }

    private func parseTime(_ input: String) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ":").map { String($0) }
        guard parts.count >= 2, parts.count <= 3 else { return nil }
        guard let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        let s = parts.count == 3 ? (Int(parts[2]) ?? 0) : 0
        guard m < 60, s < 60 else { return nil }
        return h * 3600 + m * 60 + s
    }

    private func formatSeconds(_ totalSeconds: Int) -> String {
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }
}

enum TimeOperation: String, CaseIterable, Identifiable {
    case add, subtract, difference, convert
    var id: String { rawValue }
    var label: String {
        switch self {
        case .add: return "Add"
        case .subtract: return "Subtract"
        case .difference: return "Difference"
        case .convert: return "Convert"
        }
    }
}

struct TimeInputField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        LabeledContent(label) {
            TextField(placeholder, text: $text)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .font(.system(.body, design: .monospaced))
        }
    }
}
