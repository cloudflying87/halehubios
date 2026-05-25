import SwiftUI

struct ShoppingListsView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var network: NetworkMonitor
    @StateObject private var vm = ShoppingViewModel()
    @State private var showCreateSheet = false
    @State private var navigateToNewList: ShoppingList? = nil

    var body: some View {
        Group {
            if vm.isLoading && vm.lists.isEmpty {
                ProgressView("Loading lists…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.lists.isEmpty, let error = vm.error {
                // Only show the full-screen error when there are NO lists to display.
                // Errors from individual actions (delete/create) surface as an alert
                // below so they don't mask the working list view.
                ContentUnavailableView(
                    "Couldn't Load Lists",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if vm.lists.isEmpty {
                ContentUnavailableView(
                    "No Shopping Lists",
                    systemImage: "cart",
                    description: Text("Tap + to create a shopping list.")
                )
            } else {
                VStack(spacing: 0) {
                    if !network.isConnected {
                        OfflineBanner(cacheDate: vm.cacheDate)
                    }
                    List(vm.lists) { list in
                        NavigationLink(destination: ShoppingListDetailView(list: list)) {
                            ShoppingListRow(list: list)
                        }
                        .swipeActions(edge: .trailing) {
                            if network.isConnected {
                                Button(role: .destructive) {
                                    Task { await vm.deleteList(id: list.id, token: auth.accessToken ?? "") }
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                    .refreshable { await vm.load(token: auth.accessToken ?? "", isConnected: network.isConnected) }
                }
            }
        }
        // Action errors (delete/create) when lists are loaded — present as an
        // alert instead of hijacking the screen.
        .alert(
            "Couldn't complete that action",
            isPresented: Binding(
                get: { vm.error != nil && !vm.lists.isEmpty },
                set: { if !$0 { vm.error = nil } }
            ),
            presenting: vm.error
        ) { _ in
            Button("OK") { vm.error = nil }
        } message: { msg in
            Text(msg)
        }
        .navigationTitle("Shopping")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateShoppingListSheet(vm: vm) { newList in
                navigateToNewList = newList
            }
            .environmentObject(auth)
        }
        .navigationDestination(item: $navigateToNewList) { list in
            ShoppingListDetailView(list: list)
        }
        .task { await vm.load(token: auth.accessToken ?? "", isConnected: network.isConnected) }
    }
}

struct CreateShoppingListSheet: View {
    @EnvironmentObject var auth: AuthManager
    @ObservedObject var vm: ShoppingViewModel
    let onCreated: (ShoppingList) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var listName = ""
    @State private var storeName = ""
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("List Name", text: $listName)
                    TextField("Store (optional)", text: $storeName)
                }
            }
            .navigationTitle("New Shopping List")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isCreating)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView()
                    } else {
                        Button("Create") {
                            Task { await create() }
                        }
                        .disabled(listName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func create() async {
        guard let token = auth.accessToken else { return }
        isCreating = true
        let newList = await vm.createList(
            name: listName.trimmingCharacters(in: .whitespaces),
            store: storeName.trimmingCharacters(in: .whitespaces),
            token: token
        )
        isCreating = false
        if let newList {
            dismiss()
            onCreated(newList)
        }
    }
}

struct ShoppingListRow: View {
    let list: ShoppingList

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(list.name).font(.headline)
                Spacer()
                if list.isFullyChecked && list.itemCount > 0 {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            HStack(spacing: 12) {
                if let store = list.store, !store.isEmpty {
                    Label(store, systemImage: "storefront").font(.caption).foregroundStyle(.secondary)
                }
                Text("\(list.uncheckedCount) of \(list.itemCount) remaining")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if list.itemCount > 0 {
                ProgressView(value: Double(list.checkedCount), total: Double(list.itemCount))
                    .tint(list.isFullyChecked ? Color.green : Color.accentColor)
            }
        }
        .padding(.vertical, 4)
    }
}
