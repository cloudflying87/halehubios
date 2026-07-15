import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Helpers

enum PayTripType: String, CaseIterable, Identifiable {
    case regular, green, sick, override
    var id: String { rawValue }
    var label: String {
        switch self {
        case .regular: return "Regular"
        case .green: return "Green Slip"
        case .sick: return "Sick"
        case .override: return "Override / Extra"
        }
    }
    var color: Color {
        switch self {
        case .regular: return .primary
        case .green: return .green
        case .sick: return .orange
        case .override: return .blue
        }
    }
}

private func monthName(_ n: Int) -> String {
    let symbols = DateFormatter().monthSymbols ?? []
    return (1...12).contains(n) ? symbols[n - 1] : "\(n)"
}

// MARK: - Hours / minutes entry

/// Parse a time expression into decimal hours. Accepts a decimal ("26.92"),
/// H:MM ("26:53" → 26.88), or several of either summed with "+"
/// ("2:15 + 1:30" → 3.75). Returns nil if any token is unparseable.
func parseHoursExpression(_ raw: String) -> Double? {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return 0 }
    var total = 0.0
    for part in trimmed.split(separator: "+") {
        let tok = part.trimmingCharacters(in: .whitespaces)
        if tok.isEmpty { continue }
        if tok.contains(":") {
            // Keep empty sides so a lone/partial colon (":", ":30", "26:") never
            // index-crashes; treat a blank hour or minute as 0.
            let hm = tok.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let hPart = hm[0].trimmingCharacters(in: .whitespaces)
            let mPart = hm.count > 1 ? hm[1].trimmingCharacters(in: .whitespaces) : ""
            guard let h = hPart.isEmpty ? 0 : Double(hPart),
                  let mins = mPart.isEmpty ? 0 : Double(mPart) else { return nil }
            total += h + mins / 60.0
        } else {
            guard let d = Double(tok) else { return nil }
            total += d
        }
    }
    // Round to 2 decimals — H:MM math yields repeating decimals (26:53 → 26.8833…),
    // and the backend hours field only stores 2 places (max_digits 7), so send the
    // rounded value rather than full precision.
    return (total * 100).rounded() / 100
}

private func formatHours(_ value: Double) -> String {
    value == 0 ? "" : String(format: "%g", (value * 100).rounded() / 100)
}

/// A labelled field that accepts decimal or H:MM (and sums with "+"), showing
/// the converted decimal live beneath it.
struct HoursMinutesField: View {
    let title: String
    @Binding var value: Double
    @State private var text: String

    init(title: String, value: Binding<Double>) {
        self.title = title
        _value = value
        _text = State(initialValue: formatHours(value.wrappedValue))
    }

    private var parsed: Double? { parseHoursExpression(text) }
    private var showsConversion: Bool { text.contains(":") || text.contains("+") }

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            HStack {
                Text(title)
                Spacer()
                TextField("0:00", text: $text)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .onChange(of: text) { if let v = parsed { value = v } }
            }
            if showsConversion, let v = parsed {
                Text(String(format: "= %.2f hrs", v))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// The four pay components of a trip, all credited toward pay.
struct TripPayInput: Sendable {
    var credit: Double
    var additional: Double
    var green: Double
    var reroute: Double

    var totalCredit: Double { credit + additional + green + reroute }
}

/// Shared Credit / Additional / Green / Reroute inputs for Add & Edit sheets.
struct TripFormFields: View {
    @Binding var credit: Double
    @Binding var additional: Double
    @Binding var green: Double
    @Binding var reroute: Double
    @Binding var type: PayTripType
    @Binding var tripNumber: String
    @Binding var label: String

    private var total: Double {
        credit + additional + reroute + (type == .green ? green : 0)
    }

    var body: some View {
        Section("Trip") {
            HoursMinutesField(title: "Credit", value: $credit)
            Picker("Type", selection: $type) {
                ForEach(PayTripType.allCases) { Text($0.label).tag($0) }
            }
            TextField("Trip # (e.g. 7779)", text: $tripNumber)
                .keyboardType(.numbersAndPunctuation)
            TextField("Note (optional)", text: $label)
        }
        Section("Additional Pay") {
            HoursMinutesField(title: "Additional pay", value: $additional)
            HoursMinutesField(title: "Reroute pay", value: $reroute)
            if type == .green {
                HoursMinutesField(title: "Green slip pay", value: $green)
            }
        }
        Section {
            HStack {
                Text("Total credit").fontWeight(.semibold)
                Spacer()
                Text(String(format: "%.2f hrs", total)).fontWeight(.semibold)
            }
            Text("Enter times as a decimal (26.92) or H:MM (26:53). Add several with “+”, e.g. 2:15 + 1:30.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - View Model

@MainActor
final class PayHoursViewModel: ObservableObject {
    @Published var summary: PaySummary?
    @Published var isLoading = false
    @Published var error: String?
    @Published var importMessage: String?
    @Published var year: Int

    init() {
        year = Calendar.current.component(.year, from: Date())
    }

    func load(token: String) async {
        isLoading = true
        error = nil
        do {
            summary = try await APIClient.shared.get("/finance/pay/summary/?year=\(year)", token: token)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func step(_ delta: Int) { year += delta }

    func importXlsx(data: Data, filename: String, token: String) async {
        do {
            let s: PayImportSummary = try await APIClient.shared.uploadData(
                "/finance/pay/import/", data: data, filename: filename, fieldName: "file",
                mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                token: token
            )
            importMessage = "Imported \(s.tripsCreated) trips across \(s.monthsImported) months "
                + "(\(s.greenSlips) green slips), years \(s.years.map(String.init).joined(separator: ", "))."
            await load(token: token)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Pay Hours (year grid)

struct PayHoursView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = PayHoursViewModel()
    @State private var showImporter = false

    private var token: String { auth.accessToken ?? "" }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                yearSelector
                if let s = vm.summary {
                    monthsCard(s)
                    totalsCard(s)
                    breakdownCard(s)
                } else if vm.isLoading {
                    ProgressView("Loading…").frame(maxWidth: .infinity, minHeight: 160)
                }
            }
            .padding(16)
        }
        .navigationTitle("Pay Hours")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink(destination: PayActualView()) {
                        Label("Hours vs Actual Pay", systemImage: "dollarsign.arrow.circlepath")
                    }
                    NavigationLink(destination: PayCompareView()) {
                        Label("Compare to ALV", systemImage: "chart.bar.xaxis")
                    }
                    NavigationLink(destination: PayRatesView()) {
                        Label("Pay Rates", systemImage: "dollarsign.circle")
                    }
                    NavigationLink(destination: KeepLoggingConnectView()) {
                        Label("keep-logging (ALV)", systemImage: "airplane")
                    }
                    Button { showImporter = true } label: {
                        Label("Import .xlsx", systemImage: "square.and.arrow.down")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.spreadsheet]) { result in
            handleImport(result)
        }
        .task { await vm.load(token: token) }
        .onChange(of: vm.year) { Task { await vm.load(token: token) } }
        .refreshable { await vm.load(token: token) }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
        .alert("Import complete", isPresented: .init(get: { vm.importMessage != nil }, set: { if !$0 { vm.importMessage = nil } })) {
            Button("OK") {}
        } message: { Text(vm.importMessage ?? "") }
    }

    private var yearSelector: some View {
        HStack {
            Button { vm.step(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(String(vm.year)).font(.headline)
            Spacer()
            Button { vm.step(1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal, 4)
    }

    private func monthsCard(_ s: PaySummary) -> some View {
        VStack(spacing: 0) {
            ForEach(s.months) { row in
                NavigationLink(destination: PayMonthDetailView(year: s.year, monthNum: row.monthNum)) {
                    HStack {
                        Text(monthName(row.monthNum)).font(.subheadline)
                            .frame(width: 92, alignment: .leading)
                        if row.green > 0 {
                            Image(systemName: "leaf.fill").font(.caption2).foregroundStyle(.green)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(row.totalCredit > 0 ? String(format: "%.2f hrs", row.totalCredit) : "—")
                                .font(.subheadline)
                                .foregroundStyle(row.totalCredit > 0 ? .primary : .tertiary)
                            if let pay = row.estimatedPay, pay > 0 {
                                Text(LoanFormatters.money(pay, fractionDigits: 0))
                                    .font(.caption).foregroundStyle(.green)
                            }
                        }
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
        .padding(.horizontal, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func totalsCard(_ s: PaySummary) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text("Total").font(.subheadline).fontWeight(.semibold)
                Spacer()
                Text(String(format: "%.2f hrs", s.totals.creditHours)).font(.subheadline).fontWeight(.semibold)
                Text(LoanFormatters.money(s.totals.estimatedPay, fractionDigits: 0))
                    .font(.subheadline).foregroundStyle(.green).frame(width: 90, alignment: .trailing)
            }
            HStack {
                Text("Average / month").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f hrs", s.averages.creditHours)).font(.subheadline).foregroundStyle(.secondary)
                Text(LoanFormatters.money(s.averages.estimatedPay, fractionDigits: 0))
                    .font(.subheadline).foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// Year totals split by pay component (credit / additional / green / reroute).
    @ViewBuilder private func breakdownCard(_ s: PaySummary) -> some View {
        let t = s.totals
        let credit: Double = t.credit ?? 0
        let additional: Double = t.additional ?? 0
        let green: Double = t.green ?? 0
        let reroute: Double = t.reroute ?? 0
        let sum: Double = credit + additional + green + reroute
        if sum > 0 {
            VStack(spacing: 10) {
                HStack {
                    Text("Pay Breakdown (\(String(s.year)))").font(.subheadline).fontWeight(.semibold)
                    Spacer()
                }
                componentRow("Credit", credit, .primary)
                componentRow("Additional pay", additional, .blue)
                componentRow("Green slip pay", green, .green)
                componentRow("Reroute pay", reroute, .orange)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func componentRow(_ label: String, _ hours: Double, _ color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "%.2f hrs", hours)).font(.subheadline)
                .foregroundStyle(hours > 0 ? .primary : .tertiary)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else {
            if case .failure(let e) = result { vm.error = e.localizedDescription }
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            vm.error = "Couldn't read that file."
            return
        }
        Task { await vm.importXlsx(data: data, filename: url.lastPathComponent, token: token) }
    }
}

// MARK: - Month detail (trips)

@MainActor
final class PayMonthViewModel: ObservableObject {
    @Published var trips: [PayTrip] = []
    @Published var detail: PayMonthDetail?
    @Published var cards: [PayScreenshotRef] = []
    @Published var isLoading = false
    @Published var error: String?

    func load(year: Int, monthNum: Int, token: String) async {
        isLoading = true
        error = nil
        let m = String(format: "%04d-%02d", year, monthNum)
        do {
            trips = try await APIClient.shared.get("/finance/pay/trips/?month=\(m)", token: token)
        } catch {
            self.error = error.localizedDescription
        }
        // Best-effort: keep-logging may be unconfigured/slow; don't block the trip list.
        detail = try? await APIClient.shared.get("/finance/pay/month-detail/?year=\(year)&month=\(monthNum)", token: token)
        cards = (try? await APIClient.shared.get("/finance/pay/screenshots/?month=\(m)", token: token)) ?? []
        isLoading = false
    }

    func add(month: String, pay: TripPayInput, type: PayTripType, tripNumber: String, label: String, token: String) async -> Bool {
        do {
            let req = PayTripRequest(month: month, hours: pay.credit, additionalHours: pay.additional,
                                     greenHours: pay.green, rerouteHours: pay.reroute,
                                     tripType: type.rawValue, tripNumber: tripNumber,
                                     label: label.isEmpty ? nil : label)
            let _: PayTrip = try await APIClient.shared.post("/finance/pay/trips/", body: req, token: token)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func setType(_ trip: PayTrip, _ type: PayTripType, token: String) async {
        do {
            let _: PayTrip = try await APIClient.shared.patch("/finance/pay/trips/\(trip.id)/", body: PayTripPatch(tripType: type.rawValue), token: token)
        } catch { self.error = error.localizedDescription }
    }

    func update(_ trip: PayTrip, pay: TripPayInput, type: PayTripType, tripNumber: String, label: String, token: String) async -> Bool {
        do {
            let req = PayTripEditRequest(hours: pay.credit, additionalHours: pay.additional,
                                         greenHours: pay.green, rerouteHours: pay.reroute,
                                         tripType: type.rawValue, tripNumber: tripNumber, label: label)
            let _: PayTrip = try await APIClient.shared.patch("/finance/pay/trips/\(trip.id)/", body: req, token: token)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func delete(_ trip: PayTrip, token: String) async {
        do { try await APIClient.shared.delete("/finance/pay/trips/\(trip.id)/", token: token) }
        catch { self.error = error.localizedDescription }
    }

    /// Send a pay-register screenshot to the server; Claude vision returns the
    /// parsed trips for review (nothing saved yet).
    func parseScreenshot(_ imageData: Data, month: String, token: String) async -> PayScreenshotResult? {
        do {
            return try await APIClient.shared.uploadData(
                "/finance/pay/parse-screenshot/?month=\(month)",
                data: imageData, filename: "card.jpg", fieldName: "image",
                mimeType: "image/jpeg", token: token
            )
        } catch { self.error = error.localizedDescription; return nil }
    }

    /// Save reviewed screenshot trips into the month in one request.
    func bulkSave(month: String, trips: [PayParsedTrip], token: String) async -> Bool {
        let rows = trips.map {
            PayBulkTripRequest(
                tripDate: $0.date, hours: $0.credit, additionalHours: $0.additional,
                greenHours: $0.green, rerouteHours: $0.reroute,
                tripType: $0.tripType, tripNumber: $0.tripNumber, label: $0.label
            )
        }
        do {
            let req = PayBulkTripsRequest(month: month, replace: false, trips: rows)
            let _: PayBulkTripsResponse = try await APIClient.shared.post(
                "/finance/pay/bulk-trips/", body: req, token: token)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}

struct PayMonthDetailView: View {
    let year: Int
    let monthNum: Int
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = PayMonthViewModel()
    @State private var showAdd = false
    @State private var editingTrip: PayTrip?
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var parsing = false
    @State private var reviewResult: PayScreenshotResult?
    @State private var viewingCard: PayScreenshotRef?

    private var token: String { auth.accessToken ?? "" }
    private var monthString: String { String(format: "%04d-%02d", year, monthNum) }
    private var totalCredit: Double { vm.trips.reduce(0) { $0 + $1.creditHours } }
    private var creditTotal: Double { vm.trips.reduce(0) { $0 + $1.hours } }
    private var additionalTotal: Double { vm.trips.reduce(0) { $0 + $1.additionalHours } }
    private var greenTotal: Double { vm.trips.reduce(0) { $0 + $1.greenHours } }
    private var rerouteTotal: Double { vm.trips.reduce(0) { $0 + $1.rerouteHours } }
    /// Estimated Delta pay for the month (credit × rate), when a rate is known.
    private var estimatedPay: Double? { vm.detail?.paycheck.fullPay }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Total credit").fontWeight(.semibold)
                    Spacer()
                    Text(String(format: "%.2f hrs", totalCredit)).fontWeight(.semibold)
                    if let pay = estimatedPay {
                        Text(LoanFormatters.money(pay, fractionDigits: 0))
                            .fontWeight(.semibold).foregroundStyle(.green)
                            .frame(minWidth: 80, alignment: .trailing)
                    }
                }
            }
            if totalCredit > 0 {
                Section("Pay Breakdown") {
                    breakdownRow("Credit", creditTotal, .primary)
                    if additionalTotal > 0 { breakdownRow("Additional pay", additionalTotal, .blue) }
                    if greenTotal > 0 { breakdownRow("Green slip pay", greenTotal, .green) }
                    if rerouteTotal > 0 { breakdownRow("Reroute pay", rerouteTotal, .orange) }
                }
            }
            payAndAlvSection
            Section("Trips") {
                if vm.trips.isEmpty {
                    Text("No trips yet.").foregroundStyle(.secondary)
                }
                ForEach(vm.trips) { trip in
                    Button { editingTrip = trip } label: { tripRow(trip) }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await vm.delete(trip, token: token); await vm.load(year: year, monthNum: monthNum, token: token) }
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                }
            }
            if !vm.cards.isEmpty {
                Section("Card Images") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(vm.cards) { card in
                                Button { viewingCard = card } label: {
                                    AsyncImage(url: card.url.flatMap(URL.init)) { img in
                                        img.resizable().scaledToFill()
                                    } placeholder: {
                                        ProgressView()
                                    }
                                    .frame(width: 90, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("\(monthName(monthNum)) \(String(year))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showAdd = true } label: { Label("Add Trip", systemImage: "plus") }
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        Label("Import from Screenshot", systemImage: "camera.viewfinder")
                    }
                } label: {
                    if parsing { ProgressView() } else { Image(systemName: "plus") }
                }
                .disabled(parsing)
            }
        }
        .onChange(of: pickedPhoto) { Task { await handlePickedPhoto() } }
        .sheet(item: $reviewResult) { result in
            ScreenshotReviewSheet(result: result, monthString: monthString) { trips in
                let ok = await vm.bulkSave(month: monthString, trips: trips, token: token)
                if ok { await vm.load(year: year, monthNum: monthNum, token: token) }
                return ok
            }
        }
        .sheet(item: $viewingCard) { card in
            NavigationStack {
                ScrollView([.horizontal, .vertical]) {
                    AsyncImage(url: card.url.flatMap(URL.init)) { img in
                        img.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView()
                    }
                }
                .navigationTitle("Pay Card")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { viewingCard = nil }
                    }
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddTripSheet(month: monthString) { pay, type, tripNumber, label in
                let ok = await vm.add(month: monthString, pay: pay, type: type, tripNumber: tripNumber, label: label, token: token)
                if ok { await vm.load(year: year, monthNum: monthNum, token: token) }
                return ok
            }
        }
        .sheet(item: $editingTrip) { trip in
            EditTripSheet(trip: trip) { pay, type, tripNumber, label in
                let ok = await vm.update(trip, pay: pay, type: type, tripNumber: tripNumber, label: label, token: token)
                if ok { await vm.load(year: year, monthNum: monthNum, token: token) }
                return ok
            }
        }
        .task { await vm.load(year: year, monthNum: monthNum, token: token) }
        .refreshable { await vm.load(year: year, monthNum: monthNum, token: token) }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
    }

    private func handlePickedPhoto() async {
        guard let item = pickedPhoto else { return }
        pickedPhoto = nil
        parsing = true
        defer { parsing = false }
        guard let raw = try? await item.loadTransferable(type: Data.self) else {
            vm.error = "Couldn't read that image."
            return
        }
        // Downsample before upload — a screenshot doesn't need full resolution to
        // read, and this cuts upload size + vision tokens roughly in half.
        let data = Self.downsampledJPEG(raw) ?? raw
        if let result = await vm.parseScreenshot(data, month: monthString, token: token) {
            reviewResult = result
        }
    }

    /// Resize to a max long edge and re-encode as JPEG. Returns nil if the data
    /// isn't a decodable image (caller falls back to the original bytes).
    static func downsampledJPEG(_ data: Data, maxDimension: CGFloat = 1400,
                                quality: CGFloat = 0.7) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image.jpegData(compressionQuality: quality) }
        let scale = maxDimension / longest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    private func breakdownRow(_ label: String, _ hours: Double, _ color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "%.2f hrs", hours)).fontWeight(.medium)
        }
    }

    private func tripRow(_ trip: PayTrip) -> some View {
        let type = PayTripType(rawValue: trip.tripType) ?? .regular
        // Components beyond base credit, shown as small tags on the row.
        let extras: [(String, Double)] = [
            ("+add", trip.additionalHours),
            ("+green", trip.greenHours),
            ("+rrt", trip.rerouteHours),
        ].filter { $0.1 > 0 }
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if !trip.tripNumber.isEmpty {
                        Text("#\(trip.tripNumber)").font(.subheadline.weight(.semibold))
                    }
                    Text(String(format: "%.2f hrs credit", trip.hours))
                        .font(.subheadline)
                        .foregroundStyle(trip.tripNumber.isEmpty ? .primary : .secondary)
                }
                if !extras.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(extras, id: \.0) { name, val in
                            Text("\(name) \(String(format: "%.2f", val))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                if !trip.label.isEmpty {
                    Text(trip.label).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(String(format: "%.2f", trip.creditHours)).font(.caption).foregroundStyle(.secondary)
            Text(type.label)
                .font(.caption2)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(type.color.opacity(0.15))
                .clipShape(Capsule())
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var payAndAlvSection: some View {
        if let d = vm.detail {
            let kl = d.keeplogging
            // Rate + estimated pay — always shown when a rate is known.
            Section("Estimated Pay") {
                if let rate = d.paycheck.rate {
                    payRow("Pay rate", LoanFormatters.money(rate) + "/hr")
                    if let full = d.paycheck.fullPay {
                        payRow("Estimated pay (month)", LoanFormatters.money(full))
                    }
                } else {
                    Text("Add a pay rate (Pay Hours ⋯ → Pay Rates) or connect keep-logging to estimate pay.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if kl.connected {
                Section("ALV & Paycheck Split") {
                    if let alv = kl.alv {
                        payRow("ALV (target)", String(format: "%.2f hrs", alv))
                        let diff = d.halehubCredit - alv
                        HStack {
                            Text(diff >= 0 ? "Over the line" : "Under the line").foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%+.2f hrs", diff))
                                .fontWeight(.semibold)
                                .foregroundStyle(diff >= 0 ? .green : .orange)
                        }
                    } else {
                        Text("No ALV for this month (keep-logging covers 2024 on).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let rsv = kl.reserveGuarantee { payRow("Reserve guarantee", String(format: "%.2f hrs", rsv)) }
                    if let adv = d.paycheck.advance { payRow("Last check (this month)", LoanFormatters.money(adv)) }
                    if let rem = d.paycheck.remainder { payRow("Mid next month", LoanFormatters.money(rem)) }
                    if kl.creditAvailable, let klc = kl.monthlyCredit {
                        payRow("keep-logging credit", String(format: "%.2f hrs", klc))
                    }
                    if let err = kl.error, !err.isEmpty {
                        Text(err).font(.caption).foregroundStyle(.orange)
                    }
                }
            } else {
                Section {
                    NavigationLink(destination: KeepLoggingConnectView()) {
                        Label("Connect keep-logging for ALV", systemImage: "link")
                    }
                }
            }
        }
    }

    private func payRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
    }
}

struct EditTripSheet: View {
    let trip: PayTrip
    let onSave: (TripPayInput, PayTripType, String, String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var credit: Double
    @State private var additional: Double
    @State private var green: Double
    @State private var reroute: Double
    @State private var type: PayTripType
    @State private var tripNumber: String
    @State private var label: String
    @State private var saving = false

    init(trip: PayTrip, onSave: @escaping (TripPayInput, PayTripType, String, String) async -> Bool) {
        self.trip = trip
        self.onSave = onSave
        _credit = State(initialValue: trip.hours)
        _additional = State(initialValue: trip.additionalHours)
        _green = State(initialValue: trip.greenHours)
        _reroute = State(initialValue: trip.rerouteHours)
        _type = State(initialValue: PayTripType(rawValue: trip.tripType) ?? .regular)
        _tripNumber = State(initialValue: trip.tripNumber)
        _label = State(initialValue: trip.label)
    }

    private var payload: TripPayInput {
        TripPayInput(credit: credit, additional: additional,
                     green: type == .green ? green : 0, reroute: reroute)
    }

    var body: some View {
        NavigationStack {
            Form {
                TripFormFields(credit: $credit, additional: $additional, green: $green,
                               reroute: $reroute, type: $type, tripNumber: $tripNumber, label: $label)
            }
            .navigationTitle("Edit Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { saving = true; let ok = await onSave(payload, type, tripNumber, label); saving = false; if ok { dismiss() } }
                    }
                    .disabled(saving || payload.totalCredit <= 0)
                }
            }
        }
    }
}

struct AddTripSheet: View {
    let month: String
    let onSave: (TripPayInput, PayTripType, String, String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var credit: Double = 0
    @State private var additional: Double = 0
    @State private var green: Double = 0
    @State private var reroute: Double = 0
    @State private var type: PayTripType = .regular
    @State private var tripNumber = ""
    @State private var label = ""
    @State private var saving = false

    private var payload: TripPayInput {
        TripPayInput(credit: credit, additional: additional,
                     green: type == .green ? green : 0, reroute: reroute)
    }

    var body: some View {
        NavigationStack {
            Form {
                TripFormFields(credit: $credit, additional: $additional, green: $green,
                               reroute: $reroute, type: $type, tripNumber: $tripNumber, label: $label)
            }
            .navigationTitle("Add Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { saving = true; let ok = await onSave(payload, type, tripNumber, label); saving = false; if ok { dismiss() } }
                    }
                    .disabled(saving || payload.totalCredit <= 0)
                }
            }
        }
    }
}

// MARK: - Screenshot import review

/// Review the trips Claude extracted from a pay-register screenshot before
/// saving them. Trip # and type are editable; rows can be deleted.
struct ScreenshotReviewSheet: View {
    let result: PayScreenshotResult
    let monthString: String
    let onSave: ([PayParsedTrip]) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var trips: [PayParsedTrip]
    @State private var saving = false

    init(result: PayScreenshotResult, monthString: String,
         onSave: @escaping ([PayParsedTrip]) async -> Bool) {
        self.result = result
        self.monthString = monthString
        self.onSave = onSave
        _trips = State(initialValue: result.trips)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if result.totalsMatch {
                        Label("Credit total matches the card — \(String(format: "%.2f", result.computedTotalCredit)) hrs",
                              systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green).font(.caption)
                    } else {
                        Label("Check the numbers — parsed \(String(format: "%.2f", result.computedTotalCredit)) hrs vs card \(result.printedTotalCredit.map { String(format: "%.2f", $0) } ?? "—")",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).font(.caption)
                    }
                    ForEach(result.warnings, id: \.self) { w in
                        Text(w).font(.caption).foregroundStyle(.orange)
                    }
                }
                Section("Trips (\(trips.count))") {
                    if trips.isEmpty {
                        Text("No trips to save.").foregroundStyle(.secondary)
                    }
                    ForEach($trips) { $t in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                TextField("Trip #", text: $t.tripNumber)
                                    .font(.subheadline.weight(.semibold))
                                    .keyboardType(.numbersAndPunctuation)
                                Spacer()
                                Picker("", selection: $t.tripType) {
                                    ForEach(PayTripType.allCases) { Text($0.label).tag($0.rawValue) }
                                }
                                .labelsHidden()
                            }
                            HStack(spacing: 12) {
                                metric("credit", t.creditHmm)
                                if t.additional > 0 { metric("add", t.additionalHmm) }
                                if t.reroute > 0 { metric("rrt", t.rerouteHmm) }
                                if t.green > 0 { metric("green", t.greenHmm) }
                                Spacer()
                                if let d = t.date {
                                    Text(d).font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { trips.remove(atOffsets: $0) }
                }
            }
            .navigationTitle("Review Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save \(trips.count)") {
                        Task { saving = true; let ok = await onSave(trips); saving = false; if ok { dismiss() } }
                    }
                    .disabled(saving || trips.isEmpty)
                }
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value.isEmpty ? "0:00" : value).font(.caption2.weight(.medium))
        }
    }
}

// MARK: - Hours vs Actual Pay

/// Credit hours next to what actually landed in paychecks that year — no
/// estimated rate. The effective rate is derived from real pay ÷ hours.
struct PayActualView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var data: PayActualComparison?
    @State private var loading = false
    @State private var error: String?

    private var token: String { auth.accessToken ?? "" }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                yearSelector
                if let d = data {
                    totalsCard(d.totals)
                    monthsCard(d)
                    Text("Pilot pay for a month's credit lands across that month's last check and mid the next month, so months won't line up exactly — the year totals are the real comparison.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                } else if loading {
                    ProgressView("Loading…").frame(maxWidth: .infinity, minHeight: 160)
                }
            }
            .padding(16)
        }
        .navigationTitle("Hours vs Pay")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: year) { Task { await load() } }
        .refreshable { await load() }
        .alert("Error", isPresented: .init(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }

    private var yearSelector: some View {
        HStack {
            Button { year -= 1 } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(String(year)).font(.headline)
            Spacer()
            Button { year += 1 } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal, 4)
    }

    private func totalsCard(_ t: PayActualTotals) -> some View {
        VStack(spacing: 10) {
            row("Credit hours", String(format: "%.2f hrs", t.creditHours))
            row("Actual pay (gross)", LoanFormatters.money(t.actualGross, fractionDigits: 0))
            row("Take-home (net)", LoanFormatters.money(t.actualNet, fractionDigits: 0))
            if let r = t.effectiveRate {
                Divider()
                HStack {
                    Text("Effective rate").fontWeight(.semibold)
                    Spacer()
                    Text(LoanFormatters.money(r) + "/hr")
                        .fontWeight(.semibold).foregroundStyle(.green)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func monthsCard(_ d: PayActualComparison) -> some View {
        VStack(spacing: 0) {
            let rows = d.months.filter { $0.creditHours > 0 || ($0.actualGross ?? 0) > 0 }
            if rows.isEmpty {
                Text("No hours or paychecks for \(String(year)).")
                    .foregroundStyle(.secondary).padding(.vertical, 20)
            }
            ForEach(rows) { m in
                HStack {
                    Text(monthName(m.monthNum)).font(.subheadline)
                        .frame(width: 90, alignment: .leading)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(String(format: "%.2f hrs", m.creditHours)).font(.subheadline)
                        if let g = m.actualGross {
                            Text(LoanFormatters.money(g, fractionDigits: 0))
                                .font(.caption).foregroundStyle(.green)
                        } else {
                            Text("no paycheck yet").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.vertical, 10)
                Divider()
            }
        }
        .padding(.horizontal, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            data = try await APIClient.shared.get(
                "/finance/pay/actual-comparison/?year=\(year)", token: token)
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Pay Rates

@MainActor
final class PayRatesViewModel: ObservableObject {
    @Published var rates: [PayRate] = []
    @Published var error: String?

    func load(token: String) async {
        do { rates = try await APIClient.shared.get("/finance/pay/rates/", token: token) }
        catch { self.error = error.localizedDescription }
    }
    func add(effective: String, rate: Double, token: String) async -> Bool {
        do {
            let req = PayRateRequest(effectiveDate: effective, hourlyRate: rate, note: nil)
            let _: PayRate = try await APIClient.shared.post("/finance/pay/rates/", body: req, token: token)
            await load(token: token); return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func update(_ r: PayRate, effective: String, rate: Double, token: String) async -> Bool {
        do {
            // note: "manual" marks it as corrected so it's no longer labeled keep-logging
            let req = PayRateRequest(effectiveDate: effective, hourlyRate: rate, note: "manual")
            let _: PayRate = try await APIClient.shared.patch("/finance/pay/rates/\(r.id)/", body: req, token: token)
            await load(token: token); return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func delete(_ r: PayRate, token: String) async {
        do { try await APIClient.shared.delete("/finance/pay/rates/\(r.id)/", token: token); await load(token: token) }
        catch { self.error = error.localizedDescription }
    }
}

struct PayRatesView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = PayRatesViewModel()
    @State private var showAdd = false
    @State private var editingRate: PayRate?
    private var token: String { auth.accessToken ?? "" }

    var body: some View {
        List {
            Section {
                Text("Each rate stays in effect until a newer one starts. Months use the rate active at the time. Tap a rate to edit it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(vm.rates) { r in
                Button { editingRate = r } label: {
                    HStack {
                        Text(LoanFormatters.fullDate(r.effectiveDate))
                        Spacer()
                        Text(LoanFormatters.money(r.hourlyRate) + "/hr").fontWeight(.medium)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(role: .destructive) { Task { await vm.delete(r, token: token) } } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .navigationTitle("Pay Rates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } }
        }
        .sheet(isPresented: $showAdd) {
            RateSheet(title: "Add Rate") { eff, rate in
                await vm.add(effective: eff, rate: rate, token: token)
            }
        }
        .sheet(item: $editingRate) { r in
            RateSheet(title: "Edit Rate", initialDate: r.effectiveDate, initialRate: r.hourlyRate) { eff, rate in
                await vm.update(r, effective: eff, rate: rate, token: token)
            }
        }
        .task { await vm.load(token: token) }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
    }
}

struct RateSheet: View {
    let title: String
    var initialDate: String? = nil
    var initialRate: Double = 0
    let onSave: (String, Double) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var rate: Double = 0
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Effective from", selection: $date, displayedComponents: .date)
                HStack {
                    Text("Rate / hour"); Spacer()
                    TextField("Rate", value: $rate, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { saving = true; let ok = await onSave(LoanFormatters.ymd(date), rate); saving = false; if ok { dismiss() } }
                    }
                    .disabled(saving || rate <= 0)
                }
            }
            .onAppear {
                rate = initialRate
                if let iso = initialDate, let d = LoanFormatters.parseYMD(iso) { date = d }
            }
        }
    }
}

// MARK: - keep-logging connect

@MainActor
final class KeepLoggingViewModel: ObservableObject {
    @Published var status: KeepLoggingStatus?
    @Published var busy = false
    @Published var error: String?
    @Published var message: String?

    func load(token: String) async {
        status = try? await APIClient.shared.get("/finance/keeplogging/settings/", token: token)
    }

    func connect(username: String, password: String, token: String) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            let req = KLConnectRequest(username: username, password: password)
            status = try await APIClient.shared.post("/finance/keeplogging/connect/", body: req, token: token)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func disconnect(token: String) async {
        do {
            try await APIClient.shared.delete("/finance/keeplogging/settings/", token: token)
            await load(token: token)
        } catch { self.error = error.localizedDescription }
    }

    func syncRate(token: String) async {
        busy = true
        defer { busy = false }
        do {
            struct Result: Decodable, Sendable { let effectiveDate: String; let hourlyRate: Double }
            let r: Result = try await APIClient.shared.postEmpty("/finance/keeplogging/sync-rate/", token: token)
            message = "Pay rate \(LoanFormatters.money(r.hourlyRate))/hr (from \(LoanFormatters.fullDate(r.effectiveDate))) added."
        } catch { self.error = error.localizedDescription }
    }
}

struct KeepLoggingConnectView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = KeepLoggingViewModel()
    @State private var username = ""
    @State private var password = ""

    private var token: String { auth.accessToken ?? "" }

    var body: some View {
        Form {
            if vm.status?.connected == true {
                Section("Connected") {
                    HStack { Text("Account"); Spacer(); Text(vm.status?.username ?? "").foregroundStyle(.secondary) }
                    Button {
                        Task { await vm.syncRate(token: token) }
                    } label: { Label("Sync pay rate now", systemImage: "arrow.triangle.2.circlepath") }
                        .disabled(vm.busy)
                    Button(role: .destructive) {
                        Task { await vm.disconnect(token: token) }
                    } label: { Label("Disconnect", systemImage: "xmark.circle") }
                }
            } else {
                Section("Connect keep-logging") {
                    TextField("keeplogging.com username", text: $username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $password)
                    Button("Connect") {
                        Task {
                            if await vm.connect(username: username, password: password, token: token) {
                                password = ""
                            }
                        }
                    }
                    .disabled(username.isEmpty || password.isEmpty || vm.busy)
                }
                Section {
                    Text("Your keeplogging.com login is exchanged for a token once and stored encrypted — your password isn't kept. This pulls your ALV, reserve guarantee, and pay rate.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("keep-logging")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load(token: token) }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
        .alert("Done", isPresented: .init(get: { vm.message != nil }, set: { if !$0 { vm.message = nil } })) {
            Button("OK") {}
        } message: { Text(vm.message ?? "") }
    }
}

// MARK: - Year comparison (credit vs ALV)

@MainActor
final class PayCompareViewModel: ObservableObject {
    @Published var data: PayCompareData?
    @Published var isLoading = false
    @Published var error: String?
    @Published var year: Int

    init() { year = Calendar.current.component(.year, from: Date()) }

    func load(token: String) async {
        isLoading = true
        error = nil
        do {
            data = try await APIClient.shared.get("/finance/pay/compare/?year=\(year)", token: token)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func step(_ delta: Int) { year += delta }
}

struct PayCompareView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = PayCompareViewModel()
    private var token: String { auth.accessToken ?? "" }

    var body: some View {
        List {
            Section {
                HStack {
                    Button { vm.step(-1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(String(vm.year)).font(.headline)
                    Spacer()
                    Button { vm.step(1) } label: { Image(systemName: "chevron.right") }
                }
            }
            if vm.isLoading {
                Section { HStack { Spacer(); ProgressView("Loading ALV…"); Spacer() } }
            }
            if let d = vm.data {
                if !d.klConnected {
                    Section {
                        NavigationLink(destination: KeepLoggingConnectView()) {
                            Label("Connect keep-logging to compare", systemImage: "link")
                        }
                    }
                }
                Section {
                    HStack {
                        Text("Month").frame(width: 84, alignment: .leading)
                        Spacer()
                        Text("Credit").frame(width: 64, alignment: .trailing)
                        Text("ALV").frame(width: 56, alignment: .trailing)
                        Text("+/−").frame(width: 64, alignment: .trailing)
                    }
                    .font(.caption).foregroundStyle(.secondary)

                    ForEach(d.months.filter { $0.credit > 0 || $0.alv != nil }) { row in
                        HStack {
                            Text(monthName(row.monthNum)).frame(width: 84, alignment: .leading).font(.subheadline)
                            Spacer()
                            Text(String(format: "%.1f", row.credit)).frame(width: 64, alignment: .trailing).font(.subheadline)
                            Text(row.alv != nil ? String(format: "%.1f", row.alv!) : "—")
                                .frame(width: 56, alignment: .trailing).font(.subheadline).foregroundStyle(.secondary)
                            if let ou = row.overUnder {
                                Text(String(format: "%+.1f", ou))
                                    .frame(width: 64, alignment: .trailing).font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ou >= 0 ? .green : .orange)
                            } else {
                                Text("—").frame(width: 64, alignment: .trailing).font(.subheadline).foregroundStyle(.tertiary)
                            }
                        }
                    }
                } footer: {
                    Text("Credit is from your trips (Excel import). ALV is keep-logging's line target — available 2024 on. Positive = over the line.")
                }
            }
        }
        .navigationTitle("Compare to ALV")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load(token: token) }
        .onChange(of: vm.year) { Task { await vm.load(token: token) } }
        .refreshable { await vm.load(token: token) }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
    }
}
