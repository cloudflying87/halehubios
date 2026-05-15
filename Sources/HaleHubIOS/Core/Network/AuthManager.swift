import Foundation

@MainActor
class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let tokenKey = "halehub_access_token"
    private let refreshKey = "halehub_refresh_token"

    @Published var currentUser: HaleUser?

    private let userKey = "halehub_user"

    var accessToken: String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }

    init() {
        isAuthenticated = accessToken != nil
        if let data = UserDefaults.standard.data(forKey: userKey),
           let user = try? JSONDecoder().decode(HaleUser.self, from: data) {
            currentUser = user
        }
    }

    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let response: LoginResponse = try await APIClient.shared.post(
                "/auth/login/",
                body: LoginRequest(username: email, password: password),
                token: nil
            )
            UserDefaults.standard.set(response.access, forKey: tokenKey)
            UserDefaults.standard.set(response.refresh, forKey: refreshKey)
            isAuthenticated = true
            await fetchCurrentUser()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func fetchCurrentUser() async {
        guard let token = accessToken else { return }
        if let user: HaleUser = try? await APIClient.shared.get("/auth/me/", token: token) {
            currentUser = user
            if let data = try? JSONEncoder().encode(user) {
                UserDefaults.standard.set(data, forKey: userKey)
            }
        }
    }

    func logout() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: refreshKey)
        UserDefaults.standard.removeObject(forKey: userKey)
        currentUser = nil
        isAuthenticated = false
    }
}

struct HaleUser: Codable {
    let id: Int
    let email: String
    let firstName: String
    let lastName: String
    let displayName: String
    let role: String
}

private struct LoginRequest: Encodable {
    let username: String
    let password: String
}

struct LoginResponse: Decodable {
    let access: String
    let refresh: String
}
