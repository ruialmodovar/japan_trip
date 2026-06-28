import SwiftUI

struct ChecklistView: View {
    @EnvironmentObject private var tripState: TripState

    private var completedCount: Int {
        TripData.checklist.filter(tripState.isCompleted).count
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Preparação").font(.headline)
                        Spacer()
                        Text("\(completedCount)/\(TripData.checklist.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(completedCount), total: Double(TripData.checklist.count)).tint(.indigo)
                }
                .padding(.vertical, 6)
            }

            ForEach(ChecklistItem.Section.allCases, id: \.rawValue) { section in
                Section(section.rawValue) {
                    ForEach(TripData.checklist.filter { $0.section == section }) { item in
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
                    }
                }
            }
        }
        .navigationTitle("Checklist")
        .listStyle(.insetGrouped)
    }
}
