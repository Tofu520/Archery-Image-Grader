import UIKit

//flat 2D image for people to click on instead if preferred
enum FlatTargetRenderer {

    static func draw(tips: [CGPoint], scores: [Int], geo: TargetGeometry?, size: CGFloat = 800) -> UIImage {
        let cx = size / 2
        let cy = size / 2
        //allow near miss arrows to still show ups
        let targetR = size * 0.42

        let gold     = UIColor(red: 1.0, green: 0.80, blue: 0.00, alpha: 1)
        let red      = UIColor(red: 0.9, green: 0.10, blue: 0.10, alpha: 1)
        let blue     = UIColor(red: 0.2, green: 0.40, blue: 0.80, alpha: 1)
        let black = UIColor(red: 0.22, green: 0.22, blue: 0.22, alpha: 1)

        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
            let c = ctx.cgContext

            //Off-white background (outside the target rings)
            UIColor(red: 0.94, green: 0.94, blue: 0.90, alpha: 1).setFill()
            c.fill(CGRect(x: 0, y: 0, width: size, height: size))

            let bands: [(UIColor, CGFloat)] = [
                (.white,  1.0),
                (black, 0.8),
                (blue,    0.6),
                (red,     0.4),
                (gold,    0.2),
            ]
            for (color, factor) in bands {
                let r = targetR * factor
                color.setFill()
                c.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            }

            c.setLineWidth(max(1, size / 450))
            UIColor.black.withAlphaComponent(0.20).setStroke()
            for k in 1...10 {
                let rk = targetR * CGFloat(k) / 10
                c.strokeEllipse(in: CGRect(x: cx - rk, y: cy - rk, width: rk * 2, height: rk * 2))
            }

            //crosshair
            let cross: CGFloat = targetR * 0.04
            UIColor.black.withAlphaComponent(0.35).setStroke()
            c.setLineWidth(max(1.5, size / 320))
            c.move(to: CGPoint(x: cx - cross, y: cy)); c.addLine(to: CGPoint(x: cx + cross, y: cy))
            c.move(to: CGPoint(x: cx, y: cy - cross)); c.addLine(to: CGPoint(x: cx, y: cy + cross))
            c.strokePath()

            guard let geo else { return }

            //Map each tip from image-normalized coords → canvas coords.
            //relX/relY are in units of target radii (consistent with ScoringEngine).
            let dotR = max(10, size / 62)
            let font = UIFont.boldSystemFont(ofSize: dotR * 1.4)

            for (tip, score) in zip(tips, scores) {
                let relX = (tip.x - geo.center.x) / geo.radius
                let relY = (tip.y - geo.center.y) / geo.radius
                let px   = cx + relX * targetR
                let py   = cy + relY * targetR

                let dotColor: UIColor
                switch score {
                case 9...10: dotColor = gold
                case 7...8:  dotColor = red
                case 5...6:  dotColor = blue
                default:     dotColor = .white
                }

                dotColor.setFill()
                UIColor.black.setStroke()
                c.setLineWidth(max(1.5, size / 600))
                let rect = CGRect(x: px - dotR, y: py - dotR, width: dotR * 2, height: dotR * 2)
                c.fillEllipse(in: rect)
                c.strokeEllipse(in: rect)

                let label = score > 0 ? "\(score)" : "M"
                let str = NSAttributedString(string: label, attributes: [
                    .font: font,
                    .foregroundColor: UIColor.black,
                ])
                let ts = str.size()
                str.draw(at: CGPoint(x: px + dotR + 2, y: py - ts.height / 2))
            }
        }
    }
}
