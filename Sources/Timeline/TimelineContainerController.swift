import UIKit

public final class TimelineContainerController: UIViewController {
  /// Content Offset to be set once the view size has been calculated
  public var pendingContentOffset: CGPoint?
  
  public private(set) lazy var timeline = TimelineView()
  public private(set) lazy var container: TimelineContainer = {
    let view = TimelineContainer(timeline)
    view.addSubview(timeline)
    return view
  }()
  
  /// Stacks the all-day events above the scrolling timeline, so they push the hours down instead of covering them.
  /// The all-day view is hidden on days without all-day events, which collapses its row in the stack view
  public override func loadView() {
    let allDayView = timeline.allDayView
    let stackView = UIStackView(arrangedSubviews: [allDayView, container])
    stackView.axis = .vertical
    stackView.clipsToBounds = true
    view = stackView
  }
  
  public override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    container.contentSize = timeline.frame.size
    if let newOffset = pendingContentOffset {
      // Apply new offset only once the size has been determined
      if view.bounds != .zero {
        container.setContentOffset(newOffset, animated: false)
        container.setNeedsLayout()
        pendingContentOffset = nil
      }
    }
  }
}
