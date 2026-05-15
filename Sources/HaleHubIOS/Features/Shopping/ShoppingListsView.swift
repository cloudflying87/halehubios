import SwiftUI

struct ShoppingListsView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var network: NetworkMonitor
    @StateObject private var vm = ShoppingViewModel()

    var body: some View {
        Group {
            if vm.isLoading && vm.lists.isEmpty {
                ProgressView("Loading lists…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.lists.isEmpty {
                ContentUnavailableView(
                    "No Shopping Lists",
                    systemImage: "cart",
                    description: Text("Create a shopping list on the website.")
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
        .task { await vm.load(token: auth.accessToken ?? "", isConnected: network.isConnected) }
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
