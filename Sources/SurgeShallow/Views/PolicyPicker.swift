import SwiftUI
import SurgeProfileRelayCore

struct RelayPolicyPicker: View {
    let title: String
    @Binding var selection: String
    let sharedProfile: SharedProfile
    var excludedNames: Set<String> = []
    var includesGroups = true

    var body: some View {
        Picker(title, selection: $selection) {
            Section("Surge 内置策略") {
                ForEach(RelayPolicyCatalog.builtInPolicies) { policy in
                    Text("\(policy.title) · \(policy.name)").tag(policy.name)
                }
            }

            if !proxyNames.isEmpty {
                Section("Proxy") {
                    ForEach(proxyNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
            }

            if includesGroups, !groupNames.isEmpty {
                Section("Proxy Group") {
                    ForEach(groupNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
            }

            if !trimmedSelection.isEmpty, !knownNames.contains(trimmedSelection.lowercased()) {
                Section("现有自定义值") {
                    Text("\(trimmedSelection) · 未在公共 Proxy 中定义").tag(trimmedSelection)
                }
            }
        }
    }

    private var trimmedSelection: String {
        selection.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var proxyNames: [String] {
        RelayPolicyCatalog.proxyNames(in: sharedProfile).filter(isIncluded)
    }

    private var groupNames: [String] {
        RelayPolicyCatalog.groupNames(in: sharedProfile).filter(isIncluded)
    }

    private var knownNames: Set<String> {
        Set(
            (RelayPolicyCatalog.builtInPolicies.map(\.name) + proxyNames + groupNames)
                .map { $0.lowercased() }
        )
    }

    private func isIncluded(_ value: String) -> Bool {
        !excludedNames.contains(value.lowercased())
    }
}
