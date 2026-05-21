import SwiftUI

// MARK: - ViewModel

@MainActor
class QRCodesViewModel: ObservableObject {
    @Published var qrCodes: [QRCode] = []
    @Published var isLoading = false
    @Published var error: String?

    func load(token: String) async {
        isLoading = true
        error = nil
        do {
            qrCodes = try await APIClient.shared.get("/qr-codes/", token: token)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func delete(id: String, token: String) async {
        do {
            try await APIClient.shared.delete("/qr-codes/\(id)/delete/", token: token)
            qrCodes.removeAll { $0.id == id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Main View

struct QRCodesView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = QRCodesViewModel()
    @State private var showCreate = false

    var body: some View {
        Group {
            if vm.isLoading && vm.qrCodes.isEmpty {
                ProgressView("Loading QR codes…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.qrCodes.isEmpty {
                ContentUnavailableView(
                    "No QR Codes Yet",
                    systemImage: "qrcode",
                    description: Text("Tap + to create your first QR code.")
                )
            } else {
                List {
                    ForEach(vm.qrCodes) { code in
                        NavigationLink(destination: QRCodeDetailView(qrCode: code)) {
                            QRCodeRow(qrCode: code)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await vm.delete(id: code.id, token: auth.accessToken ?? "") }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .refreshable {
                    await vm.load(token: auth.accessToken ?? "")
                }
            }
        }
        .navigationTitle("QR Codes")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            QRCodeCreateSheet(isPresented: $showCreate) { newCode in
                vm.qrCodes.insert(newCode, at: 0)
            }
            .environmentObject(auth)
        }
        .alert("Error", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.error = nil } }
        )) {
            Button("OK") { vm.error = nil }
        } message: {
            Text(vm.error ?? "")
        }
        .task {
            await vm.load(token: auth.accessToken ?? "")
        }
    }
}

// MARK: - Row

struct QRCodeRow: View {
    let qrCode: QRCode

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(typeColor.opacity(0.15))
                    .frame(width: 42, height: 42)
                Image(systemName: typeIcon)
                    .font(.headline)
                    .foregroundStyle(typeColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(qrCode.name)
                        .font(.headline)
                        .lineLimit(1)
                    TypeBadge(qrType: qrCode.qrType)
                }
                HStack(spacing: 8) {
                    Label("\(qrCode.scanCount) scans", systemImage: "viewfinder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !qrCode.isActive {
                        Text("Inactive")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var typeIcon: String {
        switch qrCode.qrType {
        case "url":   return "link"
        case "wifi":  return "wifi"
        case "email": return "envelope.fill"
        case "phone": return "phone.fill"
        case "sms":   return "message.fill"
        default:      return "text.alignleft"
        }
    }

    private var typeColor: Color {
        switch qrCode.qrType {
        case "url":   return .blue
        case "wifi":  return .green
        case "email": return .orange
        case "phone": return .purple
        case "sms":   return .teal
        default:      return .secondary
        }
    }
}

// MARK: - Shared type badge

struct TypeBadge: View {
    let qrType: String

    var body: some View {
        Text(qrType.uppercased())
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.15), in: Capsule())
            .foregroundStyle(badgeColor)
    }

    private var badgeColor: Color {
        switch qrType {
        case "url":   return .blue
        case "wifi":  return .green
        case "email": return .orange
        case "phone": return .purple
        case "sms":   return .teal
        default:      return .secondary
        }
    }
}
