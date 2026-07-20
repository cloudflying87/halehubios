import UIKit
import UniformTypeIdentifiers

/// Safari Share Extension: "Share → HaleHub" imports the current page into
/// HaleHub's recipe importer using the logged-in app's token (shared via the App
/// Group). When shared from Safari, a JavaScript preprocessing file (GetPageContent.js)
/// runs in the live tab and returns the fully-rendered DOM (post-JS) plus the URL —
/// matching the old Shortcut. That HTML is sent to the server so sites that block
/// the server's IP, or render their recipe via JS, still import. On success it
/// offers to open the app right on the imported recipe (halehub://recipes/<id>).
class ShareViewController: UIViewController {

    // Must match the app's App Group id, token key, and API base.
    private let appGroupId = "group.com.halefamily.halehubios"
    private let tokenKey = "halehub_access_token"
    private let importEndpoint = "https://flyhomemn.com/api/recipes/import/"

    private let card = UIView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let statusLabel = UILabel()
    private let buttonStack = UIStackView()
    private let openButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)
    private var importedRecipeId: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        extractPageContent { [weak self] html, url in
            guard let self else { return }
            let haveHTML = (html?.isEmpty == false)
            guard haveHTML || url != nil else {
                self.showResult("No recipe page found on this share.", recipeId: nil)
                return
            }
            guard
                let token = UserDefaults(suiteName: self.appGroupId)?.string(forKey: self.tokenKey),
                !token.isEmpty
            else {
                self.showResult("Open the HaleHub app and sign in first, then try again.", recipeId: nil)
                return
            }
            self.importRecipe(html: html, url: url, token: token)
        }
    }

    // MARK: - UI

    private func buildUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.25)

        card.backgroundColor = .systemBackground
        card.layer.cornerRadius = 18
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        spinner.startAnimating()

        statusLabel.text = "Importing recipe…"
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        openButton.setTitle("Open in HaleHub", for: .normal)
        openButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        openButton.addTarget(self, action: #selector(openTapped), for: .touchUpInside)

        doneButton.setTitle("Done", for: .normal)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        buttonStack.axis = .vertical
        buttonStack.spacing = 4
        buttonStack.addArrangedSubview(openButton)
        buttonStack.addArrangedSubview(doneButton)
        buttonStack.isHidden = true

        let stack = UIStackView(arrangedSubviews: [spinner, statusLabel, buttonStack])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 300),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 26),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22),
        ])
    }

    // MARK: - Pull page content out of the share payload

    /// Prefers the JavaScript preprocessing result (rendered DOM + URL from the live
    /// Safari tab). Falls back to a plain URL when shared from a non-Safari source.
    private func extractPageContent(completion: @escaping @MainActor (_ html: String?, _ url: String?) -> Void) {
        guard
            let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let providers = item.attachments
        else { Task { @MainActor in completion(nil, nil) }; return }

        let plistType = UTType.propertyList.identifier
        let urlType = UTType.url.identifier

        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(plistType) }) {
            provider.loadItem(forTypeIdentifier: plistType, options: nil) { loaded, _ in
                let results = (loaded as? NSDictionary)?[NSExtensionJavaScriptPreprocessingResultsKey] as? NSDictionary
                let html = results?["html"] as? String
                let url = results?["url"] as? String
                Task { @MainActor in completion(html, url) }
            }
            return
        }
        // Non-Safari share: just a URL. Server will fetch it (no rendered DOM).
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(urlType) }) {
            provider.loadItem(forTypeIdentifier: urlType, options: nil) { loaded, _ in
                let urlString = (loaded as? URL)?.absoluteString
                Task { @MainActor in completion(nil, urlString) }
            }
            return
        }
        Task { @MainActor in completion(nil, nil) }
    }

    // MARK: - Import

    private func importRecipe(html: String?, url: String?, token: String) {
        guard let endpoint = URL(string: importEndpoint) else {
            showResult("Something went wrong.", recipeId: nil); return
        }
        var payload: [String: Any] = [:]
        if let url { payload["url"] = url }
        if let html, !html.isEmpty { payload["html"] = html }
        guard !payload.isEmpty else {
            showResult("No recipe page found on this share.", recipeId: nil); return
        }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async {
                guard let self else { return }
                if error != nil {
                    self.showResult("Network error — please try again.", recipeId: nil)
                } else if code == 200 || code == 201 {
                    var title = "Recipe"
                    var id: String?
                    var isDuplicate = false
                    if
                        let data,
                        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    {
                        if let t = json["title"] as? String, !t.isEmpty { title = t }
                        id = json["id"] as? String
                        isDuplicate = (json["duplicate"] as? Bool) ?? false
                    }
                    let message = isDuplicate
                        ? "“\(title)” is already in HaleHub."
                        : "Added “\(title)” to HaleHub ✅"
                    self.showResult(message, recipeId: id)
                } else if code == 401 {
                    self.showResult("Open the HaleHub app and sign in first, then try again.", recipeId: nil)
                } else {
                    self.showResult("Couldn’t import this page. Open it in the app to add it manually.", recipeId: nil)
                }
            }
        }.resume()
    }

    // MARK: - Result + actions

    private func showResult(_ message: String, recipeId: String?) {
        spinner.stopAnimating()
        spinner.isHidden = true
        statusLabel.text = message
        importedRecipeId = recipeId
        openButton.isHidden = (recipeId == nil)   // only offer "Open" when we have the recipe
        buttonStack.isHidden = false
    }

    @objc private func openTapped() {
        guard let id = importedRecipeId, let url = URL(string: "halehub://recipes/\(id)") else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }
        // Handoff fallback: the app also reads this on next activation and
        // navigates to the recipe, in case extensionContext.open below doesn't
        // foreground the app for some reason.
        UserDefaults(suiteName: appGroupId)?.set(id, forKey: "halehub_pending_recipe_id")

        // Share Extensions run in their own process with no UIApplication —
        // NSExtensionContext.open is the supported way to hand a URL off to the
        // containing app. completeRequest must wait for open's completion —
        // firing it immediately after (fire-and-forget) can tear the extension
        // down before the system finishes the app-switch handoff.
        extensionContext?.open(url) { [weak self] success in
            if !success {
                NSLog("HaleHub ShareExtension: extensionContext.open failed for \(url)")
            }
            DispatchQueue.main.async {
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        }
    }

    @objc private func doneTapped() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
