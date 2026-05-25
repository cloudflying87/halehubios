import SwiftUI
import PhotosUI

// MARK: - ViewModel

@MainActor
class ToteDetailViewModel: ObservableObject {
    @Published var toteDetail: ToteDetail?
    @Published var categories: [ToteCategory] = []
    @Published var isLoading = false
    @Published var isUploadingPhoto = false
    @Published var error: String?

    func load(id: String, token: String) async {
        isLoading = true
        error = nil

        async let detailFetch: ToteDetail = APIClient.shared.get("/totes/\(id)/", token: token)
        async let categoriesFetch: [ToteCategory] = APIClient.shared.get("/totes/categories/", token: token)

        do {
            let (detail, cats) = try await (detailFetch, categoriesFetch)
            toteDetail = detail
            categories = cats
        } catch is CancellationError {
            // SwiftUI cancelled the task (e.g. view disappeared) — keep existing data, no error
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func deleteItem(itemId: String, token: String) async {
        do {
            try await APIClient.shared.delete("/tote-items/\(itemId)/", token: token)
            if let detail = toteDetail {
                toteDetail = ToteDetail(
                    id: detail.id,
                    name: detail.name,
                    location: detail.location,
                    locationObjId: detail.locationObjId,
                    locationName: detail.locationName,
                    locationNotes: detail.locationNotes,
                    itemCount: detail.itemCount - 1,
                    dateSorted: detail.dateSorted,
                    dateMoved: detail.dateMoved,
                    qrCodeIdentifier: detail.qrCodeIdentifier,
                    notes: detail.notes,
                    isArchived: detail.isArchived,
                    photo1Url: detail.photo1Url,
                    photo2Url: detail.photo2Url,
                    items: detail.items.filter { $0.id != itemId }
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateTote(id: String, updated: Tote, token: String) async {
        guard let detail = toteDetail else { return }
        toteDetail = ToteDetail(
            id: detail.id,
            name: updated.name,
            location: updated.location,
            locationObjId: updated.locationObjId,
            locationName: updated.locationName,
            locationNotes: updated.locationNotes,
            itemCount: detail.itemCount,
            dateSorted: detail.dateSorted,
            dateMoved: updated.dateMoved ?? detail.dateMoved,
            qrCodeIdentifier: detail.qrCodeIdentifier,
            notes: updated.notes,
            isArchived: detail.isArchived,
            photo1Url: detail.photo1Url,
            photo2Url: detail.photo2Url,
            items: detail.items
        )
    }

    func uploadPhoto(toteId: String, slot: Int, image: UIImage, token: String) async {
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else { return }
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }

        do {
            let url = try await APIClient.shared.uploadPhoto(
                "/totes/\(toteId)/photos/",
                imageData: jpeg,
                slot: slot,
                token: token
            )
            guard let detail = toteDetail else { return }
            toteDetail = ToteDetail(
                id: detail.id,
                name: detail.name,
                location: detail.location,
                locationObjId: detail.locationObjId,
                locationName: detail.locationName,
                locationNotes: detail.locationNotes,
                itemCount: detail.itemCount,
                dateSorted: detail.dateSorted,
                dateMoved: detail.dateMoved,
                qrCodeIdentifier: detail.qrCodeIdentifier,
                notes: detail.notes,
                isArchived: detail.isArchived,
                photo1Url: slot == 1 ? url : detail.photo1Url,
                photo2Url: slot == 2 ? url : detail.photo2Url,
                items: detail.items
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    var itemsByCategory: [(categoryName: String, items: [ToteItem])] {
        guard let detail = toteDetail else { return [] }
        var groups: [(String, [ToteItem])] = []
        var seen = Set<String>()
        for item in detail.items {
            if seen.insert(item.categoryName).inserted {
                groups.append((item.categoryName, detail.items.filter { $0.categoryName == item.categoryName }))
            }
        }
        return groups
    }
}

// MARK: - Main detail view

struct ToteDetailView: View {
    @EnvironmentObject var auth: AuthManager
    let toteId: String
    let toteName: String

    @StateObject private var vm = ToteDetailViewModel()
    @State private var showAddItem = false
    @State private var showEdit = false
    @State private var photoPickerSlot: Int? = nil
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showPhotoActionSheet = false
    @State private var photoActionSlot: Int = 1
    @State private var showCamera = false
    @State private var expandedPhoto: ExpandedPhoto? = nil

    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail = vm.toteDetail {
                toteContent(detail: detail)
            } else {
                loadFailedView
            }
        }
        .navigationTitle(toteName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    if vm.toteDetail != nil {
                        Button { showEdit = true } label: {
                            Image(systemName: "pencil")
                        }
                    }
                    Button {
                        showAddItem = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(vm.categories.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let detail = vm.toteDetail {
                EditToteSheet(tote: detail) { updated in
                    Task { await vm.updateTote(id: detail.id, updated: updated, token: auth.accessToken ?? "") }
                }
                .environmentObject(auth)
            }
        }
        .sheet(isPresented: $showAddItem) {
            addItemSheet
        }
        .confirmationDialog("Add Photo", isPresented: $showPhotoActionSheet, titleVisibility: .visible) {
            Button("Take Photo") {
                photoActionSlot = photoActionSlot   // already set
                showCamera = true
            }
            Button("Choose from Library") {
                photoPickerSlot = photoActionSlot
            }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(
            isPresented: Binding(
                get: { photoPickerSlot != nil },
                set: { if !$0 { photoPickerSlot = nil } }
            ),
            selection: $selectedPhotoItem,
            matching: .images
        )
        .sheet(isPresented: $showCamera) {
            let slot = photoActionSlot
            CameraPickerView { image in
                Task {
                    await vm.uploadPhoto(toteId: toteId, slot: slot, image: image, token: auth.accessToken ?? "")
                }
            }
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item, let slot = photoPickerSlot else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await vm.uploadPhoto(toteId: toteId, slot: slot, image: image, token: auth.accessToken ?? "")
                }
                selectedPhotoItem = nil
                photoPickerSlot = nil
            }
        }
        .task { await vm.load(id: toteId, token: auth.accessToken ?? "") }
        .refreshable { await vm.load(id: toteId, token: auth.accessToken ?? "") }
        .alert("Error", isPresented: .init(get: { vm.error != nil && vm.toteDetail != nil },
                                           set: { if !$0 { vm.error = nil } })) {
            Button("OK") { vm.error = nil }
        } message: { Text(vm.error ?? "") }
        .fullScreenCover(item: $expandedPhoto) { photo in
            ExpandedPhotoView(urlString: photo.url) {
                expandedPhoto = nil
            }
        }
    }

    @ViewBuilder
    private var addItemSheet: some View {
        AddToteItemSheet(
            isPresented: $showAddItem,
            toteId: toteId,
            categories: vm.categories
        ) { newItem in
            guard let detail = vm.toteDetail else { return }
            vm.toteDetail = ToteDetail(
                id: detail.id, name: detail.name,
                location: detail.location,
                locationObjId: detail.locationObjId,
                locationName: detail.locationName,
                locationNotes: detail.locationNotes,
                itemCount: detail.itemCount + 1,
                dateSorted: detail.dateSorted,
                dateMoved: detail.dateMoved,
                qrCodeIdentifier: detail.qrCodeIdentifier,
                notes: detail.notes,
                isArchived: detail.isArchived,
                photo1Url: detail.photo1Url,
                photo2Url: detail.photo2Url,
                items: detail.items + [newItem]
            )
        }
        .environmentObject(auth)
    }

    @ViewBuilder
    private var loadFailedView: some View {
        ContentUnavailableView {
            Label("Couldn't Load Tote", systemImage: "exclamationmark.triangle")
        } description: {
            Text(vm.error ?? "Tap Retry to load this tote.")
        } actions: {
            Button("Retry") {
                Task { await vm.load(id: toteId, token: auth.accessToken ?? "") }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func toteContent(detail: ToteDetail) -> some View {
        List {
            // Location + QR header
            Section {
                HStack(spacing: 8) {
                    Image(systemName: detail.locationIcon)
                        .foregroundStyle(Color.accentColor)
                    Text(detail.locationLabel)
                        .font(.subheadline.weight(.medium))
                    if !detail.locationNotes.isEmpty {
                        Text("· \(detail.locationNotes)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let qr = detail.qrCodeIdentifier {
                        Label(qr, systemImage: "qrcode")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Photo strip
            Section {
                photoStrip(detail: detail)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            // Items grouped by category
            if vm.itemsByCategory.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No items yet",
                        systemImage: "shippingbox",
                        description: Text("Tap + to add some!")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(vm.itemsByCategory, id: \.categoryName) { group in
                    Section(group.categoryName) {
                        ForEach(group.items) { item in
                            ToteItemRow(item: item)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        Task {
                                            await vm.deleteItem(
                                                itemId: item.id,
                                                token: auth.accessToken ?? ""
                                            )
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if vm.isUploadingPhoto {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView("Uploading…").padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    @ViewBuilder
    private func photoStrip(detail: ToteDetail) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                photoSlot(urlString: detail.photo1Url, slot: 1)
                photoSlot(urlString: detail.photo2Url, slot: 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func photoSlot(urlString: String?, slot: Int) -> some View {
        Button {
            photoActionSlot = slot
            showPhotoActionSheet = true
        } label: {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 120)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                                    expandedPhoto = ExpandedPhoto(url: urlString)
                                }
                            )
                    case .failure:
                        placeholderSlot(slot: slot)
                    default:
                        ProgressView().frame(width: 120, height: 120)
                    }
                }
            } else {
                placeholderSlot(slot: slot)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func placeholderSlot(slot: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemGroupedBackground))
                .frame(width: 120, height: 120)
            VStack(spacing: 6) {
                Image(systemName: "camera.badge.plus")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Photo \(slot)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Expanded Photo

private struct ExpandedPhoto: Identifiable {
    let id = UUID()
    let url: String
}

private struct ExpandedPhotoView: View {
    let urlString: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .failure:
                        Image(systemName: "photo.slash")
                            .font(.system(size: 56))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    default:
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .padding(20)
            }
        }
    }
}

// MARK: - ToteItemRow

struct ToteItemRow: View {
    let item: ToteItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.itemTypeName)
                .font(.body)

            HStack(spacing: 12) {
                if !item.quantity.isEmpty {
                    Label(item.quantity, systemImage: "number")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !item.notes.isEmpty {
                    Text(item.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Camera picker (UIImagePickerController wrapper)

struct CameraPickerView: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        init(onImage: @escaping (UIImage) -> Void) { self.onImage = onImage }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage {
                onImage(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - ToteDetail location helpers (mirror Tote extension)

private extension ToteDetail {
    var locationLabel: String { Tote.locationLabel(for: location) }
    var locationIcon: String {
        switch location {
        case "basement":        return "stairs"
        case "attic":           return "house.lodge"
        case "garage":          return "car.garage.door"
        case "storage_unit":    return "building.2"
        case "bedroom_closet":  return "door.sliding.right.hand.closed"
        case "guest_room":      return "bed.double"
        case "shed":            return "leaf"
        default:                return "shippingbox"
        }
    }
}
