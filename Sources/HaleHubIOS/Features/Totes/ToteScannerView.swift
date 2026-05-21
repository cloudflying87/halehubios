import SwiftUI
import AVFoundation

// MARK: - QR Scanner Sheet

struct ToteScannerSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    var onToteFound: (Tote) -> Void

    @State private var isScanning = true
    @State private var isLooking = false
    @State private var errorMessage: String?
    @State private var torchOn = false

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

                // Viewfinder overlay
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
                    Button {
                        torchOn.toggle()
                    } label: {
                        Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .foregroundStyle(.white)
                    }
                }
            }
            .toolbarBackground(.clear, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private func handleScanned(code: String) async {
        guard let token = auth.accessToken else { return }
        isScanning = false
        isLooking = true
        errorMessage = nil

        // Extract QR identifier from either format:
        // - halehub://tote/IDENTIFIER
        // - https://flyhomemn.com/lists/totes/scan/IDENTIFIER/
        // - raw IDENTIFIER string
        let identifier = extractIdentifier(from: code)

        do {
            let tote: Tote = try await APIClient.shared.get(
                "/totes/scan/\(identifier)/", token: token
            )
            dismiss()
            onToteFound(tote)
        } catch let err as APIError {
            errorMessage = err.errorDescription ?? "Tote not found. Try scanning again."
            isLooking = false
            // Re-enable scanning after a delay
            try? await Task.sleep(for: .seconds(2))
            isScanning = true
        } catch {
            errorMessage = "Couldn't look up tote. Check your connection."
            isLooking = false
            try? await Task.sleep(for: .seconds(2))
            isScanning = true
        }
    }

    private func extractIdentifier(from code: String) -> String {
        // halehub://tote/IDENTIFIER
        if let url = URL(string: code), url.scheme == "halehub", url.host == "tote" {
            return String(url.path.dropFirst())  // drop leading /
        }
        // https://flyhomemn.com/lists/totes/scan/IDENTIFIER/
        if let url = URL(string: code),
           let host = url.host, host.contains("flyhomemn"),
           url.pathComponents.count >= 2 {
            let last = url.pathComponents.last(where: { !$0.isEmpty && $0 != "/" }) ?? ""
            if !last.isEmpty { return last }
        }
        // Raw identifier
        return code.trimmingCharacters(in: .whitespacesAndNewlines)
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
        if isScanning {
            view.startScanning()
        } else {
            view.stopScanning()
        }
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

        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    func stopScanning() {
        captureSession?.stopRunning()
    }

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
