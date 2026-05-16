import SwiftUI

struct PartsLookupView: View {
    @EnvironmentObject var auth: AuthManager

    @State private var parts: [PartLookup] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && parts.isEmpty {
                ProgressView("Loading parts…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "Error",
                    systemImage: "exclamationmark.circle",
                    description: Text(error)
                )
            } else if parts.isEmpty {
                ContentUnavailableView(
                    "No Parts Data",
                    systemImage: "wrench.and.screwdriver",
                    description: Text("Log some maintenance events to see part history.")
                )
            } else {
                List(parts) { part in
                    PartLookupRow(part: part)
                }
                .listStyle(.insetGrouped)
                .refreshable { await loadParts() }
            }
        }
        .navigationTitle("Parts Lookup")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadParts() }
    }

    private func loadParts() async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        errorMessage = nil
        do {
            parts = try await APIClient.shared.get("/vehicles/parts-lookup/", token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Parts Lookup Row

struct PartLookupRow: View {
    let part: PartLookup

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(part.categoryName, systemImage: "wrench.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            if let last = part.lastUsed {
                VStack(alignment: .leading, spacing: 3) {
                    if !last.description.isEmpty {
                        Text(last.description)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    HStack(spacing: 10) {
                        if last.cost > 0 {
                            Label(String(format: "$%.2f", last.cost), systemImage: "dollarsign.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 2) {
                            Image(systemName: "calendar")
                            Text(last.date, style: .date)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Label(last.vehicleName, systemImage: "car")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Text("No history yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
        .padding(.vertical, 4)
    }
}
