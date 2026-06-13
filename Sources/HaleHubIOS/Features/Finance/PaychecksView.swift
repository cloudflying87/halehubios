import SwiftUI
import UniformTypeIdentifiers

// MARK: - View Models

@MainActor
final class PaychecksViewModel: ObservableObject {
    @Published var paychecks: [FinancePaycheck] = []
    @Published var employers: [Employer] = []
    @Published var isLoading = false
    @Published var uploading = false
    @Published var error: String?

    func load(token: String) async {
        isLoading = true
        error = nil
        do {
            async let pc: [FinancePaycheck] = APIClient.shared.get("/finance/paychecks/?limit=50", token: token)
            async let emp: [Employer] = APIClient.shared.get("/finance/employers/", token: token)
            let (p, e) = try await (pc, emp)
            paychecks = p
            employers = e
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func upload(pdfData: Data, filename: String, employerId: Int?, employerName: String?, token: String) async -> Bool {
        uploading = true
        defer { uploading = false }
        do {
            _ = try await APIClient.shared.uploadPaycheck(
                pdfData: pdfData, filename: filename,
                employerId: employerId, employerName: employerName, token: token
            )
            await load(token: token)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

// MARK: - List

struct PaychecksView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = PaychecksViewModel()
    @State private var showAdd = false

    private var token: String { auth.accessToken ?? "" }

    var body: some View {
        Group {
            if vm.isLoading && vm.paychecks.isEmpty {
                ProgressView("Loading…").frame(maxWidth: .infinity, minHeight: 200)
            } else if vm.paychecks.isEmpty {
                ContentUnavailableView("No Paychecks", systemImage: "doc.text",
                                       description: Text("Tap + to upload a paycheck PDF."))
            } else {
                List {
                    ForEach(vm.paychecks) { pc in
                        NavigationLink(destination: PaycheckDetailView(paycheckId: pc.id)) {
                            paycheckRow(pc)
                        }
                    }
                }
            }
        }
        .navigationTitle("Paychecks")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddPaycheckSheet(vm: vm)
        }
        .task { await vm.load(token: token) }
        .refreshable { await vm.load(token: token) }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
    }

    private func paycheckRow(_ pc: FinancePaycheck) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(pc.payDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline).fontWeight(.medium)
                if let employer = pc.employerName {
                    Text(employer).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(LoanFormatters.money(pc.grossPay, fractionDigits: 0))
                    .font(.subheadline).fontWeight(.semibold)
                Text("Net \(LoanFormatters.money(pc.netPay, fractionDigits: 0))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Add (upload) sheet

struct AddPaycheckSheet: View {
    @ObservedObject var vm: PaychecksViewModel
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedEmployerId: Int?
    @State private var newEmployerName = ""
    @State private var useNewEmployer = false
    @State private var showImporter = false
    @State private var localError: String?

    private var token: String { auth.accessToken ?? "" }

    private var employerReady: Bool {
        if useNewEmployer { return !newEmployerName.trimmingCharacters(in: .whitespaces).isEmpty }
        return selectedEmployerId != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Employer") {
                    if !vm.employers.isEmpty && !useNewEmployer {
                        Picker("Employer", selection: $selectedEmployerId) {
                            Text("Select…").tag(Int?.none)
                            ForEach(vm.employers) { Text($0.name).tag(Int?.some($0.id)) }
                        }
                    }
                    if useNewEmployer || vm.employers.isEmpty {
                        TextField("New employer name", text: $newEmployerName)
                    }
                    if !vm.employers.isEmpty {
                        Toggle("Add a new employer", isOn: $useNewEmployer)
                    }
                }
                Section {
                    Button {
                        showImporter = true
                    } label: {
                        if vm.uploading {
                            HStack { ProgressView(); Text("Uploading & parsing…") }
                        } else {
                            Label("Choose PDF & Upload", systemImage: "doc.badge.plus")
                        }
                    }
                    .disabled(!employerReady || vm.uploading)
                } footer: {
                    Text("We'll read the gross, net, and dates from the PDF. You can correct anything afterward.")
                }
                if let localError {
                    Text(localError).font(.caption).foregroundStyle(.red)
                }
            }
            .navigationTitle("Add Paycheck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf]) { result in
                handlePick(result)
            }
            .task { if vm.employers.isEmpty { await vm.load(token: token) } }
        }
    }

    private func handlePick(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let err):
            localError = err.localizedDescription
        case .success(let url):
            let needsStop = url.startAccessingSecurityScopedResource()
            defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                localError = "Couldn't read that file."
                return
            }
            let employerId = useNewEmployer ? nil : selectedEmployerId
            let employerName = useNewEmployer ? newEmployerName.trimmingCharacters(in: .whitespaces) : nil
            Task {
                let ok = await vm.upload(
                    pdfData: data, filename: url.lastPathComponent,
                    employerId: employerId, employerName: employerName, token: token
                )
                if ok { dismiss() }
            }
        }
    }
}

// MARK: - Detail / edit

@MainActor
final class PaycheckDetailViewModel: ObservableObject {
    @Published var paycheck: PaycheckDetail?
    @Published var isLoading = false
    @Published var saving = false
    @Published var error: String?

    func load(id: Int, token: String) async {
        isLoading = true
        error = nil
        do {
            paycheck = try await APIClient.shared.get("/finance/paychecks/\(id)/", token: token)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func save(id: Int, req: PaycheckEditRequest, token: String) async -> Bool {
        saving = true
        defer { saving = false }
        do {
            paycheck = try await APIClient.shared.patch("/finance/paychecks/\(id)/", body: req, token: token)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func delete(id: Int, token: String) async -> Bool {
        do {
            try await APIClient.shared.delete("/finance/paychecks/\(id)/", token: token)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

struct PaycheckDetailView: View {
    let paycheckId: Int
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = PaycheckDetailViewModel()
    @State private var showEdit = false
    @State private var confirmDelete = false

    private var token: String { auth.accessToken ?? "" }

    var body: some View {
        Group {
            if let pc = vm.paycheck {
                content(pc)
            } else if vm.isLoading {
                ProgressView("Loading…").frame(maxWidth: .infinity, minHeight: 200)
            } else {
                ContentUnavailableView("Couldn’t load paycheck", systemImage: "exclamationmark.triangle",
                                       description: Text(vm.error ?? "Try again."))
            }
        }
        .navigationTitle(vm.paycheck.map { LoanFormatters.fullDate($0.payDate) } ?? "Paycheck")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if vm.paycheck != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showEdit = true } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let pc = vm.paycheck { PaycheckEditSheet(paycheck: pc, vm: vm) }
        }
        .alert("Delete this paycheck?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                Task { if await vm.delete(id: paycheckId, token: token) { dismiss() } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Error", isPresented: .init(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") {}
        } message: { Text(vm.error ?? "") }
        .task { await vm.load(id: paycheckId, token: token) }
        .refreshable { await vm.load(id: paycheckId, token: token) }
    }

    private func content(_ pc: PaycheckDetail) -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                VStack(spacing: 12) {
                    HStack {
                        amountPillar("Gross", pc.grossPay, .primary)
                        Spacer()
                        amountPillar("Net", pc.netPay, .green)
                        Spacer()
                        amountPillar("Deductions", pc.grossPay - pc.netPay, .orange)
                    }
                    Divider()
                    HStack {
                        Text(pc.employerName).font(.subheadline).fontWeight(.medium)
                        Spacer()
                        Text("\(LoanFormatters.fullDate(pc.payPeriodStart)) – \(LoanFormatters.fullDate(pc.payPeriodEnd))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let pdf = pc.pdfUrl, let url = URL(string: pdf) {
                        Link(destination: url) {
                            Label("View PDF", systemImage: "doc.richtext").font(.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                if let items = pc.lineItems, !items.isEmpty {
                    lineItemsCard(items)
                }
                if !pc.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes").font(.headline)
                        Text(pc.notes).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(16)
        }
    }

    private func amountPillar(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(LoanFormatters.money(value, fractionDigits: 0)).font(.headline).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func lineItemsCard(_ items: [PaycheckLineItemValue]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Line Items").font(.headline)
            ForEach(items) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name).font(.subheadline)
                        Text(item.itemType.capitalized).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(LoanFormatters.money(item.amount)).font(.subheadline)
                }
                .padding(.vertical, 2)
                Divider()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct PaycheckEditSheet: View {
    let paycheck: PaycheckDetail
    @ObservedObject var vm: PaycheckDetailViewModel
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var gross: Double
    @State private var net: Double
    @State private var payDate: Date
    @State private var notes: String

    init(paycheck: PaycheckDetail, vm: PaycheckDetailViewModel) {
        self.paycheck = paycheck
        self.vm = vm
        _gross = State(initialValue: paycheck.grossPay)
        _net = State(initialValue: paycheck.netPay)
        _notes = State(initialValue: paycheck.notes)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        _payDate = State(initialValue: f.date(from: paycheck.payDate) ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Amounts") {
                    HStack {
                        Text("Gross"); Spacer()
                        TextField("Gross", value: $gross, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Net"); Spacer()
                        TextField("Net", value: $net, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                }
                Section("Details") {
                    DatePicker("Pay Date", selection: $payDate, displayedComponents: .date)
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(1...4)
                }
            }
            .navigationTitle("Edit Paycheck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            let req = PaycheckEditRequest(
                                grossPay: gross, netPay: net,
                                payDate: LoanFormatters.ymd(payDate), notes: notes
                            )
                            if await vm.save(id: paycheck.id, req: req, token: auth.accessToken ?? "") { dismiss() }
                        }
                    }
                    .disabled(vm.saving)
                }
            }
        }
    }
}
