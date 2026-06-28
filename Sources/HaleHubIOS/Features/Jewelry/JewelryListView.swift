import SwiftUI

@MainActor
final class JewelryViewModel: ObservableObject {
    @Published var pieces: [JewelryPiece] = []
    @Published var categories: [JewelryCategory] = []
    @Published var selectedCategoryId: String?
    @Published var isLoading = false
    @Published var error: String?

    private var token: String = ""

    func configure(token: String) { self.token = token }

    func load() async {
        isLoading = true
        error = nil
        do {
            async let cats: [JewelryCategory] = APIClient.shared.get("/jewelry/categories/", token: token)
            let path = selectedCategoryId.map { "/jewelry/?category=\($0)" } ?? "/jewelry/"
            async let items: [JewelryPiece] = APIClient.shared.get(path, token: token)
            categories = try await cats
            pieces = try await items
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func createPiece(_ req: JewelryPieceRequest) async -> JewelryPiece? {
        do {
            let piece: JewelryPiece = try await APIClient.shared.post("/jewelry/", body: req, token: token)
            await load()
            return piece
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func addCategory(_ name: String) async {
        do {
            let _: JewelryCategory = try await APIClient.shared.post(
                "/jewelry/categories/", body: JewelryCategoryRequest(name: name), token: token)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct JewelryListView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = JewelryViewModel()
    @State private var showCreate = false
    @State private var showCategories = false

    private var token: String { auth.accessToken ?? "" }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                categoryFilter
                if vm.pieces.isEmpty && !vm.isLoading {
                    ContentUnavailableView("No Jewelry", systemImage: "sparkles",
                                           description: Text("Tap + to add your first piece."))
                        .frame(minHeight: 200)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(vm.pieces) { piece in
                            NavigationLink(destination: JewelryDetailView(pieceId: piece.id)) {
                                pieceCard(piece)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Jewelry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink("Report", destination: JewelryReportView())
                    Button("Manage Categories") { showCategories = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .task { vm.configure(token: token); await vm.load() }
        .refreshable { await vm.load() }
        .onChange(of: vm.selectedCategoryId) { Task { await vm.load() } }
        .sheet(isPresented: $showCreate) { CreateJewelrySheet(vm: vm) }
        .sheet(isPresented: $showCategories) { JewelryCategoriesSheet(vm: vm) }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: vm.selectedCategoryId == nil) { vm.selectedCategoryId = nil }
                ForEach(vm.categories) { c in
                    chip(c.name, selected: vm.selectedCategoryId == c.id) { vm.selectedCategoryId = c.id }
                }
            }
        }
    }

    private func chip(_ label: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.subheadline)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(selected ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundStyle(selected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func pieceCard(_ piece: JewelryPiece) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Color(.secondarySystemBackground)
                if let url = piece.photo1Url, let u = URL(string: url) {
                    AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { ProgressView() }
                } else {
                    Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.secondary)
                }
            }
            .frame(height: 150).clipped()
            VStack(alignment: .leading, spacing: 2) {
                Text(piece.title).font(.subheadline).fontWeight(.medium).lineLimit(1)
                Text(piece.categoryName.isEmpty ? "Uncategorized" : piece.categoryName)
                    .font(.caption2).foregroundStyle(.secondary)
                if let v = piece.estimatedValue {
                    Text(LoanFormatters.money(v, fractionDigits: 0)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Create sheet

struct CreateJewelrySheet: View {
    @ObservedObject var vm: JewelryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var categoryId: String = ""
    @State private var description = ""
    @State private var value = ""
    @State private var storage = ""
    @State private var acquired = ""
    @State private var acquiredNotes = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Piece") {
                    TextField("Title", text: $title)
                    Picker("Category", selection: $categoryId) {
                        Text("None").tag("")
                        ForEach(vm.categories) { Text($0.name).tag($0.id) }
                    }
                    TextField("Description", text: $description, axis: .vertical).lineLimit(2...4)
                }
                Section("Details (optional)") {
                    TextField("Estimated value", text: $value).keyboardType(.decimalPad)
                    TextField("Where it's stored", text: $storage)
                    TextField("Acquired date (YYYY-MM-DD)", text: $acquired)
                    TextField("Acquired notes", text: $acquiredNotes, axis: .vertical).lineLimit(2...3)
                }
                Text("Add photos after saving, from the piece's detail screen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("Add Piece")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            saving = true
                            let req = JewelryPieceRequest(
                                title: title.trimmingCharacters(in: .whitespaces),
                                categoryId: categoryId.isEmpty ? nil : categoryId,
                                description: description,
                                estimatedValue: Double(value),
                                storageLocation: storage,
                                acquiredDate: acquired.isEmpty ? nil : acquired,
                                acquiredNotes: acquiredNotes)
                            let created = await vm.createPiece(req)
                            saving = false
                            if created != nil { dismiss() }
                        }
                    }
                    .disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Category management sheet

struct JewelryCategoriesSheet: View {
    @ObservedObject var vm: JewelryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Add category") {
                    HStack {
                        TextField("e.g. Rings", text: $newName)
                        Button("Add") {
                            let name = newName.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty else { return }
                            newName = ""
                            Task { await vm.addCategory(name) }
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section("Categories") {
                    if vm.categories.isEmpty {
                        Text("No categories yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(vm.categories) { Text($0.name) }
                    }
                }
            }
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
