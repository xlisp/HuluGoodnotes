import SwiftUI

/// 笔记列表（首页）。以缩略图网格展示所有本地笔记。
struct NoteListView: View {
    @StateObject private var store = NoteStore()
    @State private var openNote: NoteMetadata?

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 24)]

    var body: some View {
        NavigationStack {
            Group {
                if store.notes.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 24) {
                            ForEach(store.notes) { note in
                                NoteCard(note: note, thumbnail: store.thumbnail(note.id))
                                    .onTapGesture { openNote = note }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            store.deleteNote(note.id)
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .padding(24)
                    }
                }
            }
            .navigationTitle("我的笔记")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openNote = store.createNote()
                    } label: {
                        Label("新建", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(item: $openNote) { note in
                NoteEditorView(store: store, note: note)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有笔记", systemImage: "square.and.pencil")
        } description: {
            Text("点击右上角的 + 新建一篇笔记")
        }
    }
}

/// 单张笔记卡片。
struct NoteCard: View {
    let note: NoteMetadata
    let thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 220)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )

            Text(note.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Text(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
