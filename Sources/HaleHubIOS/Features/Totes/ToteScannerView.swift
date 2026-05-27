import SwiftUI
@preconcurrency import AVFoundation

// MARK: - QR Scanner Sheet

struct ToteScannerSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    var onToteFound: (Tote) -> Void

    @State private var isScanning = true
    @State private var isLooking = false
    @State private var errorMessage: String?
    @State private var torchOn = false
    @State private var showLink = false
    @State private var unboundIdentifier: String?

    var body: some View {
        NavigationStack {
            ZStack {
                CameraPreviewWrapper(
                    isScanning: $isScanning,
                    torchOn: $torchOn,
                    onCode: { code in
                        guard isScanning, !isLooking else { return }
                        Task { await handleScanned(code: code) }
                    }
                )
                .ignoresSafeArea()

                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white, lineWidth: 3)
                        .frame(width: 240, height: 240)
                    Spacer()
                    if isLooking {
                        HStack(spacing: 8) {
                            ProgressView().tint(.white)
                            Text("Looking up tote…").foregroundStyle(.white)
                        }
                        .padding(.bottom, 40)
                    } else if let err = errorMessage {
                        Text(err)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 40)
                    } else {
                        Text("Point at a tote QR code")
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Scan Tote")
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
            .sheet(isPresented: $showLink, onDismiss: {
                // Resume scanning if the user backed out without linking/creating
                if unboundIdentifier != nil {
                    unboundIdentifier = nil
                    isScanning = true
                }
            }) {
                if let identifier = unboundIdentifier {
                    LinkToteSheet(
                        qrIdentifier: identifier,
                        // Both linking an existing tote and creating a new one
                        // end the same way: close everything and surface the tote.
                        onResolved: { tote in
                            showLink = false
                            unboundIdentifier = nil
                            dismiss()
                            onToteFound(tote)
                        },
                        onCancel: {
                            showLink = false
                            unboundIdentifier = nil
                            isScanning = true
                        }
                    )
                    .environmentObject(auth)
                }
            }
        }
    }

    private func handleScanned(code: String) async {
        guard let token = auth.accessToken else { return }
        isScanning = false
        isLooking = true
        errorMessage = nil

        let identifier = extractToteIdentifier(from: code)

        do {
            let response: ToteScanResponse = try await APIClient.shared.get(
                "/totes/scan/\(identifier)/", token: token
            )
            isLooking = false
            if response.bound, let tote = response.asTote() {
                dismiss()
                onToteFound(tote)
            } else {
                // Unbound — offer to link this code to an existing tote or
                // create a new one.
                unboundIdentifier = response.qrCodeIdentifier ?? identifier
                showLink = true
            }
        } catch let err as APIError {
            errorMessage = err.errorDescription ?? "Tote not found. Try scanning again."
            isLooking = false
            try? await Task.sleep(for: .seconds(2))
            isScanning = true
        } catch {
            errorMessage = "Couldn't look up tote. Check your connection."
            isLooking = false
            try? await Task.sleep(for: .seconds(2))
            isScanning = true
        }
    }

    private func extractToteIdentifier(from code: String) -> String {
        if let url = URL(string: code), url.scheme == "halehub", url.host == "tote" {
            return String(url.path.dropFirst())
        }
        if let url = URL(string: code),
           let host = url.host, host.contains("flyhomemn") {
            let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            // /lists/totes/scan/IDENTIFIER/
            if parts.count >= 4, parts[0] == "lists", parts[1] == "totes", parts[2] == "scan" {
                return parts[3].uppercased()
            }
        }
        return code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

// MARK: - Link / Create Sheet for an unbound QR code

/// Shown when a scanned QR label isn't linked to any tote yet. Lets the user
/// either link it to an existing tote (the common case when a printed label
/// lost its association) or create a brand-new tote with the code.
struct LinkToteSheet: View {
    @EnvironmentObject var auth: AuthManager
    let qrIdentifier: String
    var onResolved: (Tote) -> Void   // linked to existing OR created new
    var onCancel: () -> Void

    @StateObject private var vm = TotesViewModel()
    @State private var linkingId: String?
    @State private var error: String?
    @State private var showCreate = false

    // Only totes without a QR code — re-linking one that already has a (wrong)
    // code is handled from its detail page, not here.
    private var unlinkedTotes: [Tote] {
        vm.totes.filter { ($0.qrCodeIdentifier ?? "").isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "qrcode")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("New QR Code")
                                .font(.subheadline.weight(.medium))
                            Text(qrIdentifier)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("This code isn't linked to a tote yet.")
                }

                // Primary action — most scanned labels are for new totes.
                Section {
                    Button {
                        showCreate = true
                    } label: {
                        Label("Create a new tote", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .listRowBackground(Color.clear)
                    .disabled(linkingId != nil)
                }

                // Secondary action — only when a tote lost its code.
                Section {
                    DisclosureGroup("This tote already exists — link instead") {
                        if vm.isLoading {
                            HStack { ProgressView(); Text("Loading totes…").foregroundStyle(.secondary) }
                        } else if unlinkedTotes.isEmpty {
                            Text("No unlinked totes — every tote already has a QR code. To re-link a tote with the wrong code, use the Change button on its detail page.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(unlinkedTotes) { tote in
                                Button {
                                    Task { await link(tote) }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(tote.name).foregroundStyle(.primary)
                                            Text(tote.displayLocation)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if linkingId == tote.id {
                                            ProgressView()
                                        } else {
                                            Image(systemName: "link")
                                                .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                }
                                .disabled(linkingId != nil)
                            }
                        }
                    }
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.subheadline)
                    }
                }
            }
            .navigationTitle("New Tote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                        .disabled(linkingId != nil)
                }
            }
            .task {
                if let token = auth.accessToken { await vm.load(token: token) }
            }
            .sheet(isPresented: $showCreate) {
                CreateToteSheet(
                    qrIdentifier: qrIdentifier,
                    onCreated: { newTote in
                        showCreate = false
                        onResolved(newTote)
                    },
                    onCancel: { showCreate = false }
                )
                .environmentObject(auth)
            }
        }
    }

    private func link(_ tote: Tote) async {
        guard let token = auth.accessToken else { return }
        linkingId = tote.id
        error = nil
        do {
            let body = AssociateQRRequest(qrCodeIdentifier: qrIdentifier)
            let updated: Tote = try await APIClient.shared.post(
                "/totes/\(tote.id)/associate-qr/", body: body, token: token
            )
            onResolved(updated)
        } catch {
            self.error = error.localizedDescription
            linkingId = nil
        }
    }
}

// MARK: - AVFoundation Camera Preview

struct CameraPreviewWrapper: UIViewRepresentable {
    @Binding var isScanning: Bool
    @Binding var torchOn: Bool
    var onCode: (String) -> Void

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.onCode = onCode
        return view
    }

    func updateUIView(_ view: CameraPreviewView, context: Context) {
        if isScanning { view.startScanning() } else { view.stopScanning() }
        view.setTorch(on: torchOn)
    }
}

final class CameraPreviewView: UIView {
    var onCode: ((String) -> Void)?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }

    func startScanning() {
        if captureSession != nil { captureSession?.startRunning(); return }

        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = bounds
        layer.insertSublayer(preview, at: 0)
        previewLayer = preview
        captureSession = session

        // AVCaptureSession.startRunning() must be called off the main thread.
        // @preconcurrency import AVFoundation suppresses the Sendable warning here.
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    func stopScanning() { captureSession?.stopRunning() }

    func setTorch(on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }
}

extension CameraPreviewView: @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput objects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let obj = objects.first as? AVMetadataMachineReadableCodeObject,
              let code = obj.stringValue else { return }
        onCode?(code)
    }
}
