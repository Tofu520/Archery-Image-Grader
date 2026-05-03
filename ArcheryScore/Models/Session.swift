import SwiftData
import UIKit

@Model //needs to persist or else sessions won't be saved
class Session {
    var date: Date
    var total: Int
    var scores: [Int]
    var imageFilename: String   //flat 2D target render
    var tipsData: Data = Data()
    var targetCenterX: Double?
    var targetCenterY: Double?
    var targetRadius: Double?

    init(date: Date, total: Int, scores: [Int],
         imageFilename: String,
         tipsData: Data = Data(),
         targetCenterX: Double? = nil,
         targetCenterY: Double? = nil,
         targetRadius: Double? = nil) {
        self.date = date
        self.total = total
        self.scores = scores
        self.imageFilename = imageFilename
        self.tipsData = tipsData
        self.targetCenterX = targetCenterX
        self.targetCenterY = targetCenterY
        self.targetRadius = targetRadius
    }

    //holds the geometry from when the original image was scored to allow editing
    var geo: TargetGeometry? {
        guard let cx = targetCenterX, let cy = targetCenterY, let r = targetRadius else { return nil }
        return TargetGeometry(center: CGPoint(x: cx, y: cy), radius: CGFloat(r))
    }

    //tips are CG points and were saved using JSONEncoder()
    var tips: [CGPoint] {
        (try? JSONDecoder().decode([CGPoint].self, from: tipsData)) ?? []
    }

    func loadImage() -> UIImage? {
        UIImage(contentsOfFile: Self.documentsURL(for: imageFilename).path)
    }

    func updateSession(flatImage: UIImage, newTips: [CGPoint], newScores: [Int]) {
        if let data = Self.jpegData(for: flatImage) {
            try? data.write(to: Self.documentsURL(for: imageFilename), options: .atomic)
        }
        tipsData = (try? JSONEncoder().encode(newTips)) ?? Data()
        scores = newScores
        total = newScores.reduce(0, +)
    }

    func deleteImage() {
        try? FileManager.default.removeItem(at: Self.documentsURL(for: imageFilename))
    }

    //use the UUID as the unique path name for each file
    static func save(flat: UIImage, tips: [CGPoint]) -> (String, Data)? {
        let id = UUID().uuidString
        let flatName = "\(id)_flat.jpg"
        guard let flatData = jpegData(for: flat) else { return nil }
        do {
            try flatData.write(to: documentsURL(for: flatName))
            let td = (try? JSONEncoder().encode(tips)) ?? Data()
            return (flatName, td)
        } catch {
            return nil
        }
    }

    //helper to get the full filename for the CRUD operations with images
    //documentsURL("xxxx_flat.jpg") -> actual absolute path
    static func documentsURL(for filename: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
    }

    //image size to let user clearly see and save some space
    private static func jpegData(for image: UIImage) -> Data? {
        let maxSide: CGFloat = 1280
        let scale = min(maxSide / image.size.width, maxSide / image.size.height, 1.0)
        if scale >= 1.0 { return image.jpegData(compressionQuality: 0.80) }
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: newSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.80)
    }
}
