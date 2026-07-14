import SwiftUI
@preconcurrency import AVFoundation

/// Scans a product barcode and opens the right editor:
///   1. a barcode already on a pantry item → that existing item (to restock/edit)
///   2. otherwise → a new-item form, prefilled from Open Food Facts if the
///      product is known, or blank-with-the-barcode if it isn't.
/// Reuses the shared `CameraPreviewWrapper` from the tote scanner.
struct PantryBarcodeScannerSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var vm: PantryViewModel
    let onSaved: (PantryItem) -> Void

    @State private var isScanning = true
    @State private var isLooking = false
    @State private var errorMessage: String?
    @State private var torchOn = false
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

    /// Common grocery symbologies. UPC-A is reported as EAN-13 by AVFoundation.
    private let barcodeTypes: [AVMetadataObject.ObjectType] =
        [.ean13, .ean8, .upce, .code128, .code39]

    var body: some View {
        NavigationStack {
            ZStack {
                CameraPreviewWrapper(
                    isScanning: $isScanning,
                    torchOn: $torchOn,
                    onCode: { code in
                        guard isScanning, !isLooking else { return }
                        Task { await handleScanned(barcode: code) }
                    },
                    codeTypes: barcodeTypes
                )
                .ignoresSafeArea()

                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white, lineWidth: 3)
                        .frame(width: 260, height: 150)
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
                        Text("Point at a product barcode")
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { torchOn.toggle() } label: {
                        Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .foregroundStyle(.white)
                    }
                }
            }
            .toolbarBackground(.clear, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            // Present the editor for whatever the scan resolved to. Resuming
            // scanning on dismiss lets the user cancel and scan another item.
            .sheet(item: $result, onDismiss: { isScanning = true }) { res in
                editor(for: res).environmentObject(auth)
            }
        }
    }

    @ViewBuilder
    private func editor(for res: ScanResult) -> some View {
        switch res {
        case .existing(let item):
            // Already in the pantry — open it to restock / edit.
            PantryItemEditSheet(item: item, vm: vm) { saved in
                onSaved(saved)
                dismiss()
            }
        case .new(let prefill):
            PantryItemEditSheet(item: nil, vm: vm, prefill: prefill) { saved in
                onSaved(saved)
                dismiss()
            }
        }
    }

    private func handleScanned(barcode: String) async {
        let code = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        isScanning = false
        errorMessage = nil

        // 1. Do we already have an item with this barcode? Open it directly —
        //    no network needed, and it works even for products Open Food Facts
        //    doesn't know (their barcode was saved when first added).
        if let existing = vm.items.first(where: { $0.barcode == code }) {
            result = .existing(existing)
            return
        }

        // 2. Otherwise look the product up in Open Food Facts.
        guard let token = auth.accessToken else { isScanning = true; return }
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
                // Unknown product — still let them add it with the code attached.
                result = .new(PantryItemPrefill(barcode: resp.barcode ?? code))
            }
        } catch {
            errorMessage = "Couldn't look up that barcode. Try again."
            isLooking = false
            try? await Task.sleep(for: .seconds(2))
            if result == nil { isScanning = true }
        }
    }
}
