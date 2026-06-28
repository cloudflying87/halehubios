import SwiftUI

struct AccountView: View {
    @EnvironmentObject var auth: AuthManager
    @ObservedObject var notifVM: NotificationsViewModel
    @State private var tokenCopied = false

    var body: some View {
        NavigationStack {
            List {
                // User profile
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: 54, height: 54)
                            Text(initials)
                                .font(.title3.bold())
                                .foregroundStyle(Color.accentColor)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(auth.currentUser?.displayName ?? "—")
                                .font(.headline)
                            Text(auth.currentUser?.email ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let role = auth.currentUser?.role, !role.isEmpty {
                                Text(role.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.vertical, 6)

                    Button {
                        if let token = auth.accessToken {
                            UIPasteboard.general.string = token
                            tokenCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                tokenCopied = false
                            }
                        }
                    } label: {
                        Label(
                            tokenCopied ? "Copied!" : "Copy Shortcut Token",
                            systemImage: tokenCopied ? "checkmark.circle.fill" : "doc.on.clipboard"
                        )
                        .foregroundStyle(tokenCopied ? .green : Color.accentColor)
                    }
                }

                // Notifications
                Section {
                    NavigationLink(destination: NotificationsView()) {
                        HStack {
                            Label("Notifications", systemImage: "bell.fill")
                            Spacer()
                            if notifVM.unreadCount > 0 {
                                Text("\(notifVM.unreadCount)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.accentColor, in: Capsule())
                            }
                        }
                    }
                }

                // Features — each row only appears when the user has the matching permission
                let user = auth.currentUser

                // Finance — only visible with finance access (backend also 403s
                // /api/finance/* without it). Behind a biometric lock inside.
                if user?.can("finance") ?? false {
                    Section {
                        NavigationLink(destination: FinanceView()) {
                            CalculatorRow(icon: "🏦", title: "Finance", subtitle: "Net worth, loans & investments")
                        }
                    }
                }

                if user?.can("reading") ?? false ||
                   user?.can("qr")      ?? false ||
                   user?.can("letters") ?? false {
                    Section {
                        if user?.can("reading") ?? false {
                            NavigationLink(destination: ReadingView()) {
                                CalculatorRow(icon: "📖", title: "Reading Plan", subtitle: "Daily Bible reading progress")
                            }
                        }
                        if user?.can("qr") ?? false {
                            NavigationLink(destination: QRCodesView()) {
                                CalculatorRow(icon: "📷", title: "QR Codes", subtitle: "Generate & manage QR codes")
                            }
                        }
                        if user?.can("letters") ?? false {
                            NavigationLink(destination: ResourcesHubView()) {
                                CalculatorRow(icon: "📄", title: "Resources & Letters", subtitle: "Family guides and letters")
                            }
                        }
                    }
                }

                // Babysitters
                if user?.can("babysitters") ?? false {
                    Section {
                        NavigationLink(destination: BabysittersListView()) {
                            CalculatorRow(icon: "👶", title: "Babysitters", subtitle: "Hours, rates & pay reports")
                        }
                    }
                }

                // Jewelry
                if user?.can("jewelry") ?? false {
                    Section {
                        NavigationLink(destination: JewelryListView()) {
                            CalculatorRow(icon: "💍", title: "Jewelry", subtitle: "Catalog pieces, photos & value report")
                        }
                    }
                }

                // Calculators
                if user?.can("calculators") ?? false {
                    Section("Calculators") {
                        NavigationLink(destination: LoanCalculatorView()) {
                            CalculatorRow(icon: "💰", title: "Loan Calculator", subtitle: "Monthly payments & total interest")
                        }
                        NavigationLink(destination: CompoundInterestView()) {
                            CalculatorRow(icon: "📈", title: "Compound Interest", subtitle: "Investment growth over time")
                        }
                        NavigationLink(destination: TimeCalculatorView()) {
                            CalculatorRow(icon: "🕐", title: "Time Calculator", subtitle: "Add, subtract & convert times")
                        }
                    }
                }

                // Sign out
                Section {
                    Button(role: .destructive) {
                        auth.logout()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Section {
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
                    Text("HaleHub v\(version) (\(build))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle("More")
            .task {
                if auth.currentUser == nil { await auth.fetchCurrentUser() }
            }
        }
    }

    var initials: String {
        guard let user = auth.currentUser else { return "?" }
        return [user.firstName, user.lastName]
            .filter { !$0.isEmpty }
            .compactMap { $0.first.map(String.init) }
            .joined()
    }
}

struct CalculatorRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Text(icon)
                .font(.title2)
                .frame(width: 36, height: 36)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
