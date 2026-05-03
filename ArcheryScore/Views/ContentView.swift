import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var inputImage: UIImage?
    @State private var result: ScoringResult?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showingResults = false

    var body: some View {
        TabView {
            scorerTab
                .tabItem { Label("Score", systemImage: "target") }

            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        .sheet(isPresented: $showingResults) {
            if let result = result {
                ResultsView(result: result)
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            Task { await loadImage(from: newItem) }
        }
    }

    private var scorerTab: some View {
        NavigationStack {
            VStack(spacing: 24) {
                headerSection
                imageSection
                actionSection
                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding()
            .navigationTitle("Archery Scorer")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var headerSection: some View {
        VStack(spacing: 4) {
            Image(systemName: "target")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Take or choose a photo of your target")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    private var imageSection: some View {
        Group {
            if let img = inputImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.orange.opacity(0.5), lineWidth: 2))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .frame(height: 220)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)
                            Text("No image selected")
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
    }
    
    //grab image from the user and feed it into the scoreImage.
    private var actionSection: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $selectedItem, matching: .images) {
                Label("Choose Photo", systemImage: "photo.stack")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if inputImage != nil {
                Button {
                    Task { await scoreImage() }
                } label: {
                    HStack {
                        if isProcessing {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "wand.and.stars")
                        }
                        Text(isProcessing ? "Scoring…" : "Score Arrows")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isProcessing)
            }
        }
    }

    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else { return }
        inputImage = uiImage
        result = nil
        errorMessage = nil
    }
    
    //uses the ArrowDetector object to get all arrows detected and their tips/keypoints
    private func scoreImage() async {
        guard let image = inputImage else { return }
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        do {
            let detector = try ArrowDetector()
            let scored = try await Task.detached(priority: .userInitiated) {
                try detector.process(image: image)
            }.value
            result = scored
            showingResults = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
