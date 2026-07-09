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

    // Shared with the Share Extension via an App Group so it can use this login.
    // Falls back to nil (no sharing) until the App Group capability is enabled.
    private let sharedDefaults = UserDefaults(suiteName: "group.com.halefamily.halehubios")

    var accessToken: String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }

    init() {
        isAuthenticated = accessToken != nil
        if let data = UserDefaults.standard.data(forKey: userKey),
           let user = try? JSONDecoder().decode(HaleUser.self, from: data) {
            currentUser = user
        }
        syncSharedToken()
    }

    /// Mirror the current access token into the App Group so the Share Extension
    /// can authenticate. Cleared on logout.
    private func syncSharedToken() {
        if let token = accessToken {
            sharedDefaults?.set(token, forKey: tokenKey)
        } else {
            sharedDefaults?.removeObject(forKey: tokenKey)
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
            syncSharedToken()
            await fetchCurrentUser()
        } catch let error as APIError {
            switch error {
            case .unauthorized:
                errorMessage = "Username or password is incorrect."
            default:
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Returns true if the current user was loaded. Callers use this to avoid a
    /// dead-end "Loading…" state when /auth/me/ can't be reached.
    @discardableResult
    func fetchCurrentUser() async -> Bool {
        guard let token = accessToken else { return false }
        if let user: HaleUser = try? await APIClient.shared.get("/auth/me/", token: token) {
            currentUser = user
            if let data = try? JSONEncoder().encode(user) {
                UserDefaults.standard.set(data, forKey: userKey)
            }
            return true
        }
        return false
    }

    func logout() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: refreshKey)
        UserDefaults.standard.removeObject(forKey: userKey)
        currentUser = nil
        isAuthenticated = false
        syncSharedToken()
    }
}

/// Per-app access pair returned in HaleUser.apps.
/// Backend rule: owners always get true/true; everyone else needs the
/// per-app can_view_/can_edit_ flag explicitly granted.
struct AppAccess: Codable, Sendable, Hashable {
    let view: Bool
    let edit: Bool

    static let none = AppAccess(view: false, edit: false)
}

struct HaleUser: Codable, Sendable {
    let id: Int
    let email: String
    let firstName: String
    let lastName: String
    let displayName: String
    let role: String

    let isOwner: Bool
    let isAdult: Bool

    // Raw flags — still here for code that reads a specific field.
    // Prefer `can(_:edit:)` for new code, which consults the `apps` map.
    let canViewFinances: Bool
    let canViewPaychecks: Bool
    let canEditVehicles: Bool
    let canViewVacations: Bool
    let canViewMusic: Bool
    let canEditMusic: Bool
    let canViewFlights: Bool
    let canEditFlights: Bool
    let canViewRecipes: Bool
    let canEditRecipes: Bool
    let canViewLists: Bool
    let canViewTotes: Bool
    let canViewReading: Bool
    let canViewLetters: Bool
    let canEditLetters: Bool
    let canViewWebsites: Bool
    let canEditWebsites: Bool
    let canViewQr: Bool
    let canViewCalculators: Bool
    let totesOnly: Bool
    /// Non-nil when this user account is linked to a babysitter record.
    let babysitterProfileId: String?

    /// Per-app {view, edit} map keyed by app key (recipes, totes, finance, …).
    /// This is the canonical source for "should iOS show tab X?" — prefer
    /// `user.can("recipes")` over poking at the raw flag fields.
    let apps: [String: AppAccess]

    var isBabysitterOnly: Bool {
        babysitterProfileId != nil && !can("babysitters")
    }

    /// Convenience accessor for `apps`. Returns false for unknown keys.
    func can(_ appKey: String, edit: Bool = false) -> Bool {
        guard let access = apps[appKey] else { return false }
        return edit ? access.edit : access.view
    }

    // Custom decoder so missing/older flag fields don't break login. Newly-
    // added fields default to false (sensible since the positive-list model
    // means "no info → no access" is the safe assumption).
    enum CodingKeys: String, CodingKey {
        case id, email, firstName, lastName, displayName, role
        case isOwner, isAdult
        case canViewFinances, canViewPaychecks
        case canEditVehicles, canViewVacations
        case canViewMusic, canEditMusic
        case canViewFlights, canEditFlights
        case canViewRecipes, canEditRecipes
        case canViewLists, canViewTotes, canViewReading
        case canViewLetters, canEditLetters
        case canViewWebsites, canEditWebsites
        case canViewQr, canViewCalculators
        case totesOnly, babysitterProfileId
        case apps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        email = try c.decode(String.self, forKey: .email)
        firstName = try c.decode(String.self, forKey: .firstName)
        lastName = try c.decode(String.self, forKey: .lastName)
        displayName = try c.decode(String.self, forKey: .displayName)
        role = try c.decode(String.self, forKey: .role)
        isOwner = (try? c.decode(Bool.self, forKey: .isOwner)) ?? (role == "owner")
        isAdult = (try? c.decode(Bool.self, forKey: .isAdult)) ?? (role == "owner" || role == "adult")

        func flag(_ key: CodingKeys, default value: Bool = false) -> Bool {
            (try? c.decode(Bool.self, forKey: key)) ?? value
        }

        canViewFinances    = flag(.canViewFinances)
        canViewPaychecks   = flag(.canViewPaychecks)
        canEditVehicles    = flag(.canEditVehicles)
        canViewVacations   = flag(.canViewVacations)
        canViewMusic       = flag(.canViewMusic)
        canEditMusic       = flag(.canEditMusic)
        canViewFlights     = flag(.canViewFlights)
        canEditFlights     = flag(.canEditFlights)
        canViewRecipes     = flag(.canViewRecipes, default: true)
        canEditRecipes     = flag(.canEditRecipes, default: true)
        canViewLists       = flag(.canViewLists,   default: true)
        canViewTotes       = flag(.canViewTotes,   default: true)
        canViewReading     = flag(.canViewReading, default: true)
        canViewLetters     = flag(.canViewLetters, default: true)
        canEditLetters     = flag(.canEditLetters)
        canViewWebsites    = flag(.canViewWebsites)
        canEditWebsites    = flag(.canEditWebsites)
        canViewQr          = flag(.canViewQr)
        canViewCalculators = flag(.canViewCalculators, default: true)
        totesOnly          = flag(.totesOnly)
        babysitterProfileId = try? c.decode(String.self, forKey: .babysitterProfileId)

        apps = (try? c.decode([String: AppAccess].self, forKey: .apps)) ?? [:]
    }
}

private struct LoginRequest: Encodable, Sendable {
    let username: String
    let password: String
}

struct LoginResponse: Decodable, Sendable {
    let access: String
    let refresh: String
}
