import UIKit

// Frozen f4deea8 SthenoWindow body; only the class name is changed for coexistence.
public final class BaselineSthenoWindow: UIWindow {

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        windowLevel = UIWindow.Level.alert + 1
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // 0x103a8：只有落在浮窗上的触摸才吃掉，其余透传给宿主
        let hit = super.hitTest(point, with: event)
        if hit === self { return nil }
        return hit
    }
}
