import SwiftUI
@preconcurrency import AVFoundation

/// Scans a product barcode, looks it up via the backend (Open Food Facts), and
/// hands the result to the pantry edit sheet prefilled. Reuses the shared
/// `CameraPreviewWrapper` from the tote scanner, but with barcode symbologies.
struct PantryBarcodeScannerSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    let locations: [PantryLocation]
    let onSaved: (PantryItem) -> Void

    @State private var isScanning = true
    @State private var isLooking = false
    @State private var errorMessage: String?
    @State private var torchOn = false
    @State private var prefill: PantryItemPrefill?

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
            // Present the edit sheet once we have a prefill; dismiss the scanner
            // when the user finishes adding the item.
            .sheet(item: Binding(
                get: { prefill.map { PrefillBox(value: $0) } },
                set: { if $0 == nil { prefill = nil; isScanning = true } }
            )) { box in
                PantryItemEditSheet(
                    item: nil,
                    locations: locations,
                    prefill: box.value
                ) { saved in
                    onSaved(saved)
                    dismiss()
                }
                .environmentObject(auth)
            }
        }
    }

    private func handleScanned(barcode: String) async {
        guard let token = auth.accessToken else { return }
        let code = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        isScanning = false
        isLooking = true
        errorMessage = nil

        do {
            let resp: PantryBarcodeLookupResponse = try await APIClient.shared.post(
                "/pantry/barcode-lookup/",
                body: PantryBarcodeLookupRequest(barcode: code),
                token: token
            )
            isLooking = false
            if resp.found, let product = resp.product {
                prefill = PantryItemPrefill(from: product)
            } else {
                // Unknown product — still let them add it with the code attached.
                prefill = PantryItemPrefill(barcode: resp.barcode ?? code)
            }
        } catch {
            errorMessage = "Couldn't look up that barcode. Try again."
            isLooking = false
            try? await Task.sleep(for: .seconds(2))
            if prefill == nil { isScanning = true }
        }
    }
}

/// `sheet(item:)` needs an Identifiable; wrap the non-Identifiable prefill.
private struct PrefillBox: Identifiable {
    let id = UUID()
    let value: PantryItemPrefill
}
