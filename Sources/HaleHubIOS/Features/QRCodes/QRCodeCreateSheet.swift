import SwiftUI

struct QRCodeCreateSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Binding var isPresented: Bool
    var onCreated: (QRCode) -> Void

    // MARK: - Common fields
    @State private var name = ""
    @State private var selectedType = "url"
    @State private var isDynamic = true

    // MARK: - URL fields
    @State private var urlValue = ""

    // MARK: - Text fields
    @State private var textValue = ""

    // MARK: - WiFi fields
    @State private var wifiSSID = ""
    @State private var wifiPassword = ""
    @State private var wifiSecurity = "WPA"
    @State private var wifiHidden = false

    // MARK: - Email fields
    @State private var emailAddress = ""
    @State private var emailSubject = ""
    @State private var emailBody = ""

    // MARK: - Phone fields
    @State private var phoneNumber = ""

    // MARK: - SMS fields
    @State private var smsPhone = ""
    @State private var smsMessage = ""

    // MARK: - State
    @State private var isCreating = false
    @State private var error: String?

    private let typeOptions: [(value: String, label: String, icon: String)] = [
        ("url",   "URL",   "link"),
        ("text",  "Text",  "text.alignleft"),
        ("wifi",  "Wi-Fi", "wifi"),
        ("email", "Email", "envelope.fill"),
        ("phone", "Phone", "phone.fill"),
        ("sms",   "SMS",   "message.fill"),
    ]

    private let wifiSecurityOptions = ["WPA", "WEP", "nopass"]

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Name + type
                Section("General") {
                    TextField("Name", text: $name)
                        .autocorrectionDisabled()

                    Picker("Type", selection: $selectedType) {
                        ForEach(typeOptions, id: \.value) { option in
                            Label(option.label, systemImage: option.icon)
                                .tag(option.value)
                        }
                    }

                    Toggle("Dynamic QR Code", isOn: $isDynamic)
                    if isDynamic {
                        Text("Dynamic codes let you change the destination later without reprinting.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: Type-specific fields
                switch selectedType {
                case "url":
                    Section("URL") {
                        TextField("https://example.com", text: $urlValue)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }

                case "text":
                    Section("Text") {
                        TextField("Enter your text…", text: $textValue, axis: .vertical)
                            .lineLimit(4, reservesSpace: true)
                    }

                case "wifi":
                    Section("Wi-Fi Network") {
                        TextField("Network Name (SSID)", text: $wifiSSID)
                            .autocorrectionDisabled()
                            .autocapitalization(.none)

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
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                        TextField("Subject (optional)", text: $emailSubject)
                        TextField("Body (optional)", text: $emailBody, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                    }

                case "phone":
                    Section("Phone") {
                        TextField("+1 (555) 000-0000", text: $phoneNumber)
                            .keyboardType(.phonePad)
                    }

                case "sms":
                    Section("SMS") {
                        TextField("+1 (555) 000-0000", text: $smsPhone)
                            .keyboardType(.phonePad)
                        TextField("Message (optional)", text: $smsMessage, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                    }

                default:
                    EmptyView()
                }

                // MARK: Error
                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("New QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await create() }
                    }
                    .disabled(!isFormValid || isCreating)
                    .overlay {
                        if isCreating {
                            ProgressView().scaleEffect(0.8)
                        }
                    }
                }
            }
            .interactiveDismissDisabled(isCreating)
        }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch selectedType {
        case "url":   return !urlValue.trimmingCharacters(in: .whitespaces).isEmpty
        case "text":  return !textValue.trimmingCharacters(in: .whitespaces).isEmpty
        case "wifi":  return !wifiSSID.trimmingCharacters(in: .whitespaces).isEmpty
        case "email": return !emailAddress.trimmingCharacters(in: .whitespaces).isEmpty
        case "phone": return !phoneNumber.trimmingCharacters(in: .whitespaces).isEmpty
        case "sms":   return !smsPhone.trimmingCharacters(in: .whitespaces).isEmpty
        default:      return false
        }
    }

    // MARK: - Build content data

    private func buildContentData() -> QRContentData {
        switch selectedType {
        case "url":
            return QRContentData(url: urlValue.trimmingCharacters(in: .whitespaces))

        case "text":
            return QRContentData(text: textValue.trimmingCharacters(in: .whitespaces))

        case "wifi":
            return QRContentData(
                ssid: wifiSSID.trimmingCharacters(in: .whitespaces),
                password: wifiSecurity == "nopass" ? nil : wifiPassword,
                security: wifiSecurity,
                hidden: wifiHidden
            )

        case "email":
            return QRContentData(
                email: emailAddress.trimmingCharacters(in: .whitespaces),
                subject: emailSubject.isEmpty ? nil : emailSubject,
                body: emailBody.isEmpty ? nil : emailBody
            )

        case "phone":
            return QRContentData(phone: phoneNumber.trimmingCharacters(in: .whitespaces))

        case "sms":
            return QRContentData(
                phone: smsPhone.trimmingCharacters(in: .whitespaces),
                message: smsMessage.isEmpty ? nil : smsMessage
            )

        default:
            return QRContentData()
        }
    }

    // MARK: - Create

    private func create() async {
        guard let token = auth.accessToken else {
            error = "Not authenticated."
            return
        }
        isCreating = true
        error = nil

        let request = CreateQRCodeRequest(
            name: name.trimmingCharacters(in: .whitespaces),
            qrType: selectedType,
            isDynamic: isDynamic,
            contentData: buildContentData()
        )

        do {
            let newCode: QRCode = try await APIClient.shared.post(
                "/qr-codes/create/", body: request, token: token
            )
            onCreated(newCode)
            isPresented = false
        } catch {
            self.error = error.localizedDescription
        }
        isCreating = false
    }
}
