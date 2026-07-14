import SwiftUI

// Categories and locations are the same managed-list pattern: read the list,
// pick one, create a new one inline ("＋ New"), and rename/delete them
// independently of items. `PantryTaxonKind` picks which endpoint a given
// picker/manager talks to; everything else is shared.

enum PantryTaxonKind: String, Sendable, Identifiable {
    case category
    case location

    var id: String { rawValue }
    var path: String {
        switch self {
        case .category: return "/pantry/categories/"
        case .location: return "/pantry/locations/"
        }
    }
    var singular: String { self == .category ? "Category" : "Location" }
    var plural: String { self == .category ? "Categories" : "Locations" }
    var noneLabel: String { self == .category ? "Uncategorized" : "Pantry" }
}

// MARK: - Picker with inline "＋ New"

/// A menu that selects one taxon (or none) and can create a new one on the fly.
/// `selectedId` is the empty string when nothing is chosen.
struct PantryTaxonPicker: View {
    let kind: PantryTaxonKind
    let taxa: [PantryTaxon]
    @Binding var selectedId: String
    /// Create a taxon on the server; returns the saved taxon (with its UUID).
    let onCreate: (_ name: String, _ icon: String) async -> PantryTaxon?

    @State private var showNew = false
    @State private var newName = ""
    @State private var newIcon = ""
    @State private var isCreating = false

    var body: some View {
        Picker(kind.singular, selection: $selectedId) {
            Text(kind.noneLabel).tag("")
            ForEach(taxa) { taxon in
                Text(taxon.displayName).tag(taxon.id)
            }
        }
        Button {
            newName = ""; newIcon = ""; showNew = true
        } label: {
            Label("New \(kind.singular)", systemImage: "plus.circle")
        }
        .alert("New \(kind.singular)", isPresented: $showNew) {
            TextField("Name", text: $newName)
            TextField("Emoji (optional)", text: $newIcon)
            Button("Add") { Task { await create() } }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
    }

    private func create() async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !isCreating else { return }
        isCreating = true
        if let created = await onCreate(name, newIcon.trimmingCharacters(in: .whitespaces)) {
            selectedId = created.id
        }
        isCreating = false
    }
}

// MARK: - Manager (rename / delete / add)

/// A list of taxa with add, rename (tap) and delete (swipe). Persists each
/// change immediately. Used for both categories and locations.
struct PantryTaxonManagerView: View {
    let kind: PantryTaxonKind
    @ObservedObject var vm: PantryViewModel
    @EnvironmentObject var auth: AuthManager

    @State private var editing: PantryTaxon?
    @State private var showNew = false
    @State private var draftName = ""
    @State private var draftIcon = ""

    private var taxa: [PantryTaxon] {
        kind == .category ? vm.categories : vm.locations
    }

    var body: some View {
        List {
            if taxa.isEmpty {
                ContentUnavailableView(
                    "No \(kind.plural)",
                    systemImage: "tray",
                    description: Text("Tap + to add one.")
                )
            } else {
                ForEach(taxa) { taxon in
                    Button {
                        editing = taxon
                        draftName = taxon.name
                        draftIcon = taxon.icon
                    } label: {
                        HStack {
                            Text(taxon.displayName).foregroundStyle(.primary)
                            Spacer()
                            if let count = taxon.itemCount {
                                Text("\(count)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await vm.deleteTaxon(kind: kind, id: taxon.id, token: auth.accessToken ?? "") }
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
        .navigationTitle("Manage \(kind.plural)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    draftName = ""; draftIcon = ""; showNew = true
                } label: { Image(systemName: "plus") }
            }
        }
        .alert("New \(kind.singular)", isPresented: $showNew) {
            TextField("Name", text: $draftName)
            TextField("Emoji (optional)", text: $draftIcon)
            Button("Add") {
                Task { _ = await vm.createTaxon(kind: kind, name: draftName, icon: draftIcon, token: auth.accessToken ?? "") }
            }
            .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename \(kind.singular)", isPresented: .init(
            get: { editing != nil }, set: { if !$0 { editing = nil } }
        )) {
            TextField("Name", text: $draftName)
            TextField("Emoji (optional)", text: $draftIcon)
            Button("Save") {
                if let taxon = editing {
                    Task { await vm.renameTaxon(kind: kind, id: taxon.id, name: draftName, icon: draftIcon, token: auth.accessToken ?? "") }
                }
                editing = nil
            }
            .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) { editing = nil }
        }
        .task { await vm.loadTaxa(token: auth.accessToken ?? "") }
    }
}
