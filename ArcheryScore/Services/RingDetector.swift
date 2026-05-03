import UIKit
import CoreGraphics

struct TargetGeometry {
    let center: CGPoint   //normalized 0–1
    let radius: CGFloat   //fraction of image width
}

//assumes user at least tried to center the photo taken

//main idea: use color segmentation to find center of circle, then use known WA ratios to create a target
//we use HSV because the colors like gold is much easier to define than RGB

//we run a bfs to find blobs of gold to guess what the radius of the circle is
//the gold,red,blue and other colors all have a known amount of radius of the target they take, so we can calculate the radius using that
//we can have multiple gold blobs, so we take the one who is closer to the center

enum RingDetector {
    
    static func detect(in image: UIImage) -> TargetGeometry? {
        guard let cgImage = image.cgImage else { return nil }

        let origW = CGFloat(cgImage.width)
        let origH = CGFloat(cgImage.height)
        
        //scale down to make faster
        let workSize: CGFloat = 800
        let scale = workSize / min(origW, origH)
        let sw = Int(origW * scale)
        let sh = Int(origH * scale)
        let shortSide = CGFloat(min(sw, sh))

        guard let pixels = rasterize(cgImage, width: sw, height: sh) else { return nil }

        let gold = mask(pixels, w: sw, h: sh, hMin: 15, hMax: 45, sMin: 80, vMin: 80)

        let minGoldRadius = shortSide * 0.03

        let goldBlobs = findBlobs(in: gold, w: sw, h: sh, minPixels: 100)
        guard !goldBlobs.isEmpty else { return nil }

        struct Candidate {
            let cx, cy, R: CGFloat
            let distToCenter: CGFloat
        }

        let imgCX = CGFloat(sw) / 2
        let imgCY = CGFloat(sh) / 2

        var candidates: [Candidate] = []

        for blob in goldBlobs {
            //filters out small blobs like arrow nocks — gold zone must be at least 3% of short side
            guard blob.radius >= minGoldRadius else { continue }

            //use only gold for radius
            let R = blob.radius / 0.20  //gold = inner 20% of total target radius

            //need reasonable radius (5%–95% of short side)
            guard R >= shortSide * 0.05, R <= shortSide * 0.95 else { continue }

            candidates.append(Candidate(
                cx: blob.cx, cy: blob.cy, R: R,
                distToCenter: hypot(blob.cx - imgCX, blob.cy - imgCY)
            ))
        }

        guard !candidates.isEmpty else { return nil }

        //Pick target closest to image center
        let best = candidates.min(by: { $0.distToCenter < $1.distToCenter })!

        //Convert back to original image normalized coords
        let normCX = (best.cx / scale) / origW
        let normCY = (best.cy / scale) / origH
        let normR  = (best.R  / scale) / origW

        return TargetGeometry(center: CGPoint(x: normCX, y: normCY), radius: normR)
    }

    private struct Blob { let cx, cy, radius: CGFloat }

    //Find connected blobs in a binary mask; returns centroid + mean-radius estimate.
    private static func findBlobs(in mask: [Bool], w: Int, h: Int, minPixels: Int) -> [Blob] {
        var visited = [Bool](repeating: false, count: w * h)
        var blobs: [Blob] = []

        for startY in 0..<h {
            for startX in 0..<w {
                let startIdx = startY * w + startX
                guard mask[startIdx], !visited[startIdx] else { continue }

                //bfs to find blobs
                var queue = [startIdx]
                var pixels: [(x: Int, y: Int)] = []
                visited[startIdx] = true

                var qi = 0
                while qi < queue.count {
                    let idx = queue[qi]; qi += 1
                    let x = idx % w, y = idx / w
                    pixels.append((x, y))

                    for (dx, dy) in [(-1,0),(1,0),(0,-1),(0,1)] {
                        let nx = x+dx, ny = y+dy
                        guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                        let nidx = ny*w+nx
                        guard mask[nidx], !visited[nidx] else { continue }
                        visited[nidx] = true
                        queue.append(nidx)
                    }
                }

                guard pixels.count >= minPixels else { continue }
                
                //summary: we get center of blob then need to calculate radius of blob
                
                //take average of all pixels of the blob to get center of blob to be used to estimate blob radius/ center radius for gold
                let cx = CGFloat(pixels.reduce(0) { $0 + $1.x }) / CGFloat(pixels.count)
                let cy = CGFloat(pixels.reduce(0) { $0 + $1.y }) / CGFloat(pixels.count)
                let center = CGPoint(x: cx, y: cy)
                
                //every pixel in the blob, calculate distance from center
                //average those distances to get an average distance from center
                
                //radius approximation: treat blob as a filled disk where mean pixel distance from center = 2r/3, so r = meanDist * 1.5
                
                let meanDist = pixels.reduce(0.0) {
                    $0 + hypot(CGFloat($1.x) - center.x, CGFloat($1.y) - center.y)
                } / CGFloat(pixels.count)
                let radius = meanDist * 1.5

                blobs.append(Blob(cx: cx, cy: cy, radius: radius))
            }
        }

        return blobs
    }
    
    //turn into grid of pixels to work with from Image: in RGBA
    private static func rasterize(_ cgImage: CGImage, width: Int, height: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &pixels,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }
    
    //helper function to determine if a pixel is a certain color or
    //more specifically does it match these hue range values in each channel
    //returns a boolean array for each pixel
    private static func mask(_ pixels: [UInt8], w: Int, h: Int,
                              hMin: Float, hMax: Float,
                              sMin: Float, vMin: Float) -> [Bool] {
        var out = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) {
            let r = Float(pixels[i*4])   / 255
            let g = Float(pixels[i*4+1]) / 255
            let b = Float(pixels[i*4+2]) / 255
            let (hh, s, v) = rgbToHSV(r, g, b)
            out[i] = hh >= hMin && hh <= hMax && s*255 >= sMin && v*255 >= vMin
        }
        return out
    }
    
    //RGB → HSV with H in [0, 180] 
    private static func rgbToHSV(_ r: Float, _ g: Float, _ b: Float) -> (h: Float, s: Float, v: Float) {
        let cMax = max(r, g, b), cMin = min(r, g, b), delta = cMax - cMin
        let v = cMax
        let s = cMax > 0 ? delta / cMax : 0
        var h: Float = 0
        if delta > 0 {
            if cMax == r      { h = 30 * ((g-b)/delta).truncatingRemainder(dividingBy: 6) }
            else if cMax == g { h = 30 * ((b-r)/delta + 2) }
            else              { h = 30 * ((r-g)/delta + 4) }
        }
        if h < 0 { h += 180 }
        return (h, s, v)
    }
    
}

