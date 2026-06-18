import Foundation
import PencilKit
import UIKit

/// 负责所有笔记的本地持久化：
///  - 元信息索引保存在 Documents/notes_index.json
///  - 每条笔记的绘图数据保存在 Documents/Notes/<id>.drawing
///  - 每条笔记的缩略图保存在 Documents/Notes/<id>.png
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [NoteMetadata] = []

    private let fm = FileManager.default

    private var docsURL: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var notesDir: URL {
        docsURL.appendingPathComponent("Notes", isDirectory: true)
    }
    private var indexURL: URL {
        docsURL.appendingPathComponent("notes_index.json")
    }

    init() {
        createDirIfNeeded()
        load()
    }

    private func createDirIfNeeded() {
        if !fm.fileExists(atPath: notesDir.path) {
            try? fm.createDirectory(at: notesDir, withIntermediateDirectories: true)
        }
    }

    func drawingURL(_ id: UUID) -> URL { notesDir.appendingPathComponent("\(id).drawing") }
    func thumbURL(_ id: UUID) -> URL { notesDir.appendingPathComponent("\(id).png") }

    // MARK: - 索引

    func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([NoteMetadata].self, from: data) else {
            notes = []
            return
        }
        notes = list.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func persistIndex() {
        if let data = try? JSONEncoder().encode(notes) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    // MARK: - 增删改

    @discardableResult
    func createNote(title: String = "未命名笔记") -> NoteMetadata {
        let note = NoteMetadata(title: title)
        notes.insert(note, at: 0)
        persistIndex()
        try? PKDrawing().dataRepresentation().write(to: drawingURL(note.id))
        return note
    }

    func deleteNote(_ id: UUID) {
        notes.removeAll { $0.id == id }
        try? fm.removeItem(at: drawingURL(id))
        try? fm.removeItem(at: thumbURL(id))
        persistIndex()
    }

    func rename(_ id: UUID, to title: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].title = title
        notes[i].modifiedAt = Date()
        notes.sort { $0.modifiedAt > $1.modifiedAt }
        persistIndex()
    }

    // MARK: - 绘图数据

    func loadDrawing(_ id: UUID) -> PKDrawing {
        guard let data = try? Data(contentsOf: drawingURL(id)),
              let drawing = try? PKDrawing(data: data) else {
            return PKDrawing()
        }
        return drawing
    }

    func saveDrawing(_ id: UUID, drawing: PKDrawing, thumbnail: UIImage?) {
        try? drawing.dataRepresentation().write(to: drawingURL(id), options: .atomic)
        if let png = thumbnail?.pngData() {
            try? png.write(to: thumbURL(id), options: .atomic)
        }
        if let i = notes.firstIndex(where: { $0.id == id }) {
            notes[i].modifiedAt = Date()
            notes.sort { $0.modifiedAt > $1.modifiedAt }
            persistIndex()
        }
    }

    func thumbnail(_ id: UUID) -> UIImage? {
        UIImage(contentsOfFile: thumbURL(id).path)
    }
}
