import SwiftUI
import UIKit
import WebKit

// MARK: - ViewModel

@MainActor
class LetterDetailViewModel: ObservableObject {
    @Published var detail: LetterDetail?
    @Published var isLoading = false
    @Published var error: String?
    @Published var rsvpSuccess = false
    @Published var rsvpError: String?
    @Published var isSubmittingRSVP = false
    @Published var isDownloading = false
    @Published var isDownloaded = false

    private func cacheKey(_ slug: String) -> String { "letter_detail_\(slug)" }

    func load(slug: String, token: String) async {
        isLoading = true
        error = nil
        // Show any cached copy immediately — instant render and the offline fallback.
        if detail == nil, let cached: LetterDetail = await CacheManager.shared.load(key: cacheKey(slug)) {
            detail = cached
        }
        do {
            let fresh: LetterDetail = try await APIClient.shared.get("/letters/\(slug)/", token: token)
            detail = fresh
            await CacheManager.shared.save(fresh, key: cacheKey(slug))
        } catch {
            // Offline (or failed) with a cached copy → keep showing it silently.
            if detail == nil { self.error = error.localizedDescription }
        }
        await refreshDownloadedState(slug: slug)
        isLoading = false
    }

    /// A letter counts as "downloaded" when its detail JSON is cached and every
    /// photo is on disk.
    func refreshDownloadedState(slug: String) async {
        guard let cached: LetterDetail = await CacheManager.shared.load(key: cacheKey(slug)) else {
            isDownloaded = false
            return
        }
        for photo in cached.photos {
            let onDisk = await OfflineImageStore.shared.isCached(photo.url)
            if !onDisk {
                isDownloaded = false
                return
            }
        }
        isDownloaded = true
    }

    /// Save the letter (text + every photo) for offline reading.
    func downloadForOffline(slug: String, token: String) async {
        isDownloading = true
        var letterToCache = detail
        do {
            let fresh: LetterDetail = try await APIClient.shared.get("/letters/\(slug)/", token: token)
            detail = fresh
            letterToCache = fresh
            await CacheManager.shared.save(fresh, key: cacheKey(slug))
        } catch {
            // Offline: fall back to whatever we already have cached.
            if letterToCache == nil {
                letterToCache = await CacheManager.shared.load(key: cacheKey(slug))
            }
        }
        if let letterToCache {
            for photo in letterToCache.photos {
                await OfflineImageStore.shared.download(photo.url)
            }
        }
        await refreshDownloadedState(slug: slug)
        isDownloading = false
    }

    func submitRSVP(slug: String, rsvp: RSVPRequest, token: String) async {
        isSubmittingRSVP = true
        rsvpError = nil
        do {
            let response: RSVPResponse = try await APIClient.shared.post(
                "/letters/\(slug)/rsvp/", body: rsvp, token: token
            )
            rsvpSuccess = response.success
            if !response.success { rsvpError = response.message }
        } catch {
            rsvpError = error.localizedDescription
        }
        isSubmittingRSVP = false
    }
}

// MARK: - View

struct LetterDetailView: View {
    @EnvironmentObject var auth: AuthManager
    let letter: Letter

    @StateObject private var vm = LetterDetailViewModel()

    @State private var rsvpName = ""
    @State private var rsvpEmail = ""
    @State private var rsvpPhone = ""
    @State private var rsvpGuestCount = 1
    @State private var rsvpNotes = ""
    @State private var showRSVPForm = false
    @State private var selectedPhoto: LetterPhoto?
    @State private var showEdit = false

    var body: some View {
        Group {
            if vm.isLoading && vm.detail == nil {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = vm.error, vm.detail == nil {
                ContentUnavailableView {
                    Label("Couldn't Load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") {
                        Task { await vm.load(slug: letter.slug, token: auth.accessToken ?? "") }
                    }
                    .buttonStyle(.bordered)
                }
            } else if let detail = vm.detail {
                contentView(detail: detail)
            } else {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(letter.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if vm.isDownloading {
                    ProgressView()
                } else {
                    Button {
                        Task { await vm.downloadForOffline(slug: letter.slug, token: auth.accessToken ?? "") }
                    } label: {
                        Image(systemName: vm.isDownloaded ? "checkmark.icloud.fill" : "arrow.down.circle")
                    }
                    .accessibilityLabel(vm.isDownloaded ? "Saved for offline" : "Download for offline")
                    .disabled(vm.detail == nil)
                }
            }
            if let detail = vm.detail, detail.canEdit {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { showEdit = true }
                }
            }
        }
        .sheet(item: $selectedPhoto) { photo in
            PhotoFullScreenView(photo: photo)
        }
        .sheet(isPresented: $showEdit) {
            if let detail = vm.detail {
                LetterEditorSheet(mode: .edit(detail)) { updated in
                    vm.detail = updated
                }
                .environmentObject(auth)
            }
        }
        .task { await vm.load(slug: letter.slug, token: auth.accessToken ?? "") }
    }

    @ViewBuilder
    private func contentView(detail: LetterDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Event Info Banner
                if let eventDate = detail.eventDate, !eventDate.isEmpty {
                    EventInfoBanner(detail: detail)
                }

                // Greeting Message — server-rendered HTML in WKWebView
                if !detail.greetingMessageHtml.isEmpty {
                    HTMLWebView(html: detail.greetingMessageHtml)
                        .frame(minHeight: 200)
                } else if !detail.greetingMessage.isEmpty {
                    // Fallback: AttributedString markdown
                    MarkdownContentView(content: detail.greetingMessage)
                }

                // Photo Gallery
                if !detail.photos.isEmpty {
                    PhotoGallerySection(photos: detail.photos, onTap: { selectedPhoto = $0 })
                }

                // RSVP Section
                if detail.hasRsvp {
                    RSVPSection(
                        detail: detail,
                        vm: vm,
                        showRSVPForm: $showRSVPForm,
                        rsvpName: $rsvpName,
                        rsvpEmail: $rsvpEmail,
                        rsvpPhone: $rsvpPhone,
                        rsvpGuestCount: $rsvpGuestCount,
                        rsvpNotes: $rsvpNotes,
                        onSubmit: { Task { await submitRSVP(detail: detail) } }
                    )
                }

                Spacer(minLength: 40)
            }
            .padding(20)
        }
    }

    private func submitRSVP(detail: LetterDetail) async {
        guard let token = auth.accessToken else { return }
        let rsvp = RSVPRequest(
            name: rsvpName.trimmingCharacters(in: .whitespaces),
            email: rsvpEmail.trimmingCharacters(in: .whitespaces),
            phone: rsvpPhone.trimmingCharacters(in: .whitespaces),
            guestCount: rsvpGuestCount,
            notes: rsvpNotes.trimmingCharacters(in: .whitespaces)
        )
        await vm.submitRSVP(slug: detail.slug, rsvp: rsvp, token: token)
        if vm.rsvpSuccess { showRSVPForm = false }
    }
}

// MARK: - Event Info Banner

private struct EventInfoBanner: View {
    let detail: LetterDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eventDate = detail.eventDate {
                Label(formattedDate(eventDate), systemImage: "calendar")
                    .font(.subheadline.weight(.medium))
            }
            if !detail.eventTime.isEmpty {
                Label(detail.eventTime, systemImage: "clock")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if !detail.eventLocation.isEmpty {
                Label(detail.eventLocation, systemImage: "mappin.and.ellipse")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(0.2), lineWidth: 1))
    }

    private func formattedDate(_ dateString: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let date = fmt.date(from: dateString) else { return dateString }
        fmt.dateStyle = .long
        return fmt.string(from: date)
    }
}

// MARK: - Photo Gallery

private struct PhotoGallerySection: View {
    let photos: [LetterPhoto]
    let onTap: (LetterPhoto) -> Void

    private let columns = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Photos").font(.headline)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(photos.sorted { $0.order < $1.order }) { photo in
                    PhotoThumbnail(photo: photo).onTapGesture { onTap(photo) }
                }
            }
        }
    }
}

private struct PhotoThumbnail: View {
    let photo: LetterPhoto

    var body: some View {
        CachedAsyncImage(urlString: photo.url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Color(.systemGray5).overlay(
                Image(systemName: "photo").foregroundStyle(.tertiary).font(.title2)
            )
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Cached Async Image

/// Like `AsyncImage`, but it prefers a copy from `OfflineImageStore` (so letter
/// photos show without a connection) and caches any network fetch for next time.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let urlString: String
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var loaded: Image?
    @State private var didFail = false

    var body: some View {
        Group {
            if let loaded {
                content(loaded)
            } else if didFail {
                placeholder()
            } else {
                placeholder().task { await load() }
            }
        }
    }

    @MainActor
    private func load() async {
        // 1. Offline copy on disk.
        if let data = await OfflineImageStore.shared.data(for: urlString),
           let ui = UIImage(data: data) {
            loaded = Image(uiImage: ui)
            return
        }
        // 2. Network — and cache it for offline next time.
        guard let url = URL(string: urlString) else { didFail = true; return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let ui = UIImage(data: data) else { didFail = true; return }
            await OfflineImageStore.shared.store(data, for: urlString)
            loaded = Image(uiImage: ui)
        } catch {
            didFail = true
        }
    }
}

// MARK: - Photo Full Screen

private struct PhotoFullScreenView: View {
    @Environment(\.dismiss) private var dismiss
    let photo: LetterPhoto

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                CachedAsyncImage(urlString: photo.url) { image in
                    image.resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                } placeholder: {
                    Image(systemName: "photo.slash").font(.largeTitle).foregroundStyle(.white.opacity(0.5))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(.white)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if !photo.caption.isEmpty {
                    Text(photo.caption)
                        .font(.caption).foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(.black.opacity(0.6))
                }
            }
        }
    }
}

// MARK: - RSVP Section

private struct RSVPSection: View {
    let detail: LetterDetail
    @ObservedObject var vm: LetterDetailViewModel
    @Binding var showRSVPForm: Bool
    @Binding var rsvpName: String
    @Binding var rsvpEmail: String
    @Binding var rsvpPhone: String
    @Binding var rsvpGuestCount: Int
    @Binding var rsvpNotes: String
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(detail.rsvpTitle.isEmpty ? "RSVP" : detail.rsvpTitle).font(.headline)
                if !detail.rsvpSubtitle.isEmpty {
                    Text(detail.rsvpSubtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }

            if vm.rsvpSuccess {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("You're on the list! See you there.").font(.subheadline)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            } else if !showRSVPForm {
                Button { showRSVPForm = true } label: {
                    Label("Submit RSVP", systemImage: "person.crop.circle.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                RSVPFormFields(
                    detail: detail, vm: vm,
                    rsvpName: $rsvpName, rsvpEmail: $rsvpEmail,
                    rsvpPhone: $rsvpPhone, rsvpGuestCount: $rsvpGuestCount,
                    rsvpNotes: $rsvpNotes, onSubmit: onSubmit
                )
            }
        }
        .padding(16)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct RSVPFormFields: View {
    let detail: LetterDetail
    @ObservedObject var vm: LetterDetailViewModel
    @Binding var rsvpName: String
    @Binding var rsvpEmail: String
    @Binding var rsvpPhone: String
    @Binding var rsvpGuestCount: Int
    @Binding var rsvpNotes: String
    let onSubmit: () -> Void

    var isFormValid: Bool { !rsvpName.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 12) {
            field("Name") {
                TextField("Your name", text: $rsvpName).textContentType(.name)
            }
            if detail.rsvpShowEmail {
                field("Email") {
                    TextField("email@example.com", text: $rsvpEmail)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                }
            }
            if detail.rsvpShowPhone {
                field("Phone") {
                    TextField("(555) 000-0000", text: $rsvpPhone)
                        .textContentType(.telephoneNumber).keyboardType(.phonePad)
                }
            }
            if detail.rsvpShowGuestCount {
                field("Guests") {
                    Stepper("\(rsvpGuestCount) guest\(rsvpGuestCount == 1 ? "" : "s")",
                            value: $rsvpGuestCount, in: 1...20)
                }
            }
            if detail.rsvpShowNotes {
                field("Notes") {
                    TextField("Any questions…", text: $rsvpNotes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            if let rsvpError = vm.rsvpError {
                Text(rsvpError).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                onSubmit()
            } label: {
                Group {
                    if vm.isSubmittingRSVP {
                        HStack(spacing: 8) {
                            ProgressView().tint(.white).controlSize(.small)
                            Text("Submitting…")
                        }
                    } else {
                        Text("Submit RSVP")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isFormValid || vm.isSubmittingRSVP)
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            content()
                .padding(10)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
