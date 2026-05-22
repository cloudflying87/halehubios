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
    @State private var sharePDF: Data?

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
                        HStack {
                            Button("Print") { printQRCodes() }
                            Button("Share PDF") {
                                sharePDF = makePDF()
                                showShareSheet = true
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let pdf = sharePDF {
                    ActivityViewController(items: [pdf])
                }
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

    // MARK: - Print / PDF

    private func printQRCodes() {
        let pdf = makePDF()
        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = "HaleHub QR Codes"
        printInfo.outputType = .grayscale
        printController.printInfo = printInfo
        printController.printingItem = pdf
        printController.present(animated: true)
    }

    /// Renders all QR codes into a US-Letter PDF, 4 per row.
    private func makePDF() -> Data {
        let pageW: CGFloat = 612   // 8.5 in @ 72 dpi
        let pageH: CGFloat = 792   // 11 in @ 72 dpi
        let margin: CGFloat = 36
        let cols = 4
        let colGap: CGFloat = 12
        let rowGap: CGFloat = 14
        let labelH: CGFloat = 14

        let usableW = pageW - 2 * margin
        let cellW = (usableW - CGFloat(cols - 1) * colGap) / CGFloat(cols)
        let rowH = cellW + labelH + rowGap
        let rowsPerPage = Int((pageH - 2 * margin) / rowH)

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 8, weight: .regular),
            .foregroundColor: UIColor.darkGray
        ]

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))
        return renderer.pdfData { ctx in
            var idx = 0
            while idx < items.count {
                ctx.beginPage()
                for row in 0..<rowsPerPage {
                    for col in 0..<cols {
                        guard idx < items.count else { break }
                        let item = items[idx]; idx += 1
                        let x = margin + CGFloat(col) * (cellW + colGap)
                        let y = margin + CGFloat(row) * rowH
                        if let img = item.uiImage {
                            img.draw(in: CGRect(x: x, y: y, width: cellW, height: cellW))
                        }
                        let labelRect = CGRect(x: x, y: y + cellW + 2, width: cellW, height: labelH)
                        let label = NSString(string: item.qrCodeIdentifier)
                        let labelSize = label.size(withAttributes: labelAttrs)
                        let centeredRect = CGRect(
                            x: x + (cellW - labelSize.width) / 2,
                            y: labelRect.minY,
                            width: labelSize.width,
                            height: labelH
                        )
                        label.draw(in: centeredRect, withAttributes: labelAttrs)
                    }
                }
            }
        }
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
