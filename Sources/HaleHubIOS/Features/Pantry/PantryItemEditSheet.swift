import SwiftUI

/// Create (item == nil) or edit an existing pantry item.
/// Calls `onSave` with the server's saved copy so the list can upsert it.
struct PantryItemEditSheet: View {
    let item: PantryItem?
    @ObservedObject var vm: PantryViewModel
    /// Optional values from a barcode scan, used only when creating (item == nil).
    var prefill: PantryItemPrefill? = nil
    let onSave: (PantryItem) -> Void

    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var brand = ""
    @State private var quantityText = ""
    @State private var unit = ""
    @State private var barcode = ""
    @State private var selectedCategoryId: String = ""   // "" == uncategorized
    @State private var selectedLocationId: String = ""   // "" == no PantryLocation
    @State private var hasExpiration = false
    @State private var expirationDate = Date()
    @State private var isLow = false
    @State private var autoAddToList = false

    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isEditing: Bool { item != nil }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Name", text: $name)
                    TextField("Brand (optional)", text: $brand)
                }

                Section("Quantity") {
                    TextField("Amount, e.g. \"16 oz\" or \"2\"", text: $quantityText)
                    TextField("Unit (optional)", text: $unit)
                }

                Section("Category") {
                    PantryTaxonPicker(
                        kind: .category,
                        taxa: vm.categories,
                        selectedId: $selectedCategoryId,
                        onCreate: { name, icon in
                            await vm.createTaxon(kind: .category, name: name, icon: icon,
                                                 token: auth.accessToken ?? "")
                        }
                    )
                }

                Section("Location") {
                    PantryTaxonPicker(
                        kind: .location,
                        taxa: vm.locations,
                        selectedId: $selectedLocationId,
                        onCreate: { name, icon in
                            await vm.createTaxon(kind: .location, name: name, icon: icon,
                                                 token: auth.accessToken ?? "")
                        }
                    )
                }

                Section("Tracking") {
                    Toggle("Running low", isOn: $isLow)
                    Toggle("Auto-add to list when low", isOn: $autoAddToList)
                    Toggle("Has expiration date", isOn: $hasExpiration.animation())
                    if hasExpiration {
                        DatePicker("Expires", selection: $expirationDate, displayedComponents: .date)
                    }
                }

                Section("Barcode") {
                    TextField("UPC / EAN (optional)", text: $barcode)
                        .keyboardType(.numbersAndPunctuation)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.callout)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Item" : "New Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(!canSave)
                    }
                }
            }
            .onAppear(perform: populate)
        }
    }

    private func populate() {
        guard let item else {
            applyPrefill()
            return
        }
        name = item.name
        brand = item.brand
        quantityText = item.quantityText.isEmpty
            ? (item.quantity.map { $0.truncatingRemainder(dividingBy: 1) == 0 ? String(Int($0)) : String($0) } ?? "")
            : item.quantityText
        unit = item.unit
        barcode = item.barcode
        selectedCategoryId = item.category ?? ""
        selectedLocationId = item.location ?? ""
        isLow = item.isLow
        autoAddToList = item.autoAddToList
        if let raw = item.expirationDate, let d = Self.dateFmt.date(from: raw) {
            hasExpiration = true
            expirationDate = d
        }
    }

    private func applyPrefill() {
        guard let prefill else { return }
        name = prefill.name
        brand = prefill.brand
        quantityText = prefill.quantityText
        barcode = prefill.barcode
        // Match the suggested location ("Fridge"/"Freezer"/…) to a real one.
        if !prefill.locationHint.isEmpty,
           let match = vm.locations.first(where: {
               $0.name.caseInsensitiveCompare(prefill.locationHint) == .orderedSame
           }) {
            selectedLocationId = match.id
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        let token = auth.accessToken ?? ""

        let body = PantryItemRequest(
            name: name.trimmingCharacters(in: .whitespaces),
            brand: brand.trimmingCharacters(in: .whitespaces),
            category: selectedCategoryId.isEmpty ? nil : selectedCategoryId,
            quantityText: quantityText.trimmingCharacters(in: .whitespaces),
            unit: unit.trimmingCharacters(in: .whitespaces),
            barcode: barcode.trimmingCharacters(in: .whitespaces),
            location: selectedLocationId.isEmpty ? nil : selectedLocationId,
            expirationDate: hasExpiration ? Self.dateFmt.string(from: expirationDate) : nil,
            isLow: isLow,
            autoAddToList: autoAddToList
        )

        do {
            let saved: PantryItem
            if let item {
                saved = try await APIClient.shared.patch(
                    "/pantry/items/\(item.id)/", body: body, token: token)
            } else {
                saved = try await APIClient.shared.post(
                    "/pantry/items/", body: body, token: token)
            }
            onSave(saved)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
