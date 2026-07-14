import SwiftUI
import VisionKit
import AVFoundation

/// Unified pantry scanner. A single live camera recognizes both barcodes and
/// text (VisionKit `DataScannerViewController`, on-device — no network, no key):
///   • tap a barcode → recognize an existing item, else Open Food Facts lookup,
///     else a new-item form with the code attached
///   • tap a product name → a new-item form prefilled with that text
/// Everything resolves through the same `PantryItemEditSheet`.
struct PantryScannerSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var vm: PantryViewModel
    let onSaved: (PantryItem) -> Void

    @State private var isLooking = false
    @State private var errorMessage: String?
    @State private var cameraDenied = false
    @State private var result: ScanResult?

    /// What a scan resolved to — an item we already own, or a new one to add.
    private enum ScanResult: Identifiable {
        case existing(PantryItem)
        case new(PantryItemPrefill)

        var id: String {
            switch self {
            case .existing(let item): return "existing-\(item.id)"
            case .new: return "new"
            }
        }
    }

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && !cameraDenied
    }

    var body: some View {
        NavigationStack {
            Group {
                if scannerAvailable {
                    scannerBody
                } else {
                    unavailableView
                }
            }
            .navigationTitle("Scan Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(scannerAvailable ? Color.white : Color.accentColor)
                }
            }
            .task { await requestCamera() }
            // Resume tapping after the editor is dismissed without saving.
            .sheet(item: $result) { res in
                editor(for: res).environmentObject(auth)
            }
        }
    }

    // MARK: Overlays

    private var scannerBody: some View {
        ZStack {
            PantryDataScannerView(
                onBarcode: { code in Task { await handleBarcode(code) } },
                onText: { text in handleText(text) }
            )
            .ignoresSafeArea()

            overlay
        }
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var overlay: some View {
        VStack {
            Spacer()
            if isLooking {
                HStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("Looking up product…").foregroundStyle(.white)
                }
                .padding(.bottom, 40)
            } else if let err = errorMessage {
                Text(err)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            } else {
                Text("Tap a barcode, or tap the product’s name")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(.bottom, 40)
            }
        }
    }

    private var unavailableView: some View {
        ContentUnavailableView {
            Label("Scanning Unavailable", systemImage: "camera.fill")
        } description: {
            Text(cameraDenied
                 ? "Camera access is off. Enable it in Settings, or add the item manually."
                 : "This device can’t scan. You can still add the item manually.")
        } actions: {
            Button {
                result = .new(PantryItemPrefill())
            } label: {
                Label("Add Manually", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func editor(for res: ScanResult) -> some View {
        switch res {
        case .existing(let item):
            PantryItemEditSheet(item: item, vm: vm) { saved in onSaved(saved); dismiss() }
        case .new(let prefill):
            PantryItemEditSheet(item: nil, vm: vm, prefill: prefill) { saved in onSaved(saved); dismiss() }
        }
    }

    // MARK: Handling

    private func requestCamera() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraDenied = false
        case .notDetermined:
            cameraDenied = !(await AVCaptureDevice.requestAccess(for: .video))
        default:
            cameraDenied = true
        }
    }

    private func handleBarcode(_ raw: String) async {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result == nil, !isLooking, !code.isEmpty else { return }
        errorMessage = nil

        // 1. Already in the pantry? Open it directly — works even for products
        //    Open Food Facts doesn't know (their code was saved when first added).
        if let existing = vm.items.first(where: { $0.barcode == code }) {
            result = .existing(existing)
            return
        }

        // 2. Otherwise look the product up in Open Food Facts.
        guard let token = auth.accessToken else { return }
        isLooking = true
        do {
            let resp: PantryBarcodeLookupResponse = try await APIClient.shared.post(
                "/pantry/barcode-lookup/",
                body: PantryBarcodeLookupRequest(barcode: code),
                token: token
            )
            isLooking = false
            if resp.found, let product = resp.product {
                result = .new(PantryItemPrefill(from: product))
            } else {
                result = .new(PantryItemPrefill(barcode: resp.barcode ?? code))
            }
        } catch {
            isLooking = false
            errorMessage = "Couldn't look up that barcode. Try again."
        }
    }

    private func handleText(_ raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result == nil, !isLooking, name.count >= 2 else { return }
        errorMessage = nil
        result = .new(PantryItemPrefill(name: name))
    }
}

// MARK: - VisionKit data scanner (barcodes + text)

/// Live scanner recognizing barcodes and text; taps are routed back to SwiftUI.
/// Tap-based (not auto-fire) so the user picks which barcode / which words —
/// packaging is covered in text, so guessing "the name" is unreliable.
struct PantryDataScannerView: UIViewControllerRepresentable {
    let onBarcode: (String) -> Void
    let onText: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [.ean13, .ean8, .upce, .code128, .code39]),
                .text(),
            ],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        // startScanning() is safe to call while already running.
        try? scanner.startScanning()
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: PantryDataScannerView
        init(_ parent: PantryDataScannerView) { self.parent = parent }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            switch item {
            case .barcode(let barcode):
                if let value = barcode.payloadStringValue { parent.onBarcode(value) }
            case .text(let text):
                parent.onText(text.transcript)
            @unknown default:
                break
            }
        }
    }
}
