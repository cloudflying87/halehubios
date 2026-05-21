import SwiftUI

struct QRCodeEditSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    let qrCode: QRCode
    var onSaved: (QRCode) -> Void

    @State private var name: String
    @State private var isActive: Bool

    // Per-type editable fields (mirrors QRCodeCreateSheet)
    @State private var urlValue: String
    @State private var textValue: String
    @State private var wifiSSID: String
    @State private var wifiPassword: String
    @State private var wifiSecurity: String
    @State private var wifiHidden: Bool
    @State private var emailAddress: String
    @State private var emailSubject: String
    @State private var emailBody: String
    @State private var phoneNumber: String
    @State private var smsPhone: String
    @State private var smsMessage: String

    @State private var isSaving = false
    @State private var error: String?

    init(qrCode: QRCode, onSaved: @escaping (QRCode) -> Void) {
        self.qrCode = qrCode
        self.onSaved = onSaved
        let d = qrCode.contentData
        _name = State(initialValue: qrCode.name)
        _isActive = State(initialValue: qrCode.isActive)
        _urlValue = State(initialValue: d.url ?? "")
        _textValue = State(initialValue: d.text ?? "")
        _wifiSSID = State(initialValue: d.ssid ?? "")
        _wifiPassword = State(initialValue: d.password ?? "")
        _wifiSecurity = State(initialValue: d.security ?? "WPA")
        _wifiHidden = State(initialValue: d.hidden ?? false)
        _emailAddress = State(initialValue: d.email ?? "")
        _emailSubject = State(initialValue: d.subject ?? "")
        _emailBody = State(initialValue: d.body ?? "")
        _phoneNumber = State(initialValue: d.phone ?? "")
        _smsPhone = State(initialValue: d.phone ?? "")
        _smsMessage = State(initialValue: d.message ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    TextField("Name", text: $name).autocorrectionDisabled()
                    Toggle("Active", isOn: $isActive)
                    if qrCode.isDynamic {
                        Text("Dynamic — you can change where this points without reprinting.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Label("Static — saving will regenerate the QR image. Re-print any distributed copies.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }

                switch qrCode.qrType {
                case "url":
                    Section("URL") {
                        TextField("https://example.com", text: $urlValue)
                            .keyboardType(.URL).autocapitalization(.none).autocorrectionDisabled()
                    }
                case "text":
                    Section("Text") {
                        TextField("Your text…", text: $textValue, axis: .vertical)
                            .lineLimit(4, reservesSpace: true)
                    }
                case "wifi":
                    Section("Wi-Fi Network") {
                        TextField("Network Name (SSID)", text: $wifiSSID)
                            .autocorrectionDisabled().autocapitalization(.none)
                        Picker("Security", selection: $wifiSecurity) {
                            Text("WPA / WPA2").tag("WPA")
                            Text("WEP").tag("WEP")
                            Text("None").tag("nopass")
                        }
                        if wifiSecurity != "nopass" {
                            SecureField("Password", text: $wifiPassword)
                        }
                        Toggle("Hidden Network", isOn: $wifiHidden)
                    }
                case "email":
                    Section("Email") {
                        TextField("address@example.com", text: $emailAddress)
                            .keyboardType(.emailAddress).autocapitalization(.none).autocorrectionDisabled()
                        TextField("Subject (optional)", text: $emailSubject)
                        TextField("Body (optional)", text: $emailBody, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                    }
                case "phone":
                    Section("Phone") {
                        TextField("+1 (555) 000-0000", text: $phoneNumber).keyboardType(.phonePad)
                    }
                case "sms":
                    Section("SMS") {
                        TextField("+1 (555) 000-0000", text: $smsPhone).keyboardType(.phonePad)
                        TextField("Message (optional)", text: $smsMessage, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                    }
                default: EmptyView()
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.subheadline)
                    }
                }
            }
            .navigationTitle("Edit QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func buildContentData() -> QRContentData {
        switch qrCode.qrType {
        case "url":   return QRContentData(url: urlValue.trimmingCharacters(in: .whitespaces))
        case "text":  return QRContentData(text: textValue.trimmingCharacters(in: .whitespaces))
        case "wifi":  return QRContentData(ssid: wifiSSID, password: wifiSecurity == "nopass" ? nil : wifiPassword, security: wifiSecurity, hidden: wifiHidden)
        case "email": return QRContentData(email: emailAddress, subject: emailSubject.isEmpty ? nil : emailSubject, body: emailBody.isEmpty ? nil : emailBody)
        case "phone": return QRContentData(phone: phoneNumber)
        case "sms":   return QRContentData(phone: smsPhone, message: smsMessage.isEmpty ? nil : smsMessage)
        default:      return qrCode.contentData
        }
    }

    private func save() async {
        guard let token = auth.accessToken else { return }
        isSaving = true
        error = nil
        let body = UpdateQRCodeRequest(
            name: name.trimmingCharacters(in: .whitespaces),
            isActive: isActive,
            contentData: buildContentData()
        )
        do {
            let updated: QRCode = try await APIClient.shared.patch(
                "/qr-codes/\(qrCode.id)/update/", body: body, token: token
            )
            onSaved(updated)
            dismiss()
        } catch {
            self.error = error.localizedDescription
            isSaving = false
        }
    }
}
