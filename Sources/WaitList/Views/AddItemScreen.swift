import SwiftUI
import WaitListCore

/// Adds a new item, or edits the name, price and note of an existing one.
struct AddItemScreen: View {
    private enum Field: Hashable {
        case name, price, note, customDays
    }

    private enum WaitChoice: Hashable {
        case preset(Int)
        case custom
    }

    private static let presets = [7, 14, 30, 90]

    let editing: Item?

    @Environment(ItemStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router

    @State private var name: String
    @State private var priceText: String
    @State private var note: String
    @State private var waitChoice: WaitChoice
    @State private var customDaysText: String
    @FocusState private var focus: Field?

    init(editing: Item?, defaultWaitDays: Int) {
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _priceText = State(initialValue: editing?.price.map(Format.editablePrice) ?? "")
        _note = State(initialValue: editing?.note ?? "")
        _waitChoice = State(initialValue: Self.presets.contains(defaultWaitDays) ? .preset(defaultWaitDays) : .custom)
        _customDaysText = State(initialValue: String(defaultWaitDays))
    }

    // MARK: Derived state

    private var isEditing: Bool { editing != nil }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var priceInput: PriceInput {
        PriceInput.parse(priceText)
    }

    private var priceProblem: String? {
        switch priceInput {
        case .invalid: return "Enter an amount, like 1299."
        case .value(let value) where value < 0: return "The price can't be negative."
        default: return nil
        }
    }

    private var customDays: Int? {
        guard let days = Int(customDaysText), Scheduling.waitDaysRange.contains(days) else { return nil }
        return days
    }

    private var waitDays: Int? {
        switch waitChoice {
        case .preset(let days): return days
        case .custom: return customDays
        }
    }

    private var decideDate: Date? {
        waitDays.map {
            Scheduling.decideDate(from: store.now, waitDays: $0, time: settings.notificationTime,
                                  calendar: store.calendar)
        }
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && priceProblem == nil && (isEditing || waitDays != nil)
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: isEditing ? "Edit item" : "Add item", backTitle: "Cancel", showsChevron: false) {
                router.show(.list)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FormField(label: "Name") {
                        TextField("Name", text: $name, prompt: Text("What do you want to buy?"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .focused($focus, equals: .name)
                    }
                    FormField(label: "Price", message: priceProblem) {
                        HStack(spacing: 6) {
                            TextField("Price", text: $priceText, prompt: Text("Optional"))
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .focused($focus, equals: .price)
                            Text(settings.currencyCode)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    FormField(label: "Note or link") {
                        TextField("Note or link", text: $note, prompt: Text("Why you want it, or a link"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .focused($focus, equals: .note)
                    }
                    if !isEditing {
                        waitSection
                    } else if let editing, editing.isWaiting(at: store.now) {
                        decideLine(for: editing.decideAt)
                    }
                }
                .padding(16)
                .animation(.snappy(duration: 0.2), value: waitChoice)
                .animation(.snappy(duration: 0.2), value: priceProblem)
            }
            Divider()
            HStack {
                Spacer()
                Button(isEditing ? "Save" : "Add to WaitList", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .defaultFocus($focus, .name)
        .onAppear { focus = .name }
    }

    private var waitSection: some View {
        FormField(label: "Wait before deciding",
                  message: waitDays == nil ? "Choose between 1 and 365 days." : nil) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Wait", selection: $waitChoice) {
                    ForEach(Self.presets, id: \.self) { days in
                        Text("\(days) days").tag(WaitChoice.preset(days))
                    }
                    Text("Custom").tag(WaitChoice.custom)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if waitChoice == .custom {
                    HStack(spacing: 6) {
                        TextField("Days", text: $customDaysText)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 56)
                            .focused($focus, equals: .customDays)
                            .onChange(of: customDaysText) { _, newValue in
                                let digits = String(newValue.filter { $0.isASCII && $0.isNumber }.prefix(3))
                                if digits != newValue { customDaysText = digits }
                            }
                        Stepper("Days", value: customDaysBinding, in: Scheduling.waitDaysRange)
                            .labelsHidden()
                        Text(customDays == 1 ? "day" : "days")
                            .foregroundStyle(.secondary)
                    }
                }

                if let decideDate {
                    decideLine(for: decideDate)
                }
            }
        }
    }

    private func decideLine(for date: Date) -> some View {
        Label {
            Text("You'll decide on \(Format.shortDate(date)) at \(Format.time(date))")
        } icon: {
            Image(systemName: "calendar")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var customDaysBinding: Binding<Int> {
        Binding(
            get: { customDays ?? settings.defaultWaitDays },
            set: { customDaysText = String($0) })
    }

    // MARK: Saving

    private func save() {
        guard canSave else { return }
        var price: Decimal?
        if case .value(let value) = priceInput { price = value }
        if let editing {
            store.update(editing.id, name: trimmedName, price: price, note: note)
        } else if let waitDays {
            store.add(name: trimmedName, price: price, note: note, waitDays: waitDays)
        }
        router.show(.list)
    }
}
