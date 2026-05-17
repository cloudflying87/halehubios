import SwiftUI

struct AddToteItemSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @Binding var isPresented: Bool
    let toteId: String
    let categories: [ToteCategory]
    var onAdded: (ToteItem) -> Void

    @State private var selectedCategory: ToteCategory?
    @State private var selectedItemType: ToteItemType?
    @State private var quantity = ""
    @State private var notes = ""
    @State private var isAdding = false
    @State private var error: String?

    /// Item types for the currently selected category.
    private var availableItemTypes: [ToteItemType] {
        selectedCategory?.itemTypes ?? []
    }

    private var canAdd: Bool {
        selectedCategory != nil && selectedItemType != nil && !isAdding
    }

    var body: some View {
        NavigationStack {
            Form {
                // Category picker
                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        Text("— Select —").tag(nil as ToteCategory?)
                        ForEach(categories) { cat in
                            Text(cat.name).tag(cat as ToteCategory?)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .onChange(of: selectedCategory) { _, _ in
                        // Reset item type whenever category changes.
                        selectedItemType = nil
                    }
                }

                // Item type picker — only meaningful once a category is chosen.
                Section("Item Type") {
                    if selectedCategory == nil {
                        Text("Select a category first")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else if availableItemTypes.isEmpty {
                        Text("No item types in this category")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        Picker("Item Type", selection: $selectedItemType) {
                            Text("— Select —").tag(nil as ToteItemType?)
                            ForEach(availableItemTypes) { type in
                                Text(type.name).tag(type as ToteItemType?)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }

                // Optional fields
                Section("Details (optional)") {
                    TextField("Quantity (e.g. 12 pairs, 3 boxes)", text: $quantity)
                        .autocorrectionDisabled()
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                // Inline error
                if let errorMsg = error {
                    Section {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(errorMsg)
                                .foregroundStyle(.red)
                                .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isAdding {
                        ProgressView()
                    } else {
                        Button("Add") {
                            Task { await addItem() }
                        }
                        .disabled(!canAdd)
                    }
                }
            }
        }
    }

    // MARK: - Add action

    private func addItem() async {
        guard let token = auth.accessToken,
              let category = selectedCategory,
              let itemType = selectedItemType else { return }

        isAdding = true
        error = nil

        let body = AddToteItemRequest(
            categoryId: category.id,
            itemTypeId: itemType.id,
            quantity: quantity.trimmingCharacters(in: .whitespaces),
            notes: notes.trimmingCharacters(in: .whitespaces)
        )

        do {
            let newItem: ToteItem = try await APIClient.shared.post(
                "/totes/\(toteId)/items/",
                body: body,
                token: token
            )
            onAdded(newItem)
            isPresented = false
        } catch {
            self.error = error.localizedDescription
        }

        isAdding = false
    }
}
