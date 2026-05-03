import SwiftUI
import SwiftData

struct ResultsView: View {
    let result: ScoringResult
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var editableTips: [CGPoint]
    @State private var overlayImage: UIImage
    @State private var flatImage: UIImage
    @State private var showFlat: Bool = false
    @State private var zoomScale: CGFloat = 1.0
    @State private var zoomOffset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    //set to true when a long press is recognized (finger still down) so the tap that fires on finger-lift is suppressed
    @State private var suppressNextTap = false

    private var geo: TargetGeometry? {
        guard let c = result.targetCenter, let r = result.targetRadius else { return nil }
        return TargetGeometry(center: c, radius: r)
    }

    private var scores: [Int] {
        guard let g = geo else { return Array(repeating: 0, count: editableTips.count) }
        return editableTips.map { ScoringEngine.score(tip: $0, center: g.center, radius: g.radius) }
    }

    private var total: Int { scores.reduce(0, +) }

    init(result: ScoringResult) {
        self.result = result
        _editableTips = State(initialValue: result.arrowTips)
        _overlayImage = State(initialValue: result.annotatedImage)

        let g: TargetGeometry? = {
            guard let c = result.targetCenter, let r = result.targetRadius else { return nil }
            return TargetGeometry(center: c, radius: r)
        }()
        let s = result.arrowTips.map { tip -> Int in
            guard let g else { return 0 }
            return ScoringEngine.score(tip: tip, center: g.center, radius: g.radius)
        }
        _flatImage = State(initialValue: FlatTargetRenderer.draw(tips: result.arrowTips, scores: s, geo: g))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    interactiveImage
                    if geo != nil { viewPicker }
                    if !showFlat { editHint }
                    scoreBanner
                    if !scores.isEmpty { arrowGrid }
                    if scores.isEmpty { noArrowsView }
                    if result.targetCenter == nil { noTargetWarning }
                    Spacer(minLength: 20)
                }
                .padding(.top)
            }
            .navigationTitle("Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    let active = showFlat ? flatImage : overlayImage
                    ShareLink(
                        item: Image(uiImage: active),
                        preview: SharePreview("Archery Score", image: Image(uiImage: active))
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        saveSession()
                    } label: {
                        Label("Save Session", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
        }
    }

    // MARK: - Interactive image

    private var interactiveImage: some View {
        Image(uiImage: showFlat ? flatImage : overlayImage)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 360)
            .scaleEffect(zoomScale)
            .offset(zoomOffset)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                GeometryReader { proxy in
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            //long press sets this flag while finger is still down, before tap fires on lift
                            if suppressNextTap { suppressNextTap = false; return }
                            let norm: CGPoint
                            if showFlat {
                                guard let n = flatCanvasNorm(location, in: proxy.size) else { return }
                                norm = n
                            } else {
                                norm = normalized(location, in: proxy.size)
                            }
                            guard isValid(norm) else { return }
                            editableTips.append(norm)
                            rerender()
                        }
                        .onTapGesture(count: 2) {
                            withAnimation(.spring()) { resetZoom() }
                        }
                        .simultaneousGesture(
                            //fires when 0.4s threshold is met while finger is still down —
                            //setting the flag here ensures the tap on finger-lift is suppressed
                            LongPressGesture(minimumDuration: 0.4)
                                .onEnded { _ in suppressNextTap = true }
                        )
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.4)
                                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                                .onEnded { value in
                                    guard case .second(true, let drag) = value,
                                          let location = drag?.location else { return }
                                    let norm: CGPoint
                                    if showFlat {
                                        guard let n = flatCanvasNorm(location, in: proxy.size) else { return }
                                        norm = n
                                    } else {
                                        norm = normalized(location, in: proxy.size)
                                    }
                                    guard isValid(norm) else { return }
                                    removeNearest(to: norm)
                                }
                        )
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
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            )
            .padding(.horizontal)
            .animation(.easeInOut(duration: 0.2), value: showFlat)
    }

    private var viewPicker: some View {
        Picker("View", selection: $showFlat) {
            Text("Photo").tag(false)
            Text("2D Target").tag(true)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .onChange(of: showFlat) { _, _ in resetZoom() }
    }

    private var editHint: some View {
        HStack(spacing: 16) {
            Label("Tap to add", systemImage: "hand.tap")
            Label("Hold to remove", systemImage: "hand.tap.fill")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var scoreBanner: some View {
        VStack(spacing: 4) {
            Text("Total")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text("\(total)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(.orange)
            Text("\(editableTips.count) arrow\(editableTips.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var arrowGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Arrow Scores")
                .font(.headline)
                .padding(.horizontal)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                ForEach(Array(scores.enumerated()), id: \.offset) { idx, score in
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

    private var noArrowsView: some View {
        ContentUnavailableView(
            "No Arrows",
            systemImage: "questionmark.circle",
            description: Text("Tap the image above to add arrow tips manually.")
        )
    }

    private var noTargetWarning: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("Target not detected — scores may be inaccurate.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemYellow).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }


    //inverse of FlatTargetRenderer's mapping: canvas tap → image-normalized coords
    //must match FlatTargetRenderer constants (size=800, targetR=size*0.42)
    private func flatCanvasNorm(_ point: CGPoint, in viewSize: CGSize) -> CGPoint? {
        guard let g = geo else { return nil }
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
            x: g.center.x + relX * g.radius,
            y: g.center.y + relY * g.radius
        )
    }

    private func normalized(_ point: CGPoint, in viewSize: CGSize) -> CGPoint {
        // scaledToFit centers the image inside the view frame with empty space on the sides
        // (pillarboxing for portrait images, letterboxing for landscape).
        // Dividing by viewSize directly includes that empty space and shifts taps left/up.
        // Compute the actual rendered rect and normalize relative to that instead.
        let imgSize = overlayImage.size
        let scale   = min(viewSize.width / imgSize.width, viewSize.height / imgSize.height)
        let renderedW = imgSize.width  * scale
        let renderedH = imgSize.height * scale
        let offsetX   = (viewSize.width  - renderedW) / 2
        let offsetY   = (viewSize.height - renderedH) / 2
        return CGPoint(
            x: (point.x - offsetX) / renderedW,
            y: (point.y - offsetY) / renderedH
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

    private func saveSession() {
        guard let (flatName, tipsData) = Session.save(flat: flatImage, tips: editableTips) else { return }
        let session = Session(
            date: Date(),
            total: total,
            scores: scores,
            imageFilename: flatName,
            tipsData: tipsData,
            targetCenterX: geo.map { Double($0.center.x) },
            targetCenterY: geo.map { Double($0.center.y) },
            targetRadius: geo.map { Double($0.radius) }
        )
        modelContext.insert(session)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { dismiss() }
    }

    private func resetZoom() {
        zoomScale = 1.0
        zoomOffset = .zero
        lastOffset = .zero
    }

    private func rerender() {
        overlayImage = OverlayRenderer.draw(on: result.originalImage, tips: editableTips, scores: scores, geo: geo)
        flatImage    = FlatTargetRenderer.draw(tips: editableTips, scores: scores, geo: geo)
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
