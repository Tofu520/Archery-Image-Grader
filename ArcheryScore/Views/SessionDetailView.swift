import SwiftUI
import SwiftData

struct SessionDetailView: View {
    let session: Session
    @Environment(\.modelContext) private var modelContext

    @State private var displayImage: UIImage?
    @State private var isEditing = false
    @State private var editFlatImage: UIImage?
    @State private var editableTips: [CGPoint] = []
    @State private var suppressNextTap = false
    @State private var zoomScale: CGFloat = 1.0
    @State private var zoomOffset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private var editGeo: TargetGeometry? { session.geo }

    private var editScores: [Int] {
        guard let g = editGeo else { return Array(repeating: 0, count: editableTips.count) }
        return editableTips.map { ScoringEngine.score(tip: $0, center: g.center, radius: g.radius) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                imageSection
                if isEditing { editHint }
                scoreBanner
                arrowGridSection
                Spacer(minLength: 20)
            }
            .padding(.top)
        }
        .navigationTitle(session.date.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isEditing)
        .toolbar { toolbarContent }
        .onAppear {
            displayImage = session.loadImage()
        }
    }

    // MARK: - Image

    private var imageSection: some View {
        let shown: UIImage? = isEditing ? editFlatImage : displayImage
        return Group {
            if let img = shown {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: UIScreen.main.bounds.width)
                    .scaleEffect(zoomScale)
                    .offset(zoomOffset)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        if isEditing {
                            GeometryReader { imgProxy in
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture { location in
                                        if suppressNextTap { suppressNextTap = false; return }
                                        guard let norm = flatCanvasNorm(location, in: imgProxy.size) else { return }
                                        guard isValid(norm) else { return }
                                        editableTips.append(norm)
                                        rerender()
                                    }
                                    .simultaneousGesture(
                                        LongPressGesture(minimumDuration: 0.4)
                                            .onEnded { _ in suppressNextTap = true }
                                    )
                                    .simultaneousGesture(
                                        LongPressGesture(minimumDuration: 0.4)
                                            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                                            .onEnded { value in
                                                guard case .second(true, let drag) = value,
                                                      let loc = drag?.location else { return }
                                                guard let norm = flatCanvasNorm(loc, in: imgProxy.size) else { return }
                                                guard isValid(norm) else { return }
                                                removeNearest(to: norm)
                                            }
                                    )
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in zoomScale = max(1.0, value) }
                            .onEnded { _ in
                                if zoomScale < 1.0 { withAnimation(.spring()) { resetZoom() } }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                guard zoomScale > 1.0 else { return }
                                zoomOffset = CGSize(
                                    width:  lastOffset.width  + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in lastOffset = zoomOffset }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) { resetZoom() }
                    }
                    .animation(.easeInOut(duration: 0.2), value: isEditing)
            } else {
                Color(.systemGray5)
                    .frame(height: UIScreen.main.bounds.width)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(ProgressView())
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Score UI

    private var scoreBanner: some View {
        let count = isEditing ? editableTips.count : session.scores.count
        let total = isEditing ? editScores.reduce(0, +) : session.total
        return VStack(spacing: 4) {
            Text("Total")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text("\(total)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(.orange)
            Text("\(count) arrow\(count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    @ViewBuilder
    private var arrowGridSection: some View {
        let displayScores = isEditing ? editScores : session.scores
        if !displayScores.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Arrow Scores")
                    .font(.headline)
                    .padding(.horizontal)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                    ForEach(Array(displayScores.enumerated()), id: \.offset) { idx, score in
                        VStack(spacing: 2) {
                            Text("\(idx + 1)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(score > 0 ? "\(score)" : "M")
                                .font(.title3.bold())
                                .foregroundStyle(scoreColor(score))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(scoreColor(score).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var editHint: some View {
        HStack(spacing: 16) {
            Label("Tap to add", systemImage: "hand.tap")
            Label("Hold to remove", systemImage: "hand.tap.fill")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { cancelEditing() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { saveEdits() }
                    .fontWeight(.semibold)
            }
        } else {
            ToolbarItem(placement: .confirmationAction) {
                //editing requires geo for inverse coordinate mapping
                if session.geo != nil {
                    Button { enterEditing() } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                }
            }
        }
    }

    // MARK: - Edit actions

    private func enterEditing() {
        editableTips = session.tips
        isEditing = true
        resetZoom()
        rerender()
    }

    private func cancelEditing() {
        isEditing = false
        editFlatImage = nil
        resetZoom()
    }

    private func saveEdits() {
        let finalScores = editScores
        let newFlat = FlatTargetRenderer.draw(tips: editableTips, scores: finalScores, geo: editGeo)
        session.updateSession(flatImage: newFlat, newTips: editableTips, newScores: finalScores)
        try? modelContext.save()
        displayImage = newFlat
        isEditing = false
        editFlatImage = nil
        resetZoom()
    }

    private func rerender() {
        editFlatImage = FlatTargetRenderer.draw(tips: editableTips, scores: editScores, geo: editGeo)
    }

    // MARK: - Helpers

    //inverse of FlatTargetRenderer's mapping: view tap → image-normalized coords
    //must match FlatTargetRenderer constants (size=800, targetR=size*0.42)
    private func flatCanvasNorm(_ point: CGPoint, in viewSize: CGSize) -> CGPoint? {
        guard let geo = editGeo else { return nil }
        let canvasSize: CGFloat = 800
        let scale     = min(viewSize.width / canvasSize, viewSize.height / canvasSize)
        let renderedW = canvasSize * scale
        let renderedH = canvasSize * scale
        let offsetX   = (viewSize.width  - renderedW) / 2
        let offsetY   = (viewSize.height - renderedH) / 2
        let canvasX   = (point.x - offsetX) / scale
        let canvasY   = (point.y - offsetY) / scale
        let cx        = canvasSize / 2
        let cy        = canvasSize / 2
        let targetR   = canvasSize * 0.42
        let relX      = (canvasX - cx) / targetR
        let relY      = (canvasY - cy) / targetR
        return CGPoint(
            x: geo.center.x + relX * geo.radius,
            y: geo.center.y + relY * geo.radius
        )
    }

    private func isValid(_ norm: CGPoint) -> Bool {
        (0...1).contains(norm.x) && (0...1).contains(norm.y)
    }

    private func removeNearest(to norm: CGPoint) {
        guard let idx = editableTips.indices.min(by: {
            hypot(editableTips[$0].x - norm.x, editableTips[$0].y - norm.y) <
            hypot(editableTips[$1].x - norm.x, editableTips[$1].y - norm.y)
        }) else { return }
        editableTips.remove(at: idx)
        rerender()
    }

    private func resetZoom() {
        zoomScale = 1.0
        zoomOffset = .zero
        lastOffset = .zero
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 9...10: return .yellow
        case 7...8:  return .red
        case 5...6:  return .blue
        case 1...4:  return .primary
        default:     return .gray
        }
    }
}
