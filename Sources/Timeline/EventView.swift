import UIKit

open class EventView: UIView {
  public var descriptor: EventDescriptor?
  public var color = SystemColors.label
  // button modification
  //public var colorTag: String
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)

  public var contentHeight: CGFloat {
    textView.frame.height
  }

  public private(set) lazy var textView: UITextView = {
    let view = UITextView()
    view.isUserInteractionEnabled = false
    view.backgroundColor = .clear
    view.isScrollEnabled = false
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
            impactGenerator.impactOccurred()
        } else {
            print("missing event descriptor")
        }
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

  open func configure() {
    clipsToBounds = false
    color = tintColor
    addSubview(textView)
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
    backgroundColor = event.backgroundColor
    color = event.color
      
      //button modification
      button.setBackgroundImage(UIImage(named:tagToTickImage(tagName: descriptor!.colorTag, isDone: descriptor!.isDone)), for: .normal)
      
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
    context.setStrokeColor(color.cgColor)
    context.setLineWidth(3)
    context.translateBy(x: 0, y: 0.5)
    let leftToRight = UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .leftToRight
    let x: CGFloat = leftToRight ? 0 : frame.width - 1  // 1 is the line width
    let y: CGFloat = 0
    context.beginPath()
    context.move(to: CGPoint(x: x, y: y))
    context.addLine(to: CGPoint(x: x, y: (bounds).height))
    context.strokePath()
    context.restoreGState()
  }

  private var drawsShadow = false

  override open func layoutSubviews() {
    super.layoutSubviews()
    textView.frame = {
        if UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .rightToLeft {
            return CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width - 3, height: bounds.height)
        } else {
            return CGRect(x: bounds.minX + 50, y: bounds.minY, width: bounds.width - 3, height: bounds.height)
        }
    }()
    if frame.minY < 0 {
      var textFrame = textView.frame;
      textFrame.origin.y = frame.minY * -1;
      textFrame.size.height += frame.minY;
      textView.frame = textFrame;
    }
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
      //added button frame
      //and button positioning depending of frame (task) size (duration)
    var buttonHeight : CGFloat
      if self.frame.height >= 50 {
          buttonHeight = 10
      } else {
          buttonHeight = 0.3*self.frame.height-5
      }
      button.frame = CGRect(x: 10, y: buttonHeight, width: 20, height: 20)
      //addSubview(button)
      
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
