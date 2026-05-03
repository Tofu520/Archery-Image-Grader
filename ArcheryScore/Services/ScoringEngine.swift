import CoreGraphics

//Distance-based WA ring scoring.
enum ScoringEngine {

    static let numRings = 10

    //tip, center: normalized 0–1 coords.  radius: fraction of image width.
    //Returns score 1–10, or 0 for a miss.
    static func score(tip: CGPoint, center: CGPoint, radius: CGFloat) -> Int {
        let dist = hypot(tip.x - center.x, tip.y - center.y) //euclideian distance from center
        guard dist < radius else { return 0 }
        let ringIdx = Int(dist / radius * CGFloat(numRings))
        return numRings - min(ringIdx, numRings - 1)
    }
    
}
