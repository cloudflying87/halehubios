import SwiftUI

struct ShoppingListsView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var network: NetworkMonitor
    @StateObject private var vm = ShoppingViewModel()
    @State private var showCreateSheet = false

    var body: some View {
        Group {
            if vm.isLoading && vm.lists.isEmpty {
                ProgressView("Loading lists…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = vm.error {
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
                    }
                    .refreshable { await vm.load(token: auth.accessToken ?? "", isConnected: network.isConnected) }
                }
            }
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
            CreateShoppingListSheet(vm: vm)
                .environmentObject(auth)
        }
        .task { await vm.load(token: auth.accessToken ?? "", isConnected: network.isConnected) }
    }
}

struct CreateShoppingListSheet: View {
    @EnvironmentObject var auth: AuthManager
    @ObservedObject var vm: ShoppingViewModel
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await create() }
                    }
                    .disabled(listName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
        }
    }

    private func create() async {
        guard let token = auth.accessToken else { return }
        isCreating = true
        await vm.createList(
            name: listName.trimmingCharacters(in: .whitespaces),
            store: storeName.trimmingCharacters(in: .whitespaces),
            token: token
        )
        isCreating = false
        dismiss()
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
