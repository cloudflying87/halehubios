import SwiftUI
import PhotosUI
import UIKit

@MainActor
final class JewelryDetailViewModel: ObservableObject {
    @Published var piece: JewelryPiece?
    @Published var categories: [JewelryCategory] = []
    @Published var isLoading = false
    @Published var isUploading = false
    @Published var error: String?
    @Published var didDelete = false

    let pieceId: String
    private var token = ""

    init(pieceId: String) { self.pieceId = pieceId }
    func configure(token: String) { self.token = token }

    func load() async {
        isLoading = true; error = nil
        do {
            async let p: JewelryPiece = APIClient.shared.get("/jewelry/\(pieceId)/", token: token)
            async let c: [JewelryCategory] = APIClient.shared.get("/jewelry/categories/", token: token)
            piece = try await p
            categories = try await c
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }

    func save(_ req: JewelryPieceRequest) async -> Bool {
        do {
            let updated: JewelryPiece = try await APIClient.shared.patch("/jewelry/\(pieceId)/", body: req, token: token)
            piece = updated
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func uploadPhoto(slot: Int, image: UIImage) async {
        isUploading = true
        defer { isUploading = false }
        let normalized = image.jewelryNormalized().jewelryResized(maxDimension: 1200)
        guard let jpeg = normalized.jpegData(compressionQuality: 0.85) else { return }
        do {
            _ = try await APIClient.shared.uploadPhoto("/jewelry/\(pieceId)/photos/", imageData: jpeg, slot: slot, token: token)
            await load()
        } catch { self.error = error.localizedDescription }
    }

    func delete() async {
        do {
            try await APIClient.shared.delete("/jewelry/\(pieceId)/", token: token)
            didDelete = true
        } catch { self.error = error.localizedDescription }
    }
}

struct JewelryDetailView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: JewelryDetailViewModel
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var photoSlot: Int?
    @State private var pickerItem: PhotosPickerItem?

    private var token: String { auth.accessToken ?? "" }

    init(pieceId: String) {
        _vm = StateObject(wrappedValue: JewelryDetailViewModel(pieceId: pieceId))
    }

    var body: some View {
        ScrollView {
            if let p = vm.piece {
                VStack(alignment: .leading, spacing: 16) {
                    photoRow(p)
                    Text(p.title).font(.title2).fontWeight(.semibold)
                    Text(p.categoryName.isEmpty ? "Uncategorized" : p.categoryName)
                        .font(.subheadline).foregroundStyle(.secondary)
                    detailsCard(p)
                }
                .padding(16)
            } else if vm.isLoading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .navigationTitle("Piece")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit") { showEdit = true }
                    Button("Delete", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .task { vm.configure(token: token); await vm.load() }
        .sheet(isPresented: $showEdit) {
            if let p = vm.piece { EditJewelrySheet(vm: vm, piece: p) }
        }
        .confirmationDialog("Delete this piece?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await vm.delete() } }
        }
        .onChange(of: vm.didDelete) { if vm.didDelete { dismiss() } }
        .photosPicker(isPresented: .init(get: { photoSlot != nil }, set: { if !$0 { photoSlot = nil } }),
                      selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) {
            guard let slot = photoSlot, let item = pickerItem else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    await vm.uploadPhoto(slot: slot, image: img)
                }
                pickerItem = nil; photoSlot = nil
            }
        }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
    }

    private func photoRow(_ p: JewelryPiece) -> some View {
        let urls = [p.photo1Url, p.photo2Url, p.photo3Url]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { i in
                    Button { photoSlot = i + 1 } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground))
                            if let s = urls[i], let u = URL(string: s) {
                                AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { ProgressView() }
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else {
                                VStack(spacing: 4) {
                                    Image(systemName: "camera.fill").foregroundStyle(.secondary)
                                    Text("Photo \(i + 1)").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            if vm.isUploading && photoSlot == i + 1 { ProgressView() }
                        }
                        .frame(width: 150, height: 150).clipped()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func detailsCard(_ p: JewelryPiece) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !p.description.isEmpty { Text(p.description) }
            if let v = p.estimatedValue { row("Estimated value", LoanFormatters.money(v, fractionDigits: 2)) }
            if p.hasCertificate { row("Certificate", "✅ Yes") }
            if !p.storageLocation.isEmpty { row("Stored", p.storageLocation) }
            if let d = p.acquiredDate { row("Acquired", d) }
            if !p.acquiredNotes.isEmpty { row("Acquired notes", p.acquiredNotes) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.subheadline).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
            Text(value).font(.subheadline)
            Spacer()
        }
    }
}

// MARK: - Edit sheet

struct EditJewelrySheet: View {
    @ObservedObject var vm: JewelryDetailViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var categoryId: String
    @State private var description: String
    @State private var value: String
    @State private var hasCertificate: Bool
    @State private var storage: String
    @State private var acquired: String
    @State private var acquiredNotes: String
    @State private var saving = false

    init(vm: JewelryDetailViewModel, piece: JewelryPiece) {
        self.vm = vm
        _title = State(initialValue: piece.title)
        _categoryId = State(initialValue: piece.categoryId ?? "")
        _description = State(initialValue: piece.description)
        _value = State(initialValue: piece.estimatedValue.map { String($0) } ?? "")
        _hasCertificate = State(initialValue: piece.hasCertificate)
        _storage = State(initialValue: piece.storageLocation)
        _acquired = State(initialValue: piece.acquiredDate ?? "")
        _acquiredNotes = State(initialValue: piece.acquiredNotes)
    }

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
                Section {
                    TextField("Estimated value", text: $value).keyboardType(.decimalPad)
                    Toggle("Has certificate", isOn: $hasCertificate)
                }
                Section {
                    DisclosureGroup("Storage & acquired details") {
                        TextField("Where it's stored", text: $storage)
                        TextField("Acquired date (YYYY-MM-DD)", text: $acquired)
                        TextField("Acquired notes", text: $acquiredNotes, axis: .vertical).lineLimit(2...3)
                    }
                }
            }
            .navigationTitle("Edit Piece")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            saving = true
                            let ok = await vm.save(JewelryPieceRequest(
                                title: title.trimmingCharacters(in: .whitespaces),
                                categoryId: categoryId.isEmpty ? nil : categoryId,
                                description: description,
                                estimatedValue: Double(value),
                                hasCertificate: hasCertificate,
                                storageLocation: storage,
                                acquiredDate: acquired.isEmpty ? nil : acquired,
                                acquiredNotes: acquiredNotes))
                            saving = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Image helpers (file-private; mirrors the Totes upload pipeline)

private extension UIImage {
    func jewelryNormalized() -> UIImage {
        if imageOrientation == .up { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let result = UIGraphicsGetImageFromCurrentImageContext() ?? self
        UIGraphicsEndImageContext()
        return result
    }

    func jewelryResized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let ratio = maxDimension / longest
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
