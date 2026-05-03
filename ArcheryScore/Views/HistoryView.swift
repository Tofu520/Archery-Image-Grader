import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \Session.date, order: .forward) private var sessions: [Session]
    @Environment(\.modelContext) private var modelContext
    @State private var sessionToDelete: Session?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions Yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Score a photo and tap Save to record a session.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(sessions) { session in
                                NavigationLink(destination: SessionDetailView(session: session)) {
                                    SessionCard(session: session) {
                                        sessionToDelete = session
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
        }
        .alert("Delete Session?", isPresented: .constant(sessionToDelete != nil)) {
            Button("Delete", role: .destructive) {
                if let s = sessionToDelete { delete(s) }
                sessionToDelete = nil
            }
            Button("Cancel", role: .cancel) { sessionToDelete = nil }
        } message: {
            Text("This photo and its scores will be permanently removed.")
        }
    }

    private func delete(_ session: Session) {
        session.deleteImage()
        modelContext.delete(session)
    }
}

private struct SessionCard: View {
    let session: Session
    let onDelete: () -> Void

    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(.systemGray5)
                        .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                }
            }
            .frame(height: 140)
            .clipped()

            VStack(spacing: 4) {
                Text("\(session.total) pts")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(session.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }
            .padding(8)
            .background(Color(.systemGray6))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .task {
            let path = Session.documentsURL(for: session.imageFilename).path
            image = await Task.detached(priority: .utility) {
                UIImage(contentsOfFile: path)
            }.value
        }
    }
}
