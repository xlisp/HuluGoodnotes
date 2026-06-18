import Foundation

/// 一条笔记的元信息。实际的手写/绘图数据（PKDrawing）单独保存在磁盘上。
struct NoteMetadata: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    /// 自动整理的"基准字高"。首次整理后锁定，之后再整理都按它对齐。
    var tidyGlyphHeight: CGFloat?

    init(id: UUID = UUID(), title: String, createdAt: Date = Date(), modifiedAt: Date = Date(),
         tidyGlyphHeight: CGFloat? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.tidyGlyphHeight = tidyGlyphHeight
    }
}
