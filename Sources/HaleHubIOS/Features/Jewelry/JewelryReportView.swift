import SwiftUI

@MainActor
final class JewelryReportViewModel: ObservableObject {
    @Published var report: JewelryReport?
    @Published var isLoading = false
    @Published var error: String?

    func load(token: String) async {
        isLoading = true; error = nil
        do {
            report = try await APIClient.shared.get("/jewelry/report/", token: token)
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }
}

struct JewelryReportView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = JewelryReportViewModel()
    private var token: String { auth.accessToken ?? "" }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let r = vm.report {
                    HStack {
                        stat("Pieces", "\(r.totalCount)")
                        Spacer()
                        stat("Estimated Value", LoanFormatters.money(r.totalValue, fractionDigits: 0))
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("By Category").font(.headline)
                        ForEach(r.categories) { c in
                            HStack {
                                Text(c.category).font(.subheadline)
                                Spacer()
                                Text("\(c.count)").font(.caption).foregroundStyle(.secondary)
                                Text(LoanFormatters.money(c.value, fractionDigits: 0))
                                    .font(.subheadline).fontWeight(.medium)
                                    .frame(width: 90, alignment: .trailing)
                            }
                            .padding(.vertical, 3)
                            Divider()
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                } else if vm.isLoading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(16)
        }
        .navigationTitle("Jewelry Report")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load(token: token) }
        .refreshable { await vm.load(token: token) }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3).fontWeight(.bold)
        }
    }
}
