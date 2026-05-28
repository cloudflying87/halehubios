import SwiftUI

// MARK: - Response types (request types live in Tote.swift)

private struct CreateCategoryResponse: Decodable, Sendable {
    let id: String
    let name: String
}

private struct CreateItemTypeResponse: Decodable, Sendable {
    let id: String
    let name: String
}

// MARK: - Sheet

struct AddToteItemSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @Binding var isPresented: Bool
    let toteId: String
    let categories: [ToteCategory]
    var onAdded: (ToteItem) -> Void

    // Mutable local copy of categories so new ones can be appended.
    @State private var localCategories: [ToteCategory] = []

    @State private var selectedCategory: ToteCategory?
    @State private var selectedItemType: ToteItemType?
    @State private var quantity = ""
    @State private var notes = ""
    @State private var isAdding = false
    @State private var error: String?

    // New category creation
    @State private var showNewCategoryAlert = false
    @State private var newCategoryName = ""
    @State private var isCreatingCategory = false

    // New item type creation
    @State private var showNewItemTypeAlert = false
    @State private var newItemTypeName = ""
    @State private var isCreatingItemType = false

    // Shared creation error
    @State private var createError: String?

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
                        ForEach(localCategories) { cat in
                            Text(cat.name).tag(cat as ToteCategory?)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .onChange(of: selectedCategory) { _, _ in
                        // Reset item type whenever category changes.
                        selectedItemType = nil
                    }

                    Button {
                        newCategoryName = ""
                        showNewCategoryAlert = true
                    } label: {
                        Label("New Category", systemImage: "plus.circle")
                            .foregroundStyle(Color.accentColor)
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

                    if selectedCategory != nil {
                        Button {
                            newItemTypeName = ""
                            showNewItemTypeAlert = true
                        } label: {
                            Label("New Item Type", systemImage: "plus.circle")
                                .foregroundStyle(Color.accentColor)
                        }
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
            .onAppear {
                localCategories = categories
            }
            // New category alert
            .alert("New Category", isPresented: $showNewCategoryAlert) {
                TextField("Category name", text: $newCategoryName)
                Button("Create") {
                    Task { await createCategory(token: auth.accessToken ?? "") }
                }
                .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel", role: .cancel) { newCategoryName = "" }
            } message: {
                Text("Enter a name for the new category.")
            }
            // New item type alert
            .alert("New Item Type", isPresented: $showNewItemTypeAlert) {
                TextField("Item type name", text: $newItemTypeName)
                Button("Create") {
                    Task { await createItemType(token: auth.accessToken ?? "") }
                }
                .disabled(newItemTypeName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel", role: .cancel) { newItemTypeName = "" }
            } message: {
                if let cat = selectedCategory {
                    Text("Enter a name for the new item type in \(cat.name).")
                } else {
                    Text("Enter a name for the new item type.")
                }
            }
            // Creation error alert
            .alert("Error", isPresented: .init(
                get: { createError != nil },
                set: { if !$0 { createError = nil } }
            )) {
                Button("OK") { createError = nil }
            } message: {
                Text(createError ?? "")
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

    // MARK: - Create category

    private func createCategory(token: String) async {
        let name = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isCreatingCategory = true
        do {
            let response: CreateCategoryResponse = try await APIClient.shared.post(
                "/totes/categories/", body: CreateCategoryRequest(name: name, order: nil), token: token
            )
            let newCat = ToteCategory(id: response.id, name: response.name, order: nil, isActive: nil, itemTypes: [])
            localCategories.append(newCat)
            localCategories.sort { $0.name < $1.name }
            selectedCategory = newCat
            selectedItemType = nil
            newCategoryName = ""
        } catch {
            createError = error.localizedDescription
        }
        isCreatingCategory = false
    }

    // MARK: - Create item type

    private func createItemType(token: String) async {
        guard let cat = selectedCategory else { return }
        let name = newItemTypeName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isCreatingItemType = true
        do {
            let response: CreateItemTypeResponse = try await APIClient.shared.post(
                "/totes/categories/\(cat.id)/item-types/",
                body: CreateItemTypeRequest(name: name, order: nil),
                token: token
            )
            let newType = ToteItemType(id: response.id, name: response.name, order: nil, isActive: nil)
            if let idx = localCategories.firstIndex(where: { $0.id == cat.id }) {
                let updated = ToteCategory(
                    id: cat.id,
                    name: cat.name,
                    order: cat.order,
                    isActive: cat.isActive,
                    itemTypes: (cat.itemTypes + [newType]).sorted { $0.name < $1.name }
                )
                localCategories[idx] = updated
                selectedCategory = updated
                selectedItemType = newType
            }
            newItemTypeName = ""
        } catch {
            createError = error.localizedDescription
        }
        isCreatingItemType = false
    }
}
