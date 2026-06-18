import Foundation

/// 一条笔记的元信息。实际的手写/绘图数据（PKDrawing）单独保存在磁盘上。
struct NoteMetadata: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date

    init(id: UUID = UUID(), title: String, createdAt: Date = Date(), modifiedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}
