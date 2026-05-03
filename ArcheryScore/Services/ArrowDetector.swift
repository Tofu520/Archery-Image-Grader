import CoreML
import UIKit

struct ScoringResult {
    let scores: [Int]
    let total: Int
    let arrowTips: [CGPoint]     //normalized 0–1, in original image coords
    let targetCenter: CGPoint?   //normalized 0–1
    let targetRadius: CGFloat?   //fraction of image width
    let originalImage: UIImage
    let annotatedImage: UIImage
}

enum DetectorError: LocalizedError {
    case modelNotFound
    case imageConversionFailed
    case outputParseFailed

    var errorDescription: String? {
        switch self {
        case .modelNotFound:         return "Model file not found in app bundle."
        case .imageConversionFailed: return "Could not prepare image for model."
        case .outputParseFailed:     return "Could not read model output."
        }
    }
}

class ArrowDetector {
    private let model: MLModel
    private let inputSize = 1280 //YOLO needs this size
    private let confThreshold: Float    = 0.30  // applied after calibration
    private let rawConfPreFilter: Float = 0.02  // gather candidates before calibration
    private let iouThreshold: Float     = 0.30
    private let temperature: Float      = 3.0   // temperature scaling — fitted on val set

    init() throws {
        guard let url = Bundle.main.url(forResource: "best", withExtension: "mlmodelc") else {
            throw DetectorError.modelNotFound
        }
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine  //avoids MPS warning on simulator
        self.model = try MLModel(contentsOf: url, configuration: config)
    }
    
    
    func process(image: UIImage) throws -> ScoringResult {
        //target detection stops arrow detection from firing immediately — no target means unrelated image
        guard let geo = RingDetector.detect(in: image) else {
            let annotated = OverlayRenderer.draw(on: image, tips: [], scores: [], geo: nil)
            return ScoringResult(
                scores: [], total: 0, arrowTips: [],
                targetCenter: nil, targetRadius: nil,
                originalImage: image, annotatedImage: annotated
            )
        }

        let tips   = try detectArrows(in: image)
        let scores = tips.map { ScoringEngine.score(tip: $0, center: geo.center, radius: geo.radius) }
        let annotated = OverlayRenderer.draw(on: image, tips: tips, scores: scores, geo: geo)

        return ScoringResult(
            scores: scores,
            total: scores.reduce(0, +),
            arrowTips: tips,
            targetCenter: geo.center,
            targetRadius: geo.radius,
            originalImage: image,
            annotatedImage: annotated
        )
    }
    
    private func detectArrows(in image: UIImage) throws -> [CGPoint] {
        guard let pixelBuffer = image.toPixelBuffer(width: inputSize, height: inputSize) else {
            throw DetectorError.imageConversionFailed
        }
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "image": MLFeatureValue(pixelBuffer: pixelBuffer)
        ])
        let output = try model.prediction(from: input)
        guard let array = output.featureValue(for: "var_1030")?.multiArrayValue else {
            throw DetectorError.outputParseFailed
        }
        return parseAndNMS(array)
    }

    //Output shape: [1, 8, 33600]
    //channels: [cx, cy, w, h, conf, kp_x, kp_y, kp_vis]  — pixel space 0–1280
    //deal with multiple clusters of detections because export with nms didn't work
    
    //follows same idea as the NMS on ultralytics
    //filter by confidence -> sort by descending -> keep highest
    private func parseAndNMS(_ array: MLMultiArray) -> [CGPoint] {
        let shape = array.shape.map { $0.intValue }
        // Expect [1, 8, 33600]
        guard shape.count == 3, shape[1] == 8 else { return [] }

        let numAnchors = shape[2]
        let scale = Float(inputSize)

        struct Det {
            var cx, cy, w, h, conf, kpX, kpY: Float
        }

        //Gather candidates above confidence threshold
        var dets: [Det] = []
        dets.reserveCapacity(64)

        for j in 0..<numAnchors {
            let rawConf = array[[0, 4, j] as [NSNumber]].floatValue
            guard rawConf >= rawConfPreFilter else { continue }
            let conf = temperatureScale(rawConf)
            guard conf >= confThreshold else { continue }

            dets.append(Det(
                cx:  array[[0, 0, j] as [NSNumber]].floatValue,
                cy:  array[[0, 1, j] as [NSNumber]].floatValue,
                w:   array[[0, 2, j] as [NSNumber]].floatValue,
                h:   array[[0, 3, j] as [NSNumber]].floatValue,
                conf: conf,
                kpX: array[[0, 5, j] as [NSNumber]].floatValue,
                kpY: array[[0, 6, j] as [NSNumber]].floatValue
            ))
        }

        //Sort by confidence descending
        dets.sort { $0.conf > $1.conf }

        //Greedy NMS
        var kept: [Det] = []
        var suppressed = [Bool](repeating: false, count: dets.count)

        for i in 0..<dets.count {
            guard !suppressed[i] else { continue }
            kept.append(dets[i])
            let a = dets[i]
            for j in (i+1)..<dets.count {
                guard !suppressed[j] else { continue }
                let b = dets[j]
                if iou(a.cx, a.cy, a.w, a.h, b.cx, b.cy, b.w, b.h) > iouThreshold {
                    suppressed[j] = true
                }
            }
        }

        //Return normalized keypoint positions
        return kept.map { d in
            CGPoint(
                x: max(0, min(1, CGFloat(d.kpX / scale))),
                y: max(0, min(1, CGFloat(d.kpY / scale)))
            )
        }
    }

    private func temperatureScale(_ conf: Float) -> Float {
        let clamped = max(1e-9, min(1 - 1e-9, conf))
        let logit   = log(clamped / (1 - clamped))
        return 1.0 / (1.0 + exp(-logit / temperature))
    }

    private func iou(_ cx1: Float, _ cy1: Float, _ w1: Float, _ h1: Float,
                     _ cx2: Float, _ cy2: Float, _ w2: Float, _ h2: Float) -> Float {
        let x1 = max(cx1 - w1/2, cx2 - w2/2)
        let y1 = max(cy1 - h1/2, cy2 - h2/2)
        let x2 = min(cx1 + w1/2, cx2 + w2/2)
        let y2 = min(cy1 + h1/2, cy2 + h2/2)
        let inter = max(0, x2-x1) * max(0, y2-y1)
        let union = w1*h1 + w2*h2 - inter
        return union > 0 ? inter / union : 0
    }
}

