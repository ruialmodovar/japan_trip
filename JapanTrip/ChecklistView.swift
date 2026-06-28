import SwiftUI

struct ChecklistView: View {
    @EnvironmentObject private var tripState: TripState
    @State private var editingItem: ChecklistItem?
    @State private var showsNewItem = false
    @State private var showsRestoreConfirmation = false

    private var completedCount: Int {
        tripState.checklistItems.filter(tripState.isCompleted).count
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Preparação").font(.headline)
                        Spacer()
                        Text("\(completedCount)/\(tripState.checklistItems.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(completedCount), total: Double(max(tripState.checklistItems.count, 1))).tint(.indigo)
                }
                .padding(.vertical, 6)
            }

            ForEach(ChecklistItem.Section.allCases, id: \.rawValue) { section in
                Section(section.rawValue) {
                    ForEach(tripState.checklistItems.filter { $0.section == section }) { item in
                        Button {
                            withAnimation(.snappy) { tripState.toggle(item) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: tripState.isCompleted(item) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(tripState.isCompleted(item) ? .green : .secondary)
                                Text(item.title)
                                    .foregroundStyle(tripState.isCompleted(item) ? .secondary : .primary)
                                    .strikethrough(tripState.isCompleted(item))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                tripState.deleteChecklistItem(item)
                            } label: {
                                Label("Apagar", systemImage: "trash")
                            }
                            Button {
                                editingItem = item
                            } label: {
                                Label("Editar", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("Checklist")
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showsRestoreConfirmation = true
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .accessibilityLabel("Restaurar checklist original")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsNewItem = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .accessibilityLabel("Adicionar item")
                }
            }
        }
        .sheet(isPresented: $showsNewItem) {
            ChecklistEditorView(mode: .new)
                .environmentObject(tripState)
        }
        .sheet(item: $editingItem) { item in
            ChecklistEditorView(mode: .edit(item))
                .environmentObject(tripState)
        }
        .confirmationDialog("Restaurar checklist original?", isPresented: $showsRestoreConfirmation) {
            Button("Restaurar", role: .destructive) { tripState.restoreDefaultChecklist() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Itens adicionados e alterações serão removidos.")
        }
    }
}

private struct ChecklistEditorView: View {
    enum Mode {
        case new
        case edit(ChecklistItem)
    }

    @EnvironmentObject private var tripState: TripState
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    @State private var title: String
    @State private var section: ChecklistItem.Section

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .new:
            _title = State(initialValue: "")
            _section = State(initialValue: .before)
        case .edit(let item):
            _title = State(initialValue: item.title)
            _section = State(initialValue: item.section)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("O que precisa ser feito?", text: $title, axis: .vertical)
                        .lineLimit(2...4)
                    Picker("Grupo", selection: $section) {
                        ForEach(ChecklistItem.Section.allCases, id: \.rawValue) { section in
                            Text(section.rawValue).tag(section)
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Novo item" : "Editar item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var isNew: Bool {
        if case .new = mode { return true }
        return false
    }

    private func save() {
        switch mode {
        case .new:
            tripState.addChecklistItem(title: title, section: section)
        case .edit(let item):
            tripState.updateChecklistItem(item, title: title, section: section)
        }
        dismiss()
    }
}
