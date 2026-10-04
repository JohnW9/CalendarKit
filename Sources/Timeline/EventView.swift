import UIKit

open class EventView: UIView {
  /// Posted when the tick box of an event is tapped, the notification's object is the event's descriptor
  public static let didToggleDoneNotification = Notification.Name("EventViewDidToggleDone")

  public var descriptor: EventDescriptor?
  public var color = SystemColors.label
  /// Fill color of the event, drawn as a rounded rect in draw(_:) instead of using the view's backgroundColor
  private var fillColor: UIColor = .clear
  // button modification
  //public var colorTag: String
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    // double "success" vibration when a task is ticked off, like a completed Apple Pay payment
    private let notificationGenerator = UINotificationFeedbackGenerator()

  /// Line drawn over the text when the task is done, animated from left to right when ticking
  private lazy var strikethroughLayer: CAShapeLayer = {
    let layer = CAShapeLayer()
    layer.fillColor = nil
    layer.lineWidth = 1.5
    layer.lineCap = .round
    layer.strokeEnd = 0
    return layer
  }()
  private let strikethroughAnimationKey = "strikethrough"

  public var contentHeight: CGFloat {
    textView.frame.height
  }

  public private(set) lazy var textView: UITextView = {
    // Built on TextKit 1 from the start: the strikethrough reads the layoutManager, which would otherwise
    // force every text view to switch from TextKit 2 to TextKit 1 at runtime (slow, especially the first time)
    let textStorage = NSTextStorage()
    let layoutManager = NSLayoutManager()
    textStorage.addLayoutManager(layoutManager)
    let textContainer = NSTextContainer(size: .zero)
    textContainer.widthTracksTextView = true
    layoutManager.addTextContainer(textContainer)
    let view = UITextView(frame: .zero, textContainer: textContainer)
    view.isUserInteractionEnabled = false
    view.backgroundColor = .clear
    view.isScrollEnabled = false
    // Remove the default padding so the text can be positioned precisely next to the tick button
    view.textContainerInset = .zero
    view.textContainer.lineFragmentPadding = 0
    return view
  }()
    
    //button modification
    public private(set) lazy var button: LargerButtonArea = {
        let button = LargerButtonArea()
        //button.setBackgroundImage(UIImage(named: tagToTickImage(tagName: descriptor?.color), isDone: descriptor.isDone, for: .normal))
        //button.setBackgroundImage(UIImage(named:"BlueTick"), for: .normal)
        button.imageEdgeInsets = UIEdgeInsets(top: 100, left: 100, bottom: 100, right: 100)
        button.addTarget(self, action: #selector(CalTaskButtonTapped), for: .touchUpInside)
        return button
    }()
    //button modification
    //used to make the clickable area bigger
   public class LargerButtonArea: UIButton {
        public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            return bounds.insetBy(dx: -10, dy: -10).contains(point)
        }
    }
    
    /*
    @IBDesignable
    public class GRCustomButton: UIButton {

        @IBInspectable var margin:CGFloat = 20.0
        public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            //increase touch area for control in all directions by 20

            let area = self.bounds.insetBy(dx: -margin, dy: -margin)
            return area.contains(point)
        }
    }*/
    
    //button modification
    @objc func CalTaskButtonTapped() {
        //button modification
        if let event = descriptor {
            event.isDone = !event.isDone
            //print(descriptor?.color)
            button.setBackgroundImage(UIImage(named:tagToTickImage(tagName: descriptor!.colorTag, isDone: event.isDone)), for: .normal)
            if event.isDone {
                notificationGenerator.notificationOccurred(.success)
            } else {
                impactGenerator.impactOccurred()
            }
            setStrikethrough(visible: event.isDone, animated: true)
            //lets the app react to the tick (e.g. adding the task to the logbook)
            NotificationCenter.default.post(name: EventView.didToggleDoneNotification, object: event)
        } else {
            print("missing event descriptor")
        }
    }

    /// Shows or hides the strikethrough line. When animated, the line is drawn from left to right
    /// (and retracted from right to left when un-ticking)
    private func setStrikethrough(visible: Bool, animated: Bool) {
        let target: CGFloat = visible ? 1 : 0
        guard animated else {
            // don't interrupt a running animation that already heads to the same state
            if strikethroughLayer.strokeEnd != target {
                strikethroughLayer.removeAnimation(forKey: strikethroughAnimationKey)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                strikethroughLayer.strokeEnd = target
                CATransaction.commit()
            }
            return
        }
        // start from the currently displayed value so quick double taps don't jump
        let current = strikethroughLayer.presentation()?.strokeEnd ?? strikethroughLayer.strokeEnd
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = current
        animation.toValue = target
        animation.duration = 0.35 * abs(Double(target - current))
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strikethroughLayer.strokeEnd = target
        CATransaction.commit()
        strikethroughLayer.add(animation, forKey: strikethroughAnimationKey)
    }

    /// Builds one horizontal line per visible line of text, in reading order,
    /// so animating strokeEnd draws through them one after another
    private func updateStrikethroughPath() {
        let layoutManager = textView.layoutManager
        let textContainer = textView.textContainer
        layoutManager.ensureLayout(for: textContainer)
        let font = textView.font ?? UIFont.systemFont(ofSize: 12)
        let rightToLeft = UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .rightToLeft
        let text = textView.text as NSString? ?? ""
        let path = UIBezierPath()
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { rect, _, _, lineGlyphRange, _ in
            // skip lines that are only whitespace / newlines
            let charRange = layoutManager.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
            let lineText = text.substring(with: charRange).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lineText.isEmpty else { return }
            // measure only the visible characters, excluding trailing whitespace
            let trimmedEnd = charRange.location + (text.substring(with: charRange) as NSString)
                .range(of: lineText, options: .backwards).upperBound
            let trimmedRange = NSRange(location: charRange.location, length: trimmedEnd - charRange.location)
            let trimmedGlyphs = layoutManager.glyphRange(forCharacterRange: trimmedRange, actualCharacterRange: nil)
            let usedRect = layoutManager.boundingRect(forGlyphRange: trimmedGlyphs, in: textContainer)
            let baseline = rect.minY + layoutManager.location(forGlyphAt: lineGlyphRange.location).y
            let y = baseline - font.xHeight / 2
            // ignore lines that are cut off by the bottom of the event
            guard y < self.textView.bounds.height else { return }
            let startX = rightToLeft ? usedRect.maxX : usedRect.minX
            let endX = rightToLeft ? usedRect.minX : usedRect.maxX
            path.move(to: CGPoint(x: startX, y: y))
            path.addLine(to: CGPoint(x: endX, y: y))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strikethroughLayer.frame = textView.bounds
        strikethroughLayer.path = path.cgPath
        strikethroughLayer.strokeColor = (textView.textColor ?? SystemColors.label).cgColor
        CATransaction.commit()
    }

  /// Resize Handle views showing up when editing the event.
  /// The top handle has a tag of `0` and the bottom has a tag of `1`
  public private(set) lazy var eventResizeHandles = [EventResizeHandleView(), EventResizeHandleView()]

  override public init(frame: CGRect) {
    super.init(frame: frame)
    configure()
  }

  required public init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
    configure()
  }

  /// Corner radius applied to the event's background and left color stripe
  public var cornerRadius: CGFloat = 10 {
    didSet {
      layer.cornerRadius = cornerRadius
      setNeedsDisplay()
    }
  }

  /// Width of the color stripe along the event's leading edge
  public var stripeWidth: CGFloat = 6 {
    didSet {
      setNeedsDisplay()
    }
  }

  /// Width actually used by the stripe, zero when the event hides it
  private var visibleStripeWidth: CGFloat {
    (descriptor?.showsStripe ?? true) ? stripeWidth : 0
  }

  open func configure() {
    clipsToBounds = false
    isOpaque = false
    backgroundColor = .clear
    contentMode = .redraw // redraw on resize so the rounded corners don't get stretched
    layer.cornerRadius = cornerRadius
    layer.cornerCurve = .continuous
    color = tintColor
    addSubview(textView)
    textView.layer.addSublayer(strikethroughLayer)
      //button modification
      addSubview(button)
    
    for (idx, handle) in eventResizeHandles.enumerated() {
      handle.tag = idx
      addSubview(handle)
    }
  }

  public func updateWithDescriptor(event: EventDescriptor) {
    if let attributedText = event.attributedText {
      textView.attributedText = attributedText
    } else {
      textView.text = event.text
      textView.textColor = event.textColor
      textView.font = event.font
    }
    if let lineBreakMode = event.lineBreakMode {
      textView.textContainer.lineBreakMode = lineBreakMode
    }
    descriptor = event
    // The view's own backgroundColor is filled as a square, since clipsToBounds is off,
    // so the rounded background is drawn in draw(_:) instead
    fillColor = event.backgroundColor
    color = event.color
      
      //button modification
      button.setBackgroundImage(UIImage(named:tagToTickImage(tagName: descriptor!.colorTag, isDone: descriptor!.isDone)), for: .normal)
      button.isHidden = !event.isTickable //events that are not tasks have no tick box
      setStrikethrough(visible: event.isTickable && event.isDone, animated: false)
      
    eventResizeHandles.forEach{
      $0.borderColor = event.color
      $0.isHidden = event.editedEvent == nil
    }
    drawsShadow = event.editedEvent != nil
      print("updateWithDescriptor")
    setNeedsDisplay()
    setNeedsLayout()
  }
  
  public func animateCreation() {
    transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
    func scaleAnimation() {
      transform = .identity
    }
    UIView.animate(withDuration: 0.2,
                   delay: 0,
                   usingSpringWithDamping: 0.2,
                   initialSpringVelocity: 10,
                   options: [],
                   animations: scaleAnimation,
                   completion: nil)
  }

  /**
   Custom implementation of the hitTest method is needed for the tap gesture recognizers
   located in the ResizeHandleView to work.
   Since the ResizeHandleView could be outside of the EventView's bounds, the touches to the ResizeHandleView
   are ignored.
   In the custom implementation the method is recursively invoked for all of the subviews,
   regardless of their position in relation to the Timeline's bounds.
   */
  public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    for resizeHandle in eventResizeHandles {
      if let subSubView = resizeHandle.hitTest(convert(point, to: resizeHandle), with: event) {
        return subSubView
      }
    }
    return super.hitTest(point, with: event)
  }

  override open func draw(_ rect: CGRect) {
    super.draw(rect)
    guard let context = UIGraphicsGetCurrentContext() else {
      return
    }
    context.interpolationQuality = .none
    context.saveGState()
    // Clip the stripe to the rounded shape, since clipsToBounds is off (resize handles sit outside the bounds)
    let roundedPath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius)
    roundedPath.addClip()
    fillColor.setFill()
    roundedPath.fill()
    // Draw the color stripe as a filled bar along the leading edge
    let leftToRight = UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .leftToRight
    let x: CGFloat = leftToRight ? 0 : bounds.width - visibleStripeWidth
    color.setFill()
    context.fill(CGRect(x: x, y: 0, width: visibleStripeWidth, height: bounds.height))
    context.restoreGState()
  }

  private var drawsShadow = false

  override open func layoutSubviews() {
    super.layoutSubviews()
    //button modification
    //tick button sits after the color stripe, the text follows right next to it
    let rightToLeft = UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .rightToLeft
    let buttonSize: CGFloat = 25
    let buttonLeading = visibleStripeWidth + 8
    let textSpacing: CGFloat = 8
    let textTrailingPadding: CGFloat = 6
    // keep the button near the top for long tasks, centered vertically for short ones
    let buttonY = min(10, (bounds.height - buttonSize) / 2)
    let buttonX = rightToLeft ? bounds.width - buttonLeading - buttonSize : buttonLeading
    button.frame = CGRect(x: buttonX, y: buttonY, width: buttonSize, height: buttonSize)

    // center the first line of text on the button
    let lineHeight = (textView.font ?? UIFont.systemFont(ofSize: 12)).lineHeight
    let textY = buttonY + (buttonSize - lineHeight) / 2
    //without a tick box the text takes its place
    let textLeading = button.isHidden ? buttonLeading : buttonLeading + buttonSize + textSpacing
    let textWidth = max(0, bounds.width - textLeading - textTrailingPadding)
    let textX = rightToLeft ? textTrailingPadding : textLeading
    textView.frame = CGRect(x: textX, y: textY, width: textWidth, height: bounds.height - textY)
    textView.textAlignment = rightToLeft ? .right : .left
    if frame.minY < 0 {
      var textFrame = textView.frame;
      textFrame.origin.y = textY - frame.minY;
      textFrame.size.height += frame.minY;
      textView.frame = textFrame;
    }
    updateStrikethroughPath()
    let first = eventResizeHandles.first
    let last = eventResizeHandles.last
    let radius: CGFloat = 40
    let yPad: CGFloat =  -radius / 2
    let width = bounds.width
    let height = bounds.height
    let size = CGSize(width: radius, height: radius)
    first?.frame = CGRect(origin: CGPoint(x: width - radius - layoutMargins.right, y: yPad),
                          size: size)
    last?.frame = CGRect(origin: CGPoint(x: layoutMargins.left, y: height - yPad - radius),
                         size: size)
    if drawsShadow {
      applySketchShadow(alpha: 0.13,
                        blur: 10)
    }
  }

  private func applySketchShadow(
    color: UIColor = .black,
    alpha: Float = 0.5,
    x: CGFloat = 0,
    y: CGFloat = 2,
    blur: CGFloat = 4,
    spread: CGFloat = 0)
  {
    layer.shadowColor = color.cgColor
    layer.shadowOpacity = alpha
    layer.shadowOffset = CGSize(width: x, height: y)
    layer.shadowRadius = blur / 2.0
    if spread == 0 {
      layer.shadowPath = nil
    } else {
      let dx = -spread
      let rect = bounds.insetBy(dx: dx, dy: dx)
      layer.shadowPath = UIBezierPath(rect: rect).cgPath
    }
  }
}
