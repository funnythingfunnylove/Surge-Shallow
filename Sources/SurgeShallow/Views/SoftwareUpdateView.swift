import SwiftUI

struct SoftwareUpdateView: View {
    @Environment(AppModel.self) private var model
    let release: SoftwareRelease

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(SurgeSpacing.xl)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: SurgeSpacing.lg) {
                    Text("更新日志")
                        .font(.headline)
                    Text(renderedReleaseNotes)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(SurgeSpacing.xl)
            }
            .frame(minHeight: 280, maxHeight: 440)

            Divider()

            footer
                .padding(SurgeSpacing.lg)
        }
        .frame(width: 620)
        .interactiveDismissDisabled(model.softwareUpdate.isBusy)
        .accessibilityIdentifier("software-update-sheet")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: SurgeSpacing.lg) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(SurgePalette.accent)
                .frame(width: 62, height: 62)
                .background(
                    SurgePalette.accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: SurgeRadius.card, style: .continuous)
                )

            VStack(alignment: .leading, spacing: SurgeSpacing.sm) {
                Text("Surge Shallow 有新版本")
                    .font(.title2.weight(.semibold))
                Text("\(model.softwareUpdate.currentVersion) → \(release.version.description)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(SurgePalette.accent)
                HStack(spacing: SurgeSpacing.md) {
                    Label(release.asset.size.formatted(.byteCount(style: .file)), systemImage: "archivebox")
                    if let publishedAt = release.publishedAt {
                        Label(
                            publishedAt.formatted(date: .abbreviated, time: .omitted),
                            systemImage: "calendar"
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: SurgeSpacing.md) {
            if model.softwareUpdate.isBusy {
                HStack(spacing: SurgeSpacing.md) {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.softwareUpdate.statusText)
                        .font(.callout.weight(.medium))
                }
            } else if case .failed(let message) = model.softwareUpdate.phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(SurgePalette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(
                    "更新包会校验 GitHub SHA-256、应用版本与代码签名完整性；安装后应用会自动重新启动。",
                    systemImage: "checkmark.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                Link("在 GitHub 查看", destination: release.pageURL)
                Spacer()
                Button("稍后") {
                    model.softwareUpdate.dismissPresentedUpdate()
                }
                .disabled(model.softwareUpdate.isBusy)
                Button {
                    Task { await model.installSoftwareUpdate(release) }
                } label: {
                    Text(installButtonTitle)
                }
                .buttonStyle(.glassProminent)
                .disabled(model.softwareUpdate.isBusy)
                .accessibilityIdentifier("install-software-update-button")
            }
        }
    }

    private var renderedReleaseNotes: AttributedString {
        (try? AttributedString(
            markdown: release.notes,
            options: .init(interpretedSyntax: .full)
        )) ?? AttributedString(release.notes)
    }

    private var installButtonTitle: String {
        if case .failed = model.softwareUpdate.phase { return "重试更新" }
        return "立即更新并重启"
    }
}
