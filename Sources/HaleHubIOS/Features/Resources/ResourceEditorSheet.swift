import SwiftUI

enum ResourceEditorMode {
    case create
    case edit(ResourceDetail)
}

struct ResourceEditorSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    let mode: ResourceEditorMode
    var onSave: (ResourceDetail) -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var content = ""
    @State private var contentType = "markdown"
    @State private var isPublic = true
    @State private var showPreview = false
    @State private var isSaving = false
    @State private var error: String?

    private var isCreate: Bool {
        if case .create = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Title", text: $title)
                    TextField("Short description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...3)
                    Toggle("Visible to everyone", isOn: $isPublic)
                }

                if isCreate {
                    Section("Type") {
                        Picker("Content Type", selection: $contentType) {
                            Text("Markdown").tag("markdown")
                            Text("React").tag("react")
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section {
                    if contentType == "markdown" {
                        Picker("", selection: $showPreview) {
                            Text("Write").tag(false)
                            Text("Preview").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    if contentType == "markdown" && showPreview {
                        ScrollView {
                            MarkdownContentView(content: content)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                        }
                        .frame(minHeight: 260)
                    } else {
                        TextEditor(text: $content)
                            .font(contentType == "react" ? .body.monospaced() : .body)
                            .frame(minHeight: 260)
                            .autocorrectionDisabled(contentType == "react")
                            .textInputAutocapitalization(contentType == "react" ? .never : .sentences)
                    }
                } header: {
                    Text(contentType == "markdown" ? "Markdown" : "React (JSX)")
                }

                if contentType == "react" {
                    Section {
                        Label("React components render on the web only. iOS shows source.",
                              systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.subheadline)
                    }
                }
            }
            .navigationTitle(isCreate ? "New Resource" : "Edit Resource")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .onAppear { hydrate() }
        }
    }

    private func hydrate() {
        guard case .edit(let r) = mode else { return }
        title = r.title
        description = r.description
        content = r.content
        contentType = r.contentType
        isPublic = r.isPublic
    }

    private func save() async {
        guard let token = auth.accessToken else { return }
        isSaving = true
        error = nil
        do {
            let saved: ResourceDetail
            switch mode {
            case .create:
                let draft = ResourceDraft(
                    title: title.trimmingCharacters(in: .whitespaces),
                    description: description.trimmingCharacters(in: .whitespaces),
                    content: content,
                    contentType: contentType,
                    isPublic: isPublic
                )
                saved = try await APIClient.shared.post("/resources/", body: draft, token: token)
            case .edit(let original):
                let patch = ResourcePatch(
                    title: title.trimmingCharacters(in: .whitespaces),
                    description: description.trimmingCharacters(in: .whitespaces),
                    content: content,
                    isPublic: isPublic
                )
                saved = try await APIClient.shared.patch("/resources/\(original.slug)/", body: patch, token: token)
            }
            onSave(saved)
            dismiss()
        } catch {
            self.error = error.localizedDescription
            isSaving = false
        }
    }
}
