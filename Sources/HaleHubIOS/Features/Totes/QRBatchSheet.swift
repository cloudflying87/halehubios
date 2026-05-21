import SwiftUI
import UIKit

// MARK: - Model

struct QRBatchItem: Decodable, Sendable {
    let qrCodeIdentifier: String
    let scanUrl: String
    let qrImageDataUrl: String

    var uiImage: UIImage? {
        let prefix = "data:image/png;base64,"
        guard qrImageDataUrl.hasPrefix(prefix) else { return nil }
        guard let data = Data(base64Encoded: String(qrImageDataUrl.dropFirst(prefix.count))) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Sheet

struct QRBatchSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var count = 8
    @State private var items: [QRBatchItem] = []
    @State private var isGenerating = false
    @State private var error: String?
    @State private var showShareSheet = false

    private let countOptions = [4, 8, 12, 24, 48]
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if items.isEmpty {
                    configView
                } else {
                    gridView
                }
            }
            .navigationTitle("Blank QR Codes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !items.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Share All") { showShareSheet = true }
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityViewController(items: items.compactMap { $0.uiImage })
            }
        }
    }

    // MARK: - Config view

    private var configView: some View {
        Form {
            Section {
                Picker("Number of codes", selection: $count) {
                    ForEach(countOptions, id: \.self) { n in
                        Text("\(n) codes").tag(n)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("How many blank QR codes do you need?")
            } footer: {
                Text("These codes aren't linked to any tote yet. Stick them on totes, then scan each one to create or link a tote.")
            }

            if let error {
                Section {
                    Text(error).foregroundStyle(.red).font(.subheadline)
                }
            }

            Section {
                Button {
                    Task { await generate() }
                } label: {
                    if isGenerating {
                        HStack { ProgressView(); Text("Generating…") }
                    } else {
                        Text("Generate \(count) QR Codes")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .disabled(isGenerating)
            }
        }
    }

    // MARK: - Grid view

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items, id: \.qrCodeIdentifier) { item in
                    VStack(spacing: 4) {
                        if let img = item.uiImage {
                            Image(uiImage: img)
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .padding(6)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.systemGray5))
                                .aspectRatio(1, contentMode: .fit)
                        }
                        Text(item.qrCodeIdentifier)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Generate

    private func generate() async {
        guard let token = auth.accessToken else { return }
        isGenerating = true
        error = nil
        do {
            struct Req: Encodable { let count: Int }
            items = try await APIClient.shared.post(
                "/totes/qr-codes/generate-batch/", body: Req(count: count), token: token
            )
        } catch {
            self.error = error.localizedDescription
        }
        isGenerating = false
    }
}

// MARK: - UIActivityViewController wrapper

struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
