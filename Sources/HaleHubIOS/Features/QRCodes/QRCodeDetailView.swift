import SwiftUI

struct QRCodeDetailView: View {
    @EnvironmentObject var auth: AuthManager
    let qrCode: QRCode

    @State private var showShareSheet = false
    @State private var copiedText: String?
    @State private var showCopiedToast = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                // MARK: QR Image
                qrImageSection

                // MARK: Header info
                VStack(spacing: 8) {
                    Text(qrCode.name)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    HStack(spacing: 8) {
                        TypeBadge(qrType: qrCode.qrType)

                        Text(qrCode.isDynamic ? "Dynamic" : "Static")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                (qrCode.isDynamic ? Color.blue : Color.gray).opacity(0.12),
                                in: Capsule()
                            )
                            .foregroundStyle(qrCode.isDynamic ? Color.blue : Color.secondary)

                        if !qrCode.isActive {
                            Text("INACTIVE")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.12), in: Capsule())
                                .foregroundStyle(Color.red)
                        }
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "viewfinder")
                        Text("\(qrCode.scanCount) scan\(qrCode.scanCount == 1 ? "" : "s")")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                // MARK: Content data
                contentDataSection

                // MARK: Actions
                actionButtons

                // MARK: Metadata
                metadataSection
            }
            .padding()
        }
        .navigationTitle("QR Code")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                copiedToast
            }
        }
    }

    // MARK: - QR Image Section

    @ViewBuilder
    private var qrImageSection: some View {
        if let urlString = qrCode.qrImageUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray6))
                            .frame(width: 240, height: 240)
                        ProgressView()
                    }
                case .success(let image):
                    image
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 240, height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                case .failure:
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray6))
                            .frame(width: 240, height: 240)
                        VStack(spacing: 8) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("Image unavailable")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                @unknown default:
                    EmptyView()
                }
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
                    .frame(width: 240, height: 240)
                Image(systemName: "qrcode")
                    .font(.system(size: 64))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Content Data Section

    @ViewBuilder
    private var contentDataSection: some View {
        let data = qrCode.contentData

        GroupBox("Content") {
            switch qrCode.qrType {
            case "url":
                if let url = data.url {
                    ContentRow(label: "URL", value: url, icon: "link")
                }

            case "text":
                if let text = data.text {
                    ContentRow(label: "Text", value: text, icon: "text.alignleft")
                }

            case "wifi":
                VStack(alignment: .leading, spacing: 8) {
                    if let ssid = data.ssid {
                        ContentRow(label: "Network (SSID)", value: ssid, icon: "wifi")
                    }
                    if let security = data.security {
                        ContentRow(label: "Security", value: security.uppercased(), icon: "lock.fill")
                    }
                    if let password = data.password {
                        ContentRow(label: "Password", value: password, icon: "key.fill", isPassword: true)
                    }
                    if let hidden = data.hidden, hidden {
                        HStack(spacing: 6) {
                            Image(systemName: "eye.slash")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text("Hidden network")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

            case "email":
                VStack(alignment: .leading, spacing: 8) {
                    if let email = data.email {
                        ContentRow(label: "To", value: email, icon: "envelope.fill")
                    }
                    if let subject = data.subject, !subject.isEmpty {
                        ContentRow(label: "Subject", value: subject, icon: "text.cursor")
                    }
                    if let body = data.body, !body.isEmpty {
                        ContentRow(label: "Body", value: body, icon: "text.bubble")
                    }
                }

            case "phone":
                if let phone = data.phone {
                    ContentRow(label: "Phone", value: phone, icon: "phone.fill")
                }

            case "sms":
                VStack(alignment: .leading, spacing: 8) {
                    if let phone = data.phone {
                        ContentRow(label: "To", value: phone, icon: "phone.fill")
                    }
                    if let message = data.message, !message.isEmpty {
                        ContentRow(label: "Message", value: message, icon: "message.fill")
                    }
                }

            default:
                Text("No content details available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Copy button — type-specific label
            if let copyValue = primaryCopyValue {
                Button {
                    UIPasteboard.general.string = copyValue
                    showCopy(text: copyLabelText)
                } label: {
                    Label(copyLabelText, systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            // Share QR image URL
            if let urlString = qrCode.qrImageUrl {
                ShareLink(item: urlString) {
                    Label("Share QR Image", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        GroupBox("Details") {
            VStack(alignment: .leading, spacing: 8) {
                ContentRow(label: "Short Code", value: qrCode.shortCode, icon: "number")
                ContentRow(
                    label: "Created",
                    value: qrCode.createdAt.formatted(.dateTime.month(.wide).day().year()),
                    icon: "calendar"
                )
            }
        }
    }

    // MARK: - Copied Toast

    private var copiedToast: some View {
        Text(copiedText ?? "Copied!")
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 4)
            .padding(.bottom, 32)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Helpers

    private var primaryCopyValue: String? {
        let data = qrCode.contentData
        switch qrCode.qrType {
        case "url":   return data.url
        case "text":  return data.text
        case "wifi":  return data.password
        case "email": return data.email
        case "phone": return data.phone
        case "sms":   return data.phone
        default:      return nil
        }
    }

    private var copyLabelText: String {
        switch qrCode.qrType {
        case "url":   return "Copy URL"
        case "wifi":  return "Copy Wi-Fi Password"
        case "email": return "Copy Email Address"
        case "phone": return "Copy Phone Number"
        case "sms":   return "Copy Phone Number"
        default:      return "Copy Text"
        }
    }

    private func showCopy(text: String) {
        copiedText = text.replacingOccurrences(of: "Copy ", with: "") + " Copied"
        withAnimation(.spring(duration: 0.3)) { showCopiedToast = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.3)) { showCopiedToast = false }
        }
    }
}

// MARK: - Content Row

private struct ContentRow: View {
    let label: String
    let value: String
    let icon: String
    var isPassword: Bool = false

    @State private var isRevealed = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isPassword && !isRevealed {
                    HStack(spacing: 8) {
                        Text(String(repeating: "•", count: min(value.count, 12)))
                            .font(.subheadline.monospaced())
                        Button("Show") { isRevealed = true }
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                            .buttonStyle(.plain)
                    }
                } else {
                    Text(value)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }
            }

            Spacer()
        }
    }
}
