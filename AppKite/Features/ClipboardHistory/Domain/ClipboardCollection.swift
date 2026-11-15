import Foundation

nonisolated struct ClipboardCollection: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
}
