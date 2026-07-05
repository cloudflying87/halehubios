import SwiftUI

struct ShoppingListDetailView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var network: NetworkMonitor
    @Environment(\.dismiss) private var dismiss
    let list: ShoppingList
    @StateObject private var vm: ShoppingDetailViewModel

    init(list: ShoppingList) {
        self.list = list
        _vm = StateObject(wrappedValue: ShoppingDetailViewModel(listId: list.id))
    }

    var current: ShoppingList { vm.list ?? list }
    var unchecked: [ShoppingItem] { current.items?.filter { !$0.isChecked } ?? [] }
    var checked: [ShoppingItem] { current.items?.filter { $0.isChecked } ?? [] }

    @ViewBuilder
    private func itemSwipeActions(_ item: ShoppingItem) -> some View {
        if network.isConnected {
            Button(role: .destructive) {
                Task { await vm.deleteItem(item, token: auth.accessToken ?? "") }
            } label: { Label("Delete", systemImage: "trash") }
            Button {
                vm.movingItem = item
            } label: { Label("Move", systemImage: "folder") }
                .tint(.blue)
        }
    }

    var body: some View {
        List {
            // Add item row (online only)
            if network.isConnected {
                Section {
                    HStack {
                        TextField("Add item…", text: $vm.newItemName)
                            .submitLabel(.done)
                            .onSubmit { Task { await vm.addItem(token: auth.accessToken ?? "") } }
                        if !vm.newItemQty.isEmpty || !vm.newItemName.isEmpty {
                            TextField("Qty", text: $vm.newItemQty)
                                .frame(width: 60)
                                .multilineTextAlignment(.center)
                        }
                        Button {
                            Task { await vm.addItem(token: auth.accessToken ?? "") }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.accentColor)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .disabled(vm.newItemName.isEmpty)
                    }
                }
            } else {
                Section {
                    Label("Connect to add items", systemImage: "wifi.slash")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            // Unchecked items
            if !unchecked.isEmpty {
                Section("\(unchecked.count) remaining") {
                    ForEach(unchecked) { item in
                        ItemRow(item: item, isConnected: network.isConnected) {
                            Task { await vm.toggle(item: item, token: auth.accessToken ?? "") }
                        }
                        .swipeActions(edge: .trailing) { itemSwipeActions(item) }
                    }
                }
            }

            // Checked items (collapsed by default)
            if !checked.isEmpty {
                Section {
                    ForEach(checked) { item in
                        ItemRow(item: item, isConnected: network.isConnected) {
                            Task { await vm.toggle(item: item, token: auth.accessToken ?? "") }
                        }
                        .swipeActions(edge: .trailing) { itemSwipeActions(item) }
                    }
                } header: {
                    Text("\(checked.count) checked off").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if network.isConnected {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { vm.showBulkAdd = true } label: {
                            Label("Bulk Add", systemImage: "text.badge.plus")
                        }
                        if !checked.isEmpty {
                            Divider()
                            Button(role: .destructive) {
                                Task {
                                    for item in checked {
                                        await vm.deleteItem(item, token: auth.accessToken ?? "")
                                    }
                                }
                            } label: { Label("Clear Checked", systemImage: "trash") }
                        }
                        Divider()
                        Button(role: .destructive) {
                            vm.showDeleteListConfirm = true
                        } label: { Label("Delete List", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .confirmationDialog("Delete \"\(current.name)\"?",
                            isPresented: $vm.showDeleteListConfirm, titleVisibility: .visible) {
            Button("Delete List", role: .destructive) {
                Task {
                    await vm.deleteList(id: current.id, token: auth.accessToken ?? "")
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete the list and all its items.")
        }
        .sheet(isPresented: $vm.showBulkAdd) {
            BulkAddSheet(text: $vm.bulkText) {
                Task { await vm.addBulkItems(token: auth.accessToken ?? "") }
            }
        }
        .sheet(item: $vm.movingItem) { item in
            MoveItemSheet(
                item: item,
                lists: vm.otherLists,
                onPick: { targetId in
                    Task { await vm.moveItem(item, toListId: targetId, token: auth.accessToken ?? "") }
                },
                onNewList: { name in
                    Task { await vm.moveItem(item, toNewList: name, token: auth.accessToken ?? "") }
                }
            )
            .task { await vm.loadOtherLists(token: auth.accessToken ?? "") }
        }
        .task { await vm.load(token: auth.accessToken ?? "", isConnected: network.isConnected) }
        .refreshable { await vm.load(token: auth.accessToken ?? "", isConnected: true) }
        .onChange(of: vm.listDeleted) { _, deleted in if deleted { dismiss() } }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") { }
        } message: { Text(vm.error ?? "") }
    }
}

struct ItemRow: View {
    let item: ShoppingItem
    let isConnected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isChecked ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(!isConnected)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .strikethrough(item.isChecked)
                    .foregroundStyle(item.isChecked ? .secondary : .primary)
                if let qty = item.quantity, !qty.isEmpty {
                    Text(qty).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }
}

// MARK: - Bulk Add Sheet

struct BulkAddSheet: View {
    @Binding var text: String
    let onAdd: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                } header: {
                    Text("One item per line or comma-separated.\nAdd quantity with \"x2\" — e.g. \"Milk x2, Eggs x dozen\"")
                        .textCase(nil)
                }
            }
            .navigationTitle("Bulk Add Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { onAdd() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Move Item Sheet

struct MoveItemSheet: View {
    let item: ShoppingItem
    let lists: [ShoppingList]
    let onPick: (UUID) -> Void
    let onNewList: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newListName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Move “\(item.name)”").font(.headline)
                }

                if !lists.isEmpty {
                    Section("Move to list") {
                        ForEach(lists) { list in
                            Button {
                                onPick(list.id)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(list.name).foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(list.uncheckedCount)")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }

                Section("Start a new list") {
                    HStack {
                        TextField("New list name", text: $newListName)
                            .submitLabel(.done)
                            .onSubmit(create)
                        Button("Create & Move", action: create)
                            .disabled(newListName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("Move Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func create() {
        let name = newListName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        onNewList(name)
        dismiss()
    }
}
