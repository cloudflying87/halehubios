import SwiftUI

struct ShoppingListsView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var network: NetworkMonitor
    @StateObject private var vm = ShoppingViewModel()
    @State private var showCreateSheet = false
    @State private var navigateToNewList: ShoppingList? = nil

    @Environment(\.horizontalSizeClass) private var hSize
    @State private var selectedListID: ShoppingList.ID?

    var body: some View {
        // iPad (regular) → list sidebar + detail pane. iPhone (compact) → the
        // existing push stack, unchanged.
        Group {
            if hSize == .regular {
                splitBody
            } else {
                stackBody
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
        .sheet(isPresented: $showCreateSheet) {
            CreateShoppingListSheet(vm: vm) { newList in
                if hSize == .regular {
                    selectedListID = newList.id
                } else {
                    navigateToNewList = newList
                }
            }
            .environmentObject(auth)
        }
        .task { await vm.load(token: auth.accessToken ?? "", isConnected: network.isConnected) }
    }

    // MARK: iPhone — push stack

    private var stackBody: some View {
        Group {
            if vm.isLoading && vm.lists.isEmpty {
                ProgressView("Loading lists…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.lists.isEmpty, let error = vm.error {
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
                        .swipeActions(edge: .trailing) { deleteAction(list) }
                    }
                    .refreshable { await vm.load(token: auth.accessToken ?? "", isConnected: network.isConnected) }
                }
            }
        }
        .navigationTitle("Shopping")
        .toolbar { ToolbarItem(placement: .primaryAction) { addButton } }
        .navigationDestination(item: $navigateToNewList) { list in
            ShoppingListDetailView(list: list)
        }
    }

    // MARK: iPad — split view

    private var splitBody: some View {
        NavigationSplitView {
            Group {
                if !network.isConnected {
                    VStack(spacing: 0) {
                        OfflineBanner(cacheDate: vm.cacheDate)
                        sidebarList
                    }
                } else {
                    sidebarList
                }
            }
            .navigationTitle("Shopping")
            .toolbar { ToolbarItem(placement: .primaryAction) { addButton } }
        } detail: {
            NavigationStack {
                if let id = selectedListID, let list = vm.lists.first(where: { $0.id == id }) {
                    ShoppingListDetailView(list: list).id(id)
                } else {
                    ContentUnavailableView(
                        "Select a List",
                        systemImage: "cart",
                        description: Text("Pick a shopping list to view its items.")
                    )
                }
            }
        }
    }

    private var sidebarList: some View {
        List(selection: $selectedListID) {
            ForEach(vm.lists) { list in
                ShoppingListRow(list: list)
                    .tag(list.id)
                    .swipeActions(edge: .trailing) { deleteAction(list) }
            }
        }
        .overlay {
            if vm.lists.isEmpty && !vm.isLoading {
                ContentUnavailableView(
                    "No Shopping Lists",
                    systemImage: "cart",
                    description: Text("Tap + to create a shopping list.")
                )
            }
        }
        .refreshable { await vm.load(token: auth.accessToken ?? "", isConnected: network.isConnected) }
    }

    // MARK: Shared bits

    @ViewBuilder
    private func deleteAction(_ list: ShoppingList) -> some View {
        if network.isConnected {
            Button(role: .destructive) {
                Task { await vm.deleteList(id: list.id, token: auth.accessToken ?? "") }
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private var addButton: some View {
        Button { showCreateSheet = true } label: { Image(systemName: "plus") }
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
