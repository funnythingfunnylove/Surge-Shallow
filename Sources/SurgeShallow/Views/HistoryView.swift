import SwiftUI
import SurgeProfileRelayCore

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.document.history.isEmpty {
                ContentUnavailableView(
                    "暂无更新记录",
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    description: Text("完成一次更新或自动检查后，结果会保存在 iCloud 管理配置中。")
                )
            } else {
                List(model.document.history) { record in
                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: record.outcome.symbol)
                            .font(.title3)
                            .foregroundStyle(record.outcome.color)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(record.title)
                                    .font(.headline)
                                Spacer()
                                Text(record.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(record.details)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            if record.ruleCount > 0 || record.duplicateCount > 0 {
                                Text("\(record.ruleCount) 条输出 · 去除 \(record.duplicateCount) 条重复")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.vertical, 7)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("更新记录")
    }
}
