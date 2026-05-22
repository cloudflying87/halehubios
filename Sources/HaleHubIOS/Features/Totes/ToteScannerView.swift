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
    @State private var showCreate = false
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
            .sheet(isPresented: $showCreate, onDismiss: {
                // Resume scanning if user cancelled create without saving
                if unboundIdentifier != nil {
                    unboundIdentifier = nil
                    isScanning = true
                }
            }) {
                if let identifier = unboundIdentifier {
                    CreateToteSheet(
                        qrIdentifier: identifier,
                        onCreated: { newTote in
                            showCreate = false
                            unboundIdentifier = nil
                            dismiss()
                            onToteFound(newTote)
                        },
                        onCancel: {
                            showCreate = false
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
                // Unbound — offer to create a new tote with this identifier
                unboundIdentifier = response.qrCodeIdentifier ?? identifier
                showCreate = true
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
