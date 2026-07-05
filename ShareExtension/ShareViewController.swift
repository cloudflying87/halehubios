import UIKit
import UniformTypeIdentifiers

/// Safari Share Extension: "Share → HaleHub" sends the current page URL straight
/// to HaleHub's recipe importer using the logged-in app's token (shared via the
/// App Group). No review step — it imports and reports success.
class ShareViewController: UIViewController {

    // Must match the app's App Group id, token key, and API base.
    private let appGroupId = "group.com.halefamily.halehubios"
    private let tokenKey = "halehub_access_token"
    private let importEndpoint = "https://flyhomemn.com/api/recipes/import/"

    private let card = UIView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        extractURL { [weak self] url in
            guard let self else { return }
            guard let url else {
                self.finish(success: false, message: "No recipe link found on this page.")
                return
            }
            guard
                let token = UserDefaults(suiteName: self.appGroupId)?.string(forKey: self.tokenKey),
                !token.isEmpty
            else {
                self.finish(success: false, message: "Open the HaleHub app and sign in first, then try again.")
                return
            }
            self.importRecipe(pageURL: url, token: token)
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
        spinner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(spinner)

        statusLabel.text = "Importing recipe…"
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 300),
            spinner.topAnchor.constraint(equalTo: card.topAnchor, constant: 30),
            spinner.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 18),
            statusLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            statusLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
            statusLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -30),
        ])
    }

    // MARK: - Pull the URL out of the share payload

    private func extractURL(completion: @escaping (URL?) -> Void) {
        guard
            let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let providers = item.attachments
        else { completion(nil); return }

        let urlType = UTType.url.identifier
        let textType = UTType.plainText.identifier

        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(urlType) }) {
            provider.loadItem(forTypeIdentifier: urlType, options: nil) { data, _ in
                DispatchQueue.main.async { completion(data as? URL) }
            }
            return
        }
        // Some apps share the link as plain text instead of a URL attachment.
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(textType) }) {
            provider.loadItem(forTypeIdentifier: textType, options: nil) { data, _ in
                let url = (data as? String).flatMap {
                    URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                DispatchQueue.main.async { completion(url) }
            }
            return
        }
        completion(nil)
    }

    // MARK: - Import

    private func importRecipe(pageURL: URL, token: String) {
        guard let endpoint = URL(string: importEndpoint) else {
            finish(success: false, message: "Something went wrong."); return
        }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["url": pageURL.absoluteString])

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async {
                guard let self else { return }
                if error != nil {
                    self.finish(success: false, message: "Network error — please try again.")
                } else if code == 200 || code == 201 {
                    var title = "Recipe"
                    if
                        let data,
                        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                        let t = json["title"] as? String, !t.isEmpty
                    { title = t }
                    self.finish(success: true, message: "Added “\(title)” to HaleHub ✅")
                } else if code == 401 {
                    self.finish(success: false, message: "Open the HaleHub app and sign in first, then try again.")
                } else {
                    self.finish(success: false, message: "Couldn’t import this page. Open it in the app to add it manually.")
                }
            }
        }.resume()
    }

    private func finish(success: Bool, message: String) {
        spinner.stopAnimating()
        spinner.isHidden = true
        statusLabel.text = message
        DispatchQueue.main.asyncAfter(deadline: .now() + (success ? 1.2 : 2.2)) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
