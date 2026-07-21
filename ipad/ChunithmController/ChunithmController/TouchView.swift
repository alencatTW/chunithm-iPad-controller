import UIKit

protocol TouchViewDelegate: AnyObject {
    func touchMaskChanged(_ mask: UInt32)
}

// 全螢幕多點觸控區，支援兩種模式：
//   .classic32 — 16 直行 × 2 橫列 = 32 個觸控格，對應 32-bit 狀態 (原本的 chunithm 版面)
//   .dfjk4     — 螢幕分成 4 直條，由左到右對應 d f j k 這 4 個鍵
//
// bit 編號 (必須與 Windows 端的 kScan 順序一致):
//   classic32：螢幕上半 = 上層 = bit 16..31 (由左到右遞增)，螢幕下半 = 下層 = bit 0..15 (由左到右遞增)
//   dfjk4：直接借用 kScan 下層裡 d/f/j/k 對應的 bit (3 / 5 / 11 / 13)，Windows 端完全不用改
// 想對調上下層只要改 bitIndex() 裡的那行 (upper ? 16 : 0)。
final class TouchView: UIView {
    enum Mode {
        case classic32
        case dfjk4
    }

    weak var delegate: TouchViewDelegate?

    private(set) var mode: Mode = .classic32

    private let columns = 16
    // dfjk4 模式：4 直條由左到右對應的 bit index (對照 kScan：d=3 f=5 j=11 k=13)
    private let dfjkBits = [3, 5, 11, 13]
    private let dfjkLabels = ["D", "F", "J", "K"]

    private var activeTouches = Set<UITouch>()
    private var currentMask: UInt32 = 0

    override init(frame: CGRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        isMultipleTouchEnabled = true       // 關鍵：開啟多點觸控
        backgroundColor = .black
        contentMode = .redraw
    }

    // 切換模式：清空目前按住的狀態，避免切換瞬間殘留卡鍵。
    func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        activeTouches.removeAll()
        currentMask = 0
        delegate?.touchMaskChanged(0)
        setNeedsDisplay()
    }

    // 一個座標 -> 對應的 bit index
    private func bitIndex(for point: CGPoint) -> Int {
        switch mode {
        case .classic32:
            let cellWidth = bounds.width / CGFloat(columns)
            var col = Int(point.x / cellWidth)
            col = max(0, min(columns - 1, col))
            let upper = point.y < bounds.height / 2     // 上半螢幕為上層
            return (upper ? 16 : 0) + col
        case .dfjk4:
            let cellWidth = bounds.width / CGFloat(dfjkBits.count)
            var col = Int(point.x / cellWidth)
            col = max(0, min(dfjkBits.count - 1, col))
            return dfjkBits[col]
        }
    }

    // 依目前所有按住的觸點，重算 32-bit 狀態；有變化才通知。
    private func recomputeMask() {
        var mask: UInt32 = 0
        for touch in activeTouches {
            let p = touch.location(in: self)
            mask |= UInt32(1) << bitIndex(for: p)
        }
        if mask != currentMask {
            currentMask = mask
            delegate?.touchMaskChanged(mask)
            setNeedsDisplay()               // 狀態變了才重畫
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        activeTouches.formUnion(touches)
        recomputeMask()
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        recomputeMask()                     // 手指滑動 -> 重算覆蓋的格子
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        activeTouches.subtract(touches)
        recomputeMask()
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        activeTouches.subtract(touches)
        recomputeMask()
    }

    // ---- 視覺回饋：畫格線，被按住的格子高亮 ----
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        switch mode {
        case .classic32:
            drawClassic32(ctx)
        case .dfjk4:
            drawDfjk4(ctx)
        }
    }

    private func drawClassic32(_ ctx: CGContext) {
        let cellWidth = bounds.width / CGFloat(columns)
        let rowHeight = bounds.height / 2

        for col in 0..<columns {
            for row in 0..<2 {              // row 0 = 上層(上半), row 1 = 下層(下半)
                let bit = (row == 0 ? 16 : 0) + col
                let isOn = (currentMask & (UInt32(1) << bit)) != 0
                let cell = CGRect(x: CGFloat(col) * cellWidth,
                                  y: CGFloat(row) * rowHeight,
                                  width: cellWidth, height: rowHeight)
                ctx.setFillColor(isOn
                    ? UIColor.systemTeal.cgColor
                    : UIColor(white: 0.12, alpha: 1).cgColor)
                ctx.fill(cell.insetBy(dx: 1, dy: 1))   // 留 1px 縫當格線
            }
        }
    }

    private func drawDfjk4(_ ctx: CGContext) {
        let cellWidth = bounds.width / CGFloat(dfjkBits.count)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 64, weight: .bold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.35),
        ]

        for (col, bit) in dfjkBits.enumerated() {
            let isOn = (currentMask & (UInt32(1) << bit)) != 0
            let cell = CGRect(x: CGFloat(col) * cellWidth, y: 0,
                              width: cellWidth, height: bounds.height)
            ctx.setFillColor(isOn
                ? UIColor.systemTeal.cgColor
                : UIColor(white: 0.12, alpha: 1).cgColor)
            ctx.fill(cell.insetBy(dx: 1, dy: 1))   // 留 1px 縫當格線

            let label = dfjkLabels[col] as NSString
            let size = label.size(withAttributes: labelAttrs)
            let origin = CGPoint(x: cell.midX - size.width / 2, y: cell.midY - size.height / 2)
            label.draw(at: origin, withAttributes: labelAttrs)
        }
    }
}
