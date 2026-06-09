import SwiftUI

/// Shows every verse in a chapter, marking which are read vs missing.
/// Verse status is derived from recorded reading ranges (the finest data the
/// backend tracks), so "missing" means not covered by any logged reading.
struct ChapterDetailView: View {
    let bookName: String
    let chapter: ChapterProgress

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    private var readVerses: Set<Int> { chapter.readVerses }
    private var missingVerses: [Int] {
        guard chapter.totalVerses > 0 else { return [] }
        return (1...chapter.totalVerses).filter { !readVerses.contains($0) }
    }

    var body: some View {
        Group {
            if chapter.totalVerses <= 0 {
                ContentUnavailableView(
                    "No verse data",
                    systemImage: "text.book.closed",
                    description: Text("Verse details aren't available for this chapter — only whether it's been read.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Summary
                        HStack {
                            Label("\(readVerses.count)/\(chapter.totalVerses) verses read",
                                  systemImage: chapter.isComplete ? "checkmark.seal.fill" : "circle.dashed")
                                .font(.subheadline)
                                .foregroundStyle(chapter.isComplete ? .green : .secondary)
                            Spacer()
                        }
                        .padding(.horizontal)

                        // Legend
                        HStack(spacing: 16) {
                            legend(color: .green, text: "Read")
                            legend(color: Color(.systemGray5), text: "Missing")
                            Spacer()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                        // Verse grid
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(1...chapter.totalVerses, id: \.self) { v in
                                let read = readVerses.contains(v)
                                Text("\(v)")
                                    .font(.footnote.weight(.medium))
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .background(read ? Color.green.opacity(0.85) : Color(.systemGray5))
                                    .foregroundStyle(read ? .white : .secondary)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(.horizontal)

                        if !missingVerses.isEmpty {
                            Text("Missing: \(missingSummary)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                                .padding(.bottom, 8)
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle("\(bookName) \(chapter.chapterNumber)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(text)
        }
    }

    /// Compress missing verse numbers into a compact "1-3, 7, 10-12" string.
    private var missingSummary: String {
        var parts: [String] = []
        var start: Int?
        var prev: Int?
        for v in missingVerses {
            if let p = prev, v == p + 1 {
                prev = v
            } else {
                if let s = start, let p = prev { parts.append(s == p ? "\(s)" : "\(s)-\(p)") }
                start = v; prev = v
            }
        }
        if let s = start, let p = prev { parts.append(s == p ? "\(s)" : "\(s)-\(p)") }
        return parts.joined(separator: ", ")
    }
}
