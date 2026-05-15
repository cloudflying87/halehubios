import SwiftUI

struct AccountView: View {
    @EnvironmentObject var auth: AuthManager

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
                                .foregroundStyle(.accentColor)
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
                }

                // Calculators
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

                // Sign out
                Section {
                    Button(role: .destructive) {
                        auth.logout()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("More")
            .task {
                if auth.currentUser == nil {
                    await auth.fetchCurrentUser()
                }
            }
        }
    }

    var initials: String {
        guard let user = auth.currentUser else { return "?" }
        let parts = [user.firstName, user.lastName].filter { !$0.isEmpty }
        return parts.compactMap { $0.first.map(String.init) }.joined()
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
