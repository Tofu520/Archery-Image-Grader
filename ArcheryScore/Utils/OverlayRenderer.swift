import UIKit

//Draws target rings + scored arrow tips onto the image.
//takes in scores tips and geometry (calculated target centers and rings)
enum OverlayRenderer {

    static func draw(on image: UIImage,
                     tips: [CGPoint],
                     scores: [Int],
                     geo: TargetGeometry?) -> UIImage {
        let size = image.size
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in
            image.draw(at: .zero)
            let c = ctx.cgContext

            //Draw target rings if geometry was found
            if let geo {
                let cx = geo.center.x * size.width
                let cy = geo.center.y * size.height
                let R  = geo.radius   * size.width

                let ringColors: [UIColor] = [
                    .white, .white,
                    .darkGray, .darkGray,
                    UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1),
                    UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1),
                    UIColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1),
                    UIColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1),
                    UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1),
                    UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1),
                ]

                c.setLineWidth(max(1, size.width / 400))
                for k in 1...10 {
                    let rk = R * CGFloat(k) / 10
                    ringColors[k - 1].withAlphaComponent(0.6).setStroke()
                    c.strokeEllipse(in: CGRect(x: cx - rk, y: cy - rk, width: rk * 2, height: rk * 2))
                }

                // Crosshair at center
                let cross: CGFloat = R * 0.06
                UIColor.green.setStroke()
                c.setLineWidth(max(2, size.width / 300))
                c.move(to: CGPoint(x: cx - cross, y: cy))
                c.addLine(to: CGPoint(x: cx + cross, y: cy))
                c.move(to: CGPoint(x: cx, y: cy - cross))
                c.addLine(to: CGPoint(x: cx, y: cy + cross))
                c.strokePath()
            }

            // Draw arrow tips
            let dotR = max(10, size.width / 80)
            let font = UIFont.boldSystemFont(ofSize: dotR * 1.4)

            for (tip, score) in zip(tips, scores) {
                let px = tip.x * size.width
                let py = tip.y * size.height

                let color: UIColor
                switch score {
                case 9...10: color = UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1)
                case 7...8:  color = UIColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1)
                case 5...6:  color = UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
                default:     color = .white
                }

                //Filled circle
                color.setFill()
                UIColor.black.setStroke()
                c.setLineWidth(max(1.5, size.width / 600))
                let rect = CGRect(x: px - dotR, y: py - dotR, width: dotR * 2, height: dotR * 2)
                c.fillEllipse(in: rect)
                c.strokeEllipse(in: rect)

                //Score label
                let label = score > 0 ? "\(score)" : "M"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor.black,
                ]
                let str = NSAttributedString(string: label, attributes: attrs)
                let textSize = str.size()
                str.draw(at: CGPoint(
                    x: px + dotR + 2,
                    y: py - textSize.height / 2
                ))
            }
        }
    }
}
