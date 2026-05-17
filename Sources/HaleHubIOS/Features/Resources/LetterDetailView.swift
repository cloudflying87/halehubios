import SwiftUI

// MARK: - ViewModel

@MainActor
class LetterDetailViewModel: ObservableObject {
    @Published var detail: LetterDetail?
    @Published var isLoading = false
    @Published var error: String?
    @Published var rsvpSuccess = false
    @Published var rsvpError: String?
    @Published var isSubmittingRSVP = false

    func load(slug: String, token: String) async {
        isLoading = true
        error = nil
        do {
            detail = try await APIClient.shared.get("/letters/\(slug)/", token: token)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func submitRSVP(slug: String, rsvp: RSVPRequest, token: String) async {
        isSubmittingRSVP = true
        rsvpError = nil
        do {
            let response: RSVPResponse = try await APIClient.shared.post(
                "/letters/\(slug)/rsvp/",
                body: rsvp,
                token: token
            )
            rsvpSuccess = response.success
            if !response.success {
                rsvpError = response.message
            }
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {

                        // MARK: Event Info Banner
                        if let eventDate = detail.eventDate, !eventDate.isEmpty {
                            EventInfoBanner(detail: detail)
                        }

                        // MARK: Greeting Message
                        if !detail.greetingMessage.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                MarkdownContentView(content: detail.greetingMessage)
                            }
                        }

                        // MARK: Photo Gallery
                        if !detail.photos.isEmpty {
                            PhotoGallerySection(photos: detail.photos, onTap: { photo in
                                selectedPhoto = photo
                            })
                        }

                        // MARK: RSVP Section
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
                                onSubmit: {
                                    Task { await submitRSVP(detail: detail) }
                                }
                            )
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(20)
                }
            } else {
                // detail is nil but not loading — shouldn't happen, but handle gracefully
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(letter.title)
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selectedPhoto) { photo in
            PhotoFullScreenView(photo: photo)
        }
        .task { await vm.load(slug: letter.slug, token: auth.accessToken ?? "") }
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
        if vm.rsvpSuccess {
            showRSVPForm = false
        }
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
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !detail.eventLocation.isEmpty {
                Label(detail.eventLocation, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
    }

    private func formattedDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Photo Gallery Section

private struct PhotoGallerySection: View {
    let photos: [LetterPhoto]
    let onTap: (LetterPhoto) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Photos")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(photos.sorted { $0.order < $1.order }, id: \.url) { photo in
                    PhotoThumbnail(photo: photo)
                        .onTapGesture { onTap(photo) }
                }
            }
        }
    }
}

private struct PhotoThumbnail: View {
    let photo: LetterPhoto

    var body: some View {
        Group {
            if let url = URL(string: photo.url) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        photoPlaceholder
                    default:
                        Color(.systemGray5)
                            .overlay(ProgressView())
                    }
                }
            } else {
                photoPlaceholder
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var photoPlaceholder: some View {
        Color(.systemGray5)
            .overlay(
                Image(systemName: "photo")
                    .foregroundStyle(.tertiary)
                    .font(.title2)
            )
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

                if let url = URL(string: photo.url) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        case .failure:
                            Image(systemName: "photo.slash")
                                .font(.largeTitle)
                                .foregroundStyle(.white.opacity(0.5))
                        default:
                            ProgressView()
                                .tint(.white)
                        }
                    }
                } else {
                    Image(systemName: "photo.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if !photo.caption.isEmpty {
                    Text(photo.caption)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
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
            // Section header
            VStack(alignment: .leading, spacing: 4) {
                Text(detail.rsvpTitle.isEmpty ? "RSVP" : detail.rsvpTitle)
                    .font(.headline)
                if !detail.rsvpSubtitle.isEmpty {
                    Text(detail.rsvpSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if vm.rsvpSuccess {
                // Success state
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("You're on the list! See you there.")
                        .font(.subheadline)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            } else if !showRSVPForm {
                Button {
                    showRSVPForm = true
                } label: {
                    Label("Submit RSVP", systemImage: "person.crop.circle.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                RSVPFormFields(
                    detail: detail,
                    vm: vm,
                    rsvpName: $rsvpName,
                    rsvpEmail: $rsvpEmail,
                    rsvpPhone: $rsvpPhone,
                    rsvpGuestCount: $rsvpGuestCount,
                    rsvpNotes: $rsvpNotes,
                    onSubmit: onSubmit
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

    var isFormValid: Bool {
        !rsvpName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 12) {
            // Name — always shown
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("Your name", text: $rsvpName)
                    .textContentType(.name)
                    .padding(10)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
            }

            // Email — conditional
            if detail.rsvpShowEmail {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Email")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("email@example.com", text: $rsvpEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(10)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            // Phone — conditional
            if detail.rsvpShowPhone {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Phone")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("(555) 000-0000", text: $rsvpPhone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .padding(10)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            // Guest count — conditional
            if detail.rsvpShowGuestCount {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Number of Guests")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Stepper("\(rsvpGuestCount) guest\(rsvpGuestCount == 1 ? "" : "s")",
                            value: $rsvpGuestCount, in: 1...20)
                        .padding(10)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            // Notes — conditional
            if detail.rsvpShowNotes {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("Any notes or questions…", text: $rsvpNotes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .padding(10)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            // Error message
            if let rsvpError = vm.rsvpError {
                Text(rsvpError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Submit button
            Button {
                onSubmit()
            } label: {
                Group {
                    if vm.isSubmittingRSVP {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                                .controlSize(.small)
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
}

// MARK: - LetterPhoto Identifiable conformance for sheet(item:)

extension LetterPhoto: Identifiable {
    var id: String { url }
}
