import Foundation

enum ModuleOrdering {
    static func moving<T>(_ values: [T], fromOffsets offsets: IndexSet, toOffset destination: Int) -> [T] {
        guard !offsets.isEmpty else { return values }
        let validOffsets = IndexSet(offsets.filter { values.indices.contains($0) })
        guard !validOffsets.isEmpty else { return values }

        let movingValues = validOffsets.map { values[$0] }
        var result = values
        for index in validOffsets.reversed() {
            result.remove(at: index)
        }
        let removedBeforeDestination = validOffsets.filter { $0 < destination }.count
        let insertionIndex = min(max(destination - removedBeforeDestination, 0), result.count)
        result.insert(contentsOf: movingValues, at: insertionIndex)
        return result
    }
}
