import UIKit

public protocol TimelinePagerViewDelegate: AnyObject {
  func timelinePagerDidSelectEventView(_ eventView: EventView)
  func timelinePagerDidLongPressEventView(_ eventView: EventView)
  func timelinePager(timelinePager: TimelinePagerView, didTapTimelineAt date: Date)
  func timelinePagerDidBeginDragging(timelinePager: TimelinePagerView)
  func timelinePagerDidTransitionCancel(timelinePager: TimelinePagerView)
  func timelinePager(timelinePager: TimelinePagerView, willMoveTo date: Date)
  func timelinePager(timelinePager: TimelinePagerView, didMoveTo  date: Date)
  func timelinePager(timelinePager: TimelinePagerView, didLongPressTimelineAt date: Date)

  // Editing
  func timelinePager(timelinePager: TimelinePagerView, didUpdate event: EventDescriptor)
}

public final class TimelinePagerView: UIView, UIGestureRecognizerDelegate, UIScrollViewDelegate, DayViewStateUpdating, UIPageViewControllerDataSource, UIPageViewControllerDelegate, TimelineViewDelegate {

  public weak var dataSource: EventDataSource?
  public weak var delegate: TimelinePagerViewDelegate?

  public private(set) var calendar: Calendar = Calendar.autoupdatingCurrent
  public var eventEditingSnappingBehavior: EventEditingSnappingBehavior {
    didSet {
      updateEventEditingSnappingBehavior()
    }
  }

  public var timelineScrollOffset: CGPoint {
    // Any view is fine as they are all synchronized
    let offset = (currentTimeline)?.container.contentOffset
    return offset ?? CGPoint()
  }
  
  private var currentTimeline: TimelineContainerController? {
    pagingViewController.viewControllers?.first as? TimelineContainerController
  }

  public var autoScrollToFirstEvent = false

  private var pagingViewController = UIPageViewController(transitionStyle: .scroll,
                                                  navigationOrientation: .horizontal,
                                                  options: nil)
  /// Scroll view used internally by the page view controller to swipe between days
  private var pagingScrollView: UIScrollView? {
    pagingViewController.view.subviews.first { $0 is UIScrollView } as? UIScrollView
  }
  private var style = TimelineStyle()

  private lazy var panGestureRecognizer = UIPanGestureRecognizer(target: self,
                                                          action: #selector(handlePanGesture(_:)))
  
  public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
    if otherGestureRecognizer.view is EventResizeHandleView {
      return false
    }
    return true
  }

  /// While an edited event is dragged, the page view controller must not swipe to another day at the same time
  public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
    gestureRecognizer == panGestureRecognizer && otherGestureRecognizer.view === pagingScrollView
  }

  public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard gestureRecognizer == panGestureRecognizer else {
      return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
    // Nothing to drag, so the pan must fail to let the page view controller swipe between days
    guard let pendingEvent = editedEventView else {return false}
    let eventFrame = pendingEvent.frame
    let position = panGestureRecognizer.location(in: self)
    let contains = eventFrame.contains(position)
    return contains
  }

  public weak var state: DayViewState? {
    willSet(newValue) {
      state?.unsubscribe(client: self)
    }
    didSet {
      state?.subscribe(client: self)
    }
  }

  public init(calendar: Calendar) {
    self.calendar = calendar
    self.eventEditingSnappingBehavior = SnapTo15MinuteIntervals(calendar)
    super.init(frame: .zero)
    configure()
  }

  override public init(frame: CGRect) {
    self.eventEditingSnappingBehavior = SnapTo15MinuteIntervals(calendar)
    super.init(frame: frame)
    configure()
  }

  required public init?(coder aDecoder: NSCoder) {
    self.eventEditingSnappingBehavior = SnapTo15MinuteIntervals(calendar)
    super.init(coder: aDecoder)
    configure()
  }

  private func configure() {
    let viewController = configureTimelineController(date: Date())
    pagingViewController.setViewControllers([viewController], direction: .forward, animated: false, completion: nil)
    pagingViewController.dataSource = self
    pagingViewController.delegate = self
    addSubview(pagingViewController.view!)
    // the edited event is a subview of the pager, not of the scrolling timeline: dragged past the top of the
    // timeline it would otherwise be drawn over the header above
    clipsToBounds = true
    addGestureRecognizer(panGestureRecognizer)
    panGestureRecognizer.delegate = self
  }

  public func updateStyle(_ newStyle: TimelineStyle) {
    style = newStyle
    pagingViewController.viewControllers?.forEach({ (timelineContainer) in
      if let controller = timelineContainer as? TimelineContainerController {
        self.updateStyleOfTimelineContainer(controller: controller)
      }
    })
    pagingViewController.view.backgroundColor = style.backgroundColor
  }

  private func updateStyleOfTimelineContainer(controller: TimelineContainerController) {
    let container = controller.container
    let timeline = controller.timeline
    timeline.updateStyle(style)
    container.backgroundColor = style.backgroundColor
  }
  
  private func updateEventEditingSnappingBehavior() {
    pagingViewController.viewControllers?.forEach({ (timelineContainer) in
      if let controller = timelineContainer as? TimelineContainerController {
        controller.timeline.eventEditingSnappingBehavior = eventEditingSnappingBehavior
      }
    })
  }

  public func timelinePanGestureRequire(toFail gesture: UIGestureRecognizer) {
    for controller in pagingViewController.viewControllers ?? [] {
      if let controller = controller as? TimelineContainerController {
        let container = controller.container
        container.panGestureRecognizer.require(toFail: gesture)
      }
    }
  }

  public func scrollTo(hour24: Float, animated: Bool = true) {
    // Any view is fine as they are all synchronized
    if let controller = currentTimeline {
      controller.container.scrollTo(hour24: hour24, animated: animated)
    }
  }

  private func configureTimelineController(date: Date) -> TimelineContainerController {
    let controller = TimelineContainerController()
    updateStyleOfTimelineContainer(controller: controller)
    let timeline = controller.timeline
    timeline.longPressGestureRecognizer.addTarget(self, action: #selector(timelineDidLongPress(_:)))
    timeline.delegate = self
    timeline.calendar = calendar
    timeline.eventEditingSnappingBehavior = eventEditingSnappingBehavior
    timeline.date = date.dateOnly(calendar: calendar)
    controller.container.delegate = self
    updateTimeline(timeline)
    return controller
  }

  private var initialContentOffset = CGPoint.zero
  public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    initialContentOffset = scrollView.contentOffset
  }

  public func scrollViewDidScroll(_ scrollView: UIScrollView) {
    // other days' timelines also scroll while paging, only the visible one moves the edited event
    guard scrollView === currentTimeline?.container else {return}
    let offset = scrollView.contentOffset
    let diff = offset.y - initialContentOffset.y
    if let event = editedEventView {
      event.center.y -= diff // by its center, so an ongoing change of width isn't interrupted
      if isMovingEditedEvent {
        updateDropPreview(animated: true) // the time under the dragged event changes
      }
    }
    // always tracked, not only while editing: programmatic scrolls (scrollTo, auto-scroll, safe area changes)
    // don't call scrollViewWillBeginDragging, and a stale offset would make the next edited event jump
    initialContentOffset = offset
  }

  public func reloadData() {
    pagingViewController.children.forEach({ (controller) in
      if let controller = controller as? TimelineContainerController {
        self.updateTimeline(controller.timeline)
      }
    })
  }

  override public func layoutSubviews() {
    super.layoutSubviews()
    pagingViewController.view.frame = bounds
  }

  private func updateTimeline(_ timeline: TimelineView) {
    guard let dataSource = dataSource else {return}
    let date = timeline.date.dateOnly(calendar: calendar)
    let events = dataSource.eventsForDate(date)

    let end = calendar.date(byAdding: .day, value: 1, to: date)!
    let day = DateInterval(start: date, end: end)
    let validEvents = events.filter{$0.dateInterval.intersects(day)}
    timeline.layoutAttributes = validEvents.map(EventLayoutAttributes.init)
    timeline.hiddenEvent = editedEventView?.descriptor?.editedEvent
  }

  /// Hides the original of the event being edited on every timeline, so only its editable copy is shown
  private func updateHiddenEvent() {
    let hiddenEvent = editedEventView?.descriptor?.editedEvent
    pagingViewController.children.forEach { controller in
      (controller as? TimelineContainerController)?.timeline.hiddenEvent = hiddenEvent
    }
  }

  public func scrollToFirstEventIfNeeded(animated: Bool) {
    if autoScrollToFirstEvent {
      if let controller = currentTimeline {
        controller.container.scrollToFirstEvent(animated: animated)
      }
    }
  }

  /// Event view with editing mode active. Can be either edited or newly created event
  private var editedEventView: EventView?
  /// The `EventDescriptor` that is being edited. It's editable copy is used by the `editedEventView`
  private var editedEvent: EventDescriptor?
  
  /// Tag of the last used resize handle
  private var resizeHandleTag: Int?

  /// Creates an EventView and places it on the Timeline
  /// - Parameter event: the EventDescriptor based on which an EventView will be placed on the Timeline
  /// - Parameter animated: if true, CalendarKit animates event creation
  public func create(event: EventDescriptor, animated: Bool) {
    let eventView = EventView()
    eventView.updateWithDescriptor(event: event)
    addSubview(eventView)
    // layout algo
    if let currentTimeline = currentTimeline {
      
      for handle in eventView.eventResizeHandles {
        let panGestureRecognizer = handle.panGestureRecognizer
        panGestureRecognizer.addTarget(self, action: #selector(handleResizeHandlePanGesture(_:)))
        panGestureRecognizer.cancelsTouchesInView = true
      }
      
      let timeline = currentTimeline.timeline
      // algo needs to be extracted to a separate object
      // converted from the timeline, as it is scrolled and sits below the all-day events
      let yStart = convert(CGPoint(x: 0, y: timeline.dateToY(event.dateInterval.start)), from: timeline).y
      let yEnd = convert(CGPoint(x: 0, y: timeline.dateToY(event.dateInterval.end)), from: timeline).y

      // the edited event keeps its place among the events happening at the same time
      let column = horizontalFrame(ofEditedCopyOf: event, in: timeline)
      let newRect = CGRect(x: column.minX,
                           y: yStart,
                           width: column.width,
                           height: yEnd - yStart)
      eventView.frame = newRect
      // the edited event follows scrolling from this offset on
      initialContentOffset = currentTimeline.container.contentOffset


      if animated {
        eventView.animateCreation()
      }
    }
    editedEventView = eventView
    updateHiddenEvent()
    accentDateForEditedEventView()
    // a new event isn't on the timeline yet: the events happening at the same time make room for it right away
    if event.editedEvent == nil || event.editedEvent === event {
      updateDropPreview(animated: animated)
    }
  }
  
  /// Puts timeline in the editing mode and highlights a single event as being edited.
  /// - Parameter event: the `EventDescriptor` to be edited. An editable copy of the `EventDescriptor` is created by calling `makeEditable()` method on the passed value
  /// - Parameter animated: if true, CalendarKit animates beginning of the editing
  public func beginEditing(event: EventDescriptor, animated: Bool = false) {
    if editedEventView == nil {
      editedEvent = event
      let editableCopy = event.makeEditable()
      create(event: editableCopy, animated: animated)
    }
  }

  /// Where the edited event was grabbed: the finger's distance from its center while it is moved, from the dragged
  /// edge while it is resized. The event is placed from the finger rather than moved by the finger's translation,
  /// so it picks up where it was grabbed after being held against the limits of the day
  private var grabOffset: CGPoint = .zero
  /// Last finger location while moving the edited event, the column under it is where the event goes among concurrent events
  private var moveLocation: CGPoint?
  /// True once the edited event has been dragged sideways, only then is it moved to another column among concurrent events
  private var isMovingSideways = false
  /// Horizontal distance the finger must travel before the edited event is moved to another column
  private let sidewaysMoveThreshold: CGFloat = 20
  /// True while the edited event is being moved with the finger
  private var isMovingEditedEvent = false

  @objc func handlePanGesture(_ sender: UIPanGestureRecognizer) {

    if let pendingEvent = editedEventView {
      let location = sender.location(in: self)
      if sender.state == .began {
        isMovingSideways = false
        isMovingEditedEvent = true
        // the event changes width around the finger while it is dragged among concurrent events
        setAnchorPoint(of: pendingEvent, to: sender.location(in: pendingEvent))
        grabOffset = CGPoint(x: location.x - pendingEvent.center.x, y: location.y - pendingEvent.center.y)
      }
      moveLocation = location
      if abs(sender.translation(in: self).x) > sidewaysMoveThreshold {
        isMovingSideways = true
      }

      // moved by its center, so an ongoing change of width isn't interrupted
      pendingEvent.center = CGPoint(x: location.x - grabOffset.x, y: location.y - grabOffset.y)
      if let timeline = currentTimeline?.timeline {
        keepWithinDay(pendingEvent, in: timeline)
      }
      accentDateForEditedEventView()
      updateDayChange(for: location)
      if sender.state == .changed {
        updateDropPreview(animated: true)
        // held near the top or bottom of the timeline, the event scrolls it to the rest of the day
        updateAutoScroll(for: location, resizeHandleTag: nil)
      }
    }

    if sender.state == .ended || sender.state == .cancelled || sender.state == .failed {
      stopDayChange()
      stopAutoScroll()
      isMovingEditedEvent = false
      if let pendingEvent = editedEventView {
        setAnchorPoint(of: pendingEvent, to: CGPoint(x: pendingEvent.bounds.midX, y: pendingEvent.bounds.midY))
      }
    }
    if sender.state == .ended {
      commitEditing()
    } else if sender.state == .cancelled || sender.state == .failed {
      clearDropPreview(animated: true)
    }
  }

  // MARK: Drop preview

  /// Timeline currently showing where the edited event will be dropped
  private weak var dropPreviewTimeline: TimelineView?
  /// Column and number of columns of the drop preview, a light tick is played when they change
  private var dropPreviewSlot: (column: Int, count: Int)?
  private lazy var dropPreviewFeedbackGenerator = UISelectionFeedbackGenerator()

  /// Shows where the edited event will be dropped: the events happening at the same time make room for it,
  /// a grey box shows its place and the event itself takes the size it will have
  /// - Parameter interval: where the event will be dropped, by default the time under the edited event, snapped
  private func updateDropPreview(interval: DateInterval? = nil, animated: Bool) {
    guard let eventView = editedEventView, let descriptor = eventView.descriptor, !descriptor.isAllDay,
          let timeline = currentTimeline?.timeline else {
      return
    }
    if dropPreviewTimeline !== timeline {
      dropPreviewTimeline?.clearDropPreview(animated: false) // the event was moved to another day
      dropPreviewTimeline = timeline
      dropPreviewSlot = nil
    }
    let previewedEvent = descriptor.editedEvent ?? descriptor // the original, hidden while its copy is edited
    let start = timeline.eventEditingSnappingBehavior.nearestDate(to: yToDate(y: eventView.frame.minY, timeline: timeline))
    let interval = interval ?? DateInterval(start: start, duration: previewedEvent.dateInterval.duration)
    guard interval.duration > 0 else {return}

    // once dragged sideways, the event goes into the column under the finger
    let columnX = isMovingSideways ? moveLocation.map { timeline.convert($0, from: self).x } : nil
    timeline.setDropPreview(for: previewedEvent, at: interval, columnAt: columnX, animated: animated)

    let events = timeline.dropPreviewEvents
    if let index = events.firstIndex(where: { $0 === previewedEvent }) {
      let slot = (column: index, count: events.count)
      if let previous = dropPreviewSlot, previous != slot {
        dropPreviewFeedbackGenerator.selectionChanged()
      }
      dropPreviewSlot = slot
    }
    if let frame = timeline.dropPreviewFrame {
      resize(eventView, toWidth: convert(frame, from: timeline).width, animated: animated)
    }
  }

  private func clearDropPreview(animated: Bool) {
    dropPreviewTimeline?.clearDropPreview(animated: animated)
    dropPreviewTimeline = nil
    dropPreviewSlot = nil
  }

  /// Changes the width of the edited event around its anchor point, which is under the finger while it is dragged
  private func resize(_ eventView: EventView, toWidth width: CGFloat, animated: Bool) {
    guard abs(eventView.bounds.width - width) > 0.5 else {return}
    let changes = {
      eventView.bounds.size.width = width
      eventView.layoutIfNeeded()
    }
    guard animated else {
      changes()
      return
    }
    UIView.animate(withDuration: 0.35,
                   delay: 0,
                   usingSpringWithDamping: 0.85,
                   initialSpringVelocity: 0,
                   options: [.beginFromCurrentState, .allowUserInteraction],
                   animations: changes)
  }

  /// Moves the point `view` changes size around to `point` (in its own coordinates), without moving the view
  private func setAnchorPoint(of view: UIView, to point: CGPoint) {
    let size = view.bounds.size
    guard size.width > 0, size.height > 0 else {return}
    let anchorPoint = CGPoint(x: (point.x / size.width).clamped(to: 0...1),
                              y: (point.y / size.height).clamped(to: 0...1))
    let previous = view.layer.anchorPoint
    view.layer.anchorPoint = anchorPoint
    view.center = CGPoint(x: view.center.x + (anchorPoint.x - previous.x) * size.width,
                          y: view.center.y + (anchorPoint.y - previous.y) * size.height)
  }

  /// Horizontal place of the edited copy of `event`, in the pager's coordinates: where its original is shown on the
  /// timeline (in its column, or over a longer event), the whole width of the timeline if it isn't on it
  private func horizontalFrame(ofEditedCopyOf event: EventDescriptor, in timeline: TimelineView) -> (minX: CGFloat, width: CGFloat) {
    if let original = event.editedEvent, let frame = timeline.eventViewFrame(of: original) {
      let converted = convert(frame, from: timeline)
      return (converted.minX, converted.width)
    }
    let rightToLeft = UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .rightToLeft
    let horizontalInset = timeline.style.eventHorizontalInset
    let minX = convert(CGPoint(x: rightToLeft ? 0 : timeline.style.leadingInset, y: 0), from: timeline).x
    return (minX + horizontalInset, timeline.calendarWidth - 2 * horizontalInset)
  }

  // MARK: Moving the edited event to another day

  /// Width of the areas at the left and right edges where holding a dragged event moves it to the previous or next day
  private let dayChangeEdgeWidth: CGFloat = 40
  private var dayChangeTimer: Timer?
  /// -1 while the dragged event is held at the edge of the previous day, 1 for the next day, 0 otherwise
  private var dayChangeDirection = 0
  private lazy var dayChangeFeedbackGenerator = UISelectionFeedbackGenerator()

  private func updateDayChange(for location: CGPoint) {
    var direction = 0
    if location.x < dayChangeEdgeWidth {
      direction = -1
    } else if location.x > bounds.width - dayChangeEdgeWidth {
      direction = 1
    }
    if UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .rightToLeft {
      direction = -direction
    }
    guard direction != dayChangeDirection else {return}
    stopDayChange()
    dayChangeDirection = direction
    if direction != 0 {
      dayChangeFeedbackGenerator.prepare()
      scheduleDayChange(after: 0.5)
    }
  }

  private func scheduleDayChange(after delay: TimeInterval) {
    dayChangeTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
      self?.moveEditedEventToAdjacentDay()
    }
  }

  /// Pages to the previous or next day while the edited event stays under the finger, it is dropped on that day once released
  private func moveEditedEventToAdjacentDay() {
    guard editedEventView != nil, dayChangeDirection != 0, let state = state, let currentTimeline = currentTimeline,
          let newDate = calendar.date(byAdding: .day, value: dayChangeDirection, to: currentTimeline.timeline.date) else {
      return
    }
    currentTimeline.timeline.accentedDate = nil
    currentTimeline.timeline.setNeedsDisplay()
    // the new day's timeline takes the scroll position of the current one once it is laid out: scrolling in the
    // meantime would be lost. The auto-scroll starts again with the next move of the finger
    stopAutoScroll()
    // the new day keeps the same scroll position, so the time under the event doesn't change
    initialContentOffset = currentTimeline.container.contentOffset
    dayChangeFeedbackGenerator.selectionChanged()
    state.move(to: newDate)
    scheduleDayChange(after: 0.8) // keeps paging while the event is held at the edge
  }

  private func stopDayChange() {
    dayChangeTimer?.invalidate()
    dayChangeTimer = nil
    dayChangeDirection = 0
  }

  // MARK: Keeping the edited event within the day

  /// Top and bottom of the day shown by `timeline` (00:00 and 24:00), in the pager's coordinates
  private func dayLimits(in timeline: TimelineView) -> (top: CGFloat, bottom: CGFloat) {
    let top = timeline.dateToY(timeline.date)
    let bottom = top + 24 * timeline.style.verticalDiff
    return (convert(CGPoint(x: 0, y: top), from: timeline).y,
            convert(CGPoint(x: 0, y: bottom), from: timeline).y)
  }

  /// Moves `eventView` back within the day shown by `timeline` if it was dragged before 00:00 or past 24:00.
  /// An event longer than the day starts at 00:00
  private func keepWithinDay(_ eventView: EventView, in timeline: TimelineView) {
    let limits = dayLimits(in: timeline)
    let frame = eventView.frame
    let minY = max(min(frame.minY, limits.bottom - frame.height), limits.top)
    // moved by its center, like while dragged, so an ongoing change of width isn't interrupted
    eventView.center.y += minY - frame.minY
  }

  // MARK: Scrolling the timeline while the edited event is dragged

  /// Height of the areas at the top and bottom of the visible timeline where holding the dragged event scrolls it
  private let autoScrollEdgeHeight: CGFloat = 70
  /// Fastest the timeline scrolls while the dragged event is held at its very edge, in points per second
  private let autoScrollMaxSpeed: CGFloat = 900
  private var autoScrollLink: CADisplayLink?
  /// Points per second, negative scrolls towards the start of the day
  private var autoScrollSpeed: CGFloat = 0
  /// Tag of the resize handle being dragged (see `EventView.eventResizeHandles`), nil while the whole event is moved
  private var autoScrollResizeHandleTag: Int?

  /// Scrolls the timeline faster the closer the finger gets to the top or bottom of its visible part,
  /// and stops once the finger is back between them
  private func updateAutoScroll(for location: CGPoint, resizeHandleTag: Int?) {
    guard let container = currentTimeline?.container else {
      stopAutoScroll()
      return
    }
    let visibleFrame = convert(container.bounds, from: container)
    let top = visibleFrame.minY + container.adjustedContentInset.top
    // the pager may extend under a tab bar, which covers the bottom of the timeline
    let bottom = visibleFrame.maxY - max(container.adjustedContentInset.bottom, safeAreaInsets.bottom)
    if location.y < top + autoScrollEdgeHeight {
      autoScrollSpeed = -autoScrollMaxSpeed * min(1, (top + autoScrollEdgeHeight - location.y) / autoScrollEdgeHeight)
    } else if location.y > bottom - autoScrollEdgeHeight {
      autoScrollSpeed = autoScrollMaxSpeed * min(1, (location.y - (bottom - autoScrollEdgeHeight)) / autoScrollEdgeHeight)
    } else {
      stopAutoScroll()
      return
    }
    autoScrollResizeHandleTag = resizeHandleTag
    if autoScrollLink == nil {
      let link = CADisplayLink(target: self, selector: #selector(autoScrollTick(_:)))
      link.add(to: .main, forMode: .common)
      autoScrollLink = link
    }
  }

  private func stopAutoScroll() {
    autoScrollLink?.invalidate()
    autoScrollLink = nil
    autoScrollSpeed = 0
    autoScrollResizeHandleTag = nil
  }

  /// Scrolls the timeline a little further while the part of the event under the finger stays where it is:
  /// the whole event while it is moved, the dragged edge while it is resized (the other edge keeps its time)
  @objc private func autoScrollTick(_ link: CADisplayLink) {
    guard let eventView = editedEventView, let currentTimeline = currentTimeline else {
      stopAutoScroll()
      return
    }
    let container = currentTimeline.container
    let inset = container.adjustedContentInset
    let minOffsetY = -inset.top
    let maxOffsetY = max(minOffsetY, container.contentSize.height - container.bounds.height + inset.bottom)
    let previousOffsetY = container.contentOffset.y
    let elapsed = CGFloat(link.targetTimestamp - link.timestamp)
    let offsetY = (previousOffsetY + autoScrollSpeed * elapsed).clamped(to: minOffsetY...maxOffsetY)
    let delta = offsetY - previousOffsetY
    guard delta != 0 else {return} // the end of the day is on screen, nothing left to scroll to

    // Once scrolled, the day's limits and the event (scrollViewDidScroll moves it along with the timeline) are
    // `delta` higher on screen. The part of the event under the finger is put back where it is now
    let timeline = currentTimeline.timeline
    let limits = dayLimits(in: timeline)
    let frame = eventView.frame
    var resizedFrame = frame
    switch autoScrollResizeHandleTag {
      case 0: // the top handle stays under the finger, not before 00:00, the bottom keeps its time
        let top = max(frame.minY, limits.top - delta)
        resizedFrame.origin.y = top
        resizedFrame.size.height = frame.maxY - delta - top
      case 1: // the bottom handle stays under the finger, not past 24:00, the top keeps its time
        let bottom = min(frame.maxY, limits.bottom - delta)
        resizedFrame.origin.y = frame.minY - delta
        resizedFrame.size.height = bottom - resizedFrame.minY
      default:
        break
    }
    if autoScrollResizeHandleTag != nil, resizedFrame.height < minimumEventHeight {
      stopAutoScroll() // the event can't get any shorter
      return
    }
    container.setContentOffset(CGPoint(x: container.contentOffset.x, y: offsetY), animated: false)
    if autoScrollResizeHandleTag == nil {
      // the whole event stays under the finger, moved by its center so an ongoing change of width isn't interrupted
      eventView.center.y += delta
      keepWithinDay(eventView, in: timeline)
      accentDateForEditedEventView()
      updateDropPreview(animated: true) // the time under the dragged event changed
    } else {
      eventView.frame = resizedFrame
      accentDateForEditedEventView(eventHeight: autoScrollResizeHandleTag == 1 ? resizedFrame.height : 0)
    }
  }
  
  @objc func handleResizeHandlePanGesture(_ sender: UIPanGestureRecognizer) {
    if let pendingEvent = editedEventView, let tag = sender.view?.tag {
      let location = sender.location(in: self)
      let eventFrame = pendingEvent.frame
      if sender.state == .began {
        grabOffset = CGPoint(x: 0, y: location.y - (tag == 0 ? eventFrame.minY : eventFrame.maxY))
      }
      resizeHandleTag = tag

      // the dragged edge follows the finger, but not before 00:00 or past 24:00
      let dayLimits = currentTimeline.map { self.dayLimits(in: $0.timeline) }
      var suggestedEventFrame = eventFrame
      if tag == 0 { // Top handle
        let top = max(location.y - grabOffset.y, dayLimits?.top ?? -.greatestFiniteMagnitude)
        suggestedEventFrame.origin.y = top
        suggestedEventFrame.size.height = eventFrame.maxY - top
      } else { // Bottom handle
        let bottom = min(location.y - grabOffset.y, dayLimits?.bottom ?? .greatestFiniteMagnitude)
        suggestedEventFrame.size.height = bottom - eventFrame.minY
      }
      let suggestedEventHeight = suggestedEventFrame.size.height
      
      if suggestedEventHeight > minimumEventHeight {
        pendingEvent.frame = suggestedEventFrame
        accentDateForEditedEventView(eventHeight: tag == 0 ? 0 : suggestedEventHeight)
      }
      if sender.state == .changed {
        // a handle held near the top or bottom of the timeline scrolls it, so the event can be extended further
        updateAutoScroll(for: location, resizeHandleTag: tag)
      }
    }

    if sender.state == .ended || sender.state == .cancelled || sender.state == .failed {
      stopAutoScroll()
    }
    if sender.state == .ended {
      commitEditing()
    }
  }

  /// Shortest an event can be made by dragging its resize handles, in points
  private var minimumEventHeight: CGFloat {
    CGFloat(style.minimumEventDurationInMinutesWhileEditing) * style.verticalDiff / 60
  }

  private func accentDateForEditedEventView(eventHeight: CGFloat = 0) {
    if let currentTimeline = currentTimeline {
      let timeline = currentTimeline.timeline
      let converted = timeline.convert(CGPoint.zero, from: editedEventView)
      let date = timeline.yToDate(converted.y + eventHeight)
      timeline.accentedDate = date
      timeline.setNeedsDisplay()
    }
  }

  private func commitEditing() {
    if let currentTimeline = currentTimeline {
      let timeline = currentTimeline.timeline
      timeline.accentedDate = nil
      timeline.setNeedsDisplay() // the accented time is drawn by the timeline, not by the pager

      // TODO: Animate cancellation

      if let editedEventView = editedEventView,
        let descriptor = editedEventView.descriptor {
        update(descriptor: descriptor, with: editedEventView)
        
        let ytd = yToDate(y: editedEventView.frame.origin.y,
                          timeline: timeline)
        var snapped = timeline.eventEditingSnappingBehavior.nearestDate(to: ytd)

        // where the event is dropped, used to find the events it will share the timeline's width with
        let duration = (descriptor.editedEvent ?? descriptor).dateInterval.duration
        var snappedEnd = snapped.addingTimeInterval(duration)
        if resizeHandleTag == 0 {
          snappedEnd = descriptor.dateInterval.end
        } else if resizeHandleTag == 1 {
          let bottomHandleYTD = yToDate(y: editedEventView.frame.origin.y + editedEventView.frame.size.height,
                                        timeline: timeline)
          snappedEnd = timeline.eventEditingSnappingBehavior.nearestDate(to: bottomHandleYTD)
        }

        // the event was kept within the day while dragged, but snapping to the nearest quarter of an hour can still
        // push it just past midnight (e.g. a moved event lasting 50 minutes): it ends at 24:00 at the latest instead
        let dayStart = timeline.date
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        if snappedEnd > dayEnd && resizeHandleTag != 0 {
          if resizeHandleTag == nil {
            snapped = snapped.addingTimeInterval(dayEnd.timeIntervalSince(snappedEnd))
          }
          snappedEnd = dayEnd
        }
        if snapped < dayStart && resizeHandleTag != 1 {
          if resizeHandleTag == nil {
            snappedEnd = dayStart.addingTimeInterval(duration)
          }
          snapped = dayStart
        }

        var eventFrame = editedEventView.frame
        eventFrame.origin.y = convert(CGPoint(x: 0, y: timeline.dateToY(snapped)), from: timeline).y
        eventFrame.size.height = timeline.dateToY(snappedEnd) - timeline.dateToY(snapped)

        // like Apple Calendar, the event snaps into its column among the events happening at the same time:
        // the drop preview lays the timeline out as it will be, the event lands on its grey box.
        // When it was dragged sideways, it goes into the column under the finger and the others make room for it
        if snappedEnd > snapped {
          updateDropPreview(interval: DateInterval(start: snapped, end: snappedEnd), animated: true)
        }
        let previewedEvent = descriptor.editedEvent ?? descriptor
        let concurrentEvents = timeline.dropPreviewEvents
        if resizeHandleTag == nil, isMovingSideways, concurrentEvents.count > 1 {
          for (order, event) in concurrentEvents.enumerated() {
            event.columnOrder = order
          }
          descriptor.columnOrder = previewedEvent.columnOrder
        }
        if dropPreviewTimeline === timeline, let previewFrame = timeline.dropPreviewFrame {
          let frame = convert(previewFrame, from: timeline)
          eventFrame.origin.x = frame.minX
          eventFrame.size.width = frame.width
        } else {
          let column = horizontalFrame(ofEditedCopyOf: descriptor, in: timeline)
          eventFrame.origin.x = column.minX
          eventFrame.size.width = column.width
        }

        func animateEventSnap() {
          editedEventView.frame = eventFrame
          editedEventView.layoutIfNeeded()
        }

        func completionHandler(_ completion: Bool) {
          // the snapped times themselves rather than times read back from the frame, which can come out a minute
          // short of them (e.g. 23:59 instead of 24:00) once the scroll offset is a fraction of a point
          if snappedEnd > snapped {
            descriptor.dateInterval = DateInterval(start: snapped, end: snappedEnd)
          } else {
            update(descriptor: descriptor, with: editedEventView)
          }
          // the timeline is laid out again with the dropped event on the next layout pass, without the preview
          clearDropPreview(animated: false)
          delegate?.timelinePager(timelinePager: self, didUpdate: descriptor)
        }

        UIView.animate(withDuration: 0.35,
                       delay: 0,
                       usingSpringWithDamping: 0.85,
                       initialSpringVelocity: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction],
                       animations: animateEventSnap,
                       completion: completionHandler(_:))
          
      }
        
       
        
      resizeHandleTag = nil
      grabOffset = .zero
      moveLocation = nil
      isMovingSideways = false
    print ("editing finished")
    }
  }

  /// Ends editing mode
  public func endEventEditing() {
    stopDayChange()
    stopAutoScroll()
    grabOffset = .zero
    moveLocation = nil
    isMovingSideways = false
    isMovingEditedEvent = false
    clearDropPreview(animated: true)
    editedEventView?.eventResizeHandles.forEach{$0.panGestureRecognizer.removeTarget(self, action: nil)}
    editedEventView?.removeFromSuperview()
    editedEventView = nil
    editedEvent = nil
    updateHiddenEvent()
    // create(event:) accents the edited event's start time, it must not stay once editing is over
    if let timeline = currentTimeline?.timeline {
      timeline.accentedDate = nil
      timeline.setNeedsDisplay()
    }
  }

  @objc private func timelineDidLongPress(_ sender: UILongPressGestureRecognizer) {
    if sender.state == .ended {
      commitEditing()
    }
  }
  
  private func yToDate(y: CGFloat, timeline: TimelineView) -> Date {
    let point = CGPoint(x: 0, y: y)
    let converted = convert(point, to: timeline).y
    let date = timeline.yToDate(converted)
    return date
  }

  private func update(descriptor: EventDescriptor, with eventView: EventView) {
    if let currentTimeline = currentTimeline {
      let timeline = currentTimeline.timeline
      let eventFrame = eventView.frame
      let converted = convert(eventFrame, to: timeline)
      let beginningY = converted.minY
      let endY = converted.maxY
      let beginning = timeline.yToDate(beginningY)
      let end = timeline.yToDate(endY)
      descriptor.dateInterval = DateInterval(start: beginning, end: end)
    }
  }

  // MARK: DayViewStateUpdating

  public func move(from oldDate: Date, to newDate: Date) {
    let oldDate = oldDate.dateOnly(calendar: calendar)
    let newDate = newDate.dateOnly(calendar: calendar)
    let newController = configureTimelineController(date: newDate)
    // an edited event is being moved to another day: keep the same scroll position so the time under it doesn't change
    let isMovingEditedEvent = editedEventView != nil
    if isMovingEditedEvent {
      newController.pendingContentOffset = currentTimeline?.container.contentOffset
    }

    delegate?.timelinePager(timelinePager: self, willMoveTo: newDate)

    func completionHandler(_ completion: Bool) {
      DispatchQueue.main.async { [self] in
        // Fix for the UIPageViewController issue: https://stackoverflow.com/questions/12939280/uipageviewcontroller-navigates-to-wrong-page-with-scroll-transition-style
        
        let leftToRight = UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .leftToRight
        let direction: UIPageViewController.NavigationDirection = leftToRight ? .reverse : .forward
        
        self.pagingViewController.setViewControllers([newController],
                                                      direction: direction,
                                                      animated: false,
                                                      completion: nil)
              
        self.pagingViewController.viewControllers?.first?.view.setNeedsLayout()
        if !isMovingEditedEvent {
          self.scrollToFirstEventIfNeeded(animated: true)
        }
        self.delegate?.timelinePager(timelinePager: self, didMoveTo: newDate)
      }
    }

    if newDate < oldDate {
      let leftToRight = UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .leftToRight
      let direction: UIPageViewController.NavigationDirection = leftToRight ? .reverse : .forward
      pagingViewController.setViewControllers([newController],
                                              direction: direction,
                                              animated: true,
                                              completion: completionHandler(_:))
    } else if newDate > oldDate {
      let leftToRight = UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .leftToRight
      let direction: UIPageViewController.NavigationDirection = leftToRight ? .forward : .reverse
      pagingViewController.setViewControllers([newController],
                                              direction: direction,
                                              animated: true,
                                              completion: completionHandler(_:))
    }
  }

  // MARK: UIPageViewControllerDataSource

  public func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
    guard let containerController = viewController as? TimelineContainerController  else {return nil}
    let previousDate = calendar.date(byAdding: .day, value: -1, to: containerController.timeline.date)!
    let timelineContainerController = configureTimelineController(date: previousDate)
    let offset = (pageViewController.viewControllers?.first as? TimelineContainerController)?.container.contentOffset
    timelineContainerController.pendingContentOffset = offset
    return timelineContainerController
  }

  public func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
    guard let containerController = viewController as? TimelineContainerController  else {return nil}
    let nextDate = calendar.date(byAdding: .day, value: 1, to: containerController.timeline.date)!
    let timelineContainerController = configureTimelineController(date: nextDate)
    let offset = (pageViewController.viewControllers?.first as? TimelineContainerController)?.container.contentOffset
    timelineContainerController.pendingContentOffset = offset
    return timelineContainerController
  }

  // MARK: UIPageViewControllerDelegate

  public func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
    guard completed else {
      delegate?.timelinePagerDidTransitionCancel(timelinePager: self)
      return
    }
    if let timelineContainerController = pageViewController.viewControllers?.first as? TimelineContainerController {
      let selectedDate = timelineContainerController.timeline.date
      delegate?.timelinePager(timelinePager: self, willMoveTo: selectedDate)
      state?.client(client: self, didMoveTo: selectedDate)
      scrollToFirstEventIfNeeded(animated: true)
      delegate?.timelinePager(timelinePager: self, didMoveTo: selectedDate)
    }
  }
  
  public func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
    delegate?.timelinePagerDidBeginDragging(timelinePager: self)
  }

  // MARK: TimelineViewDelegate
  
  public func timelineView(_ timelineView: TimelineView, didTapAt date: Date) {
    delegate?.timelinePager(timelinePager: self, didTapTimelineAt: date)
  }
  
  public func timelineView(_ timelineView: TimelineView, didLongPressAt date: Date) {
    delegate?.timelinePager(timelinePager: self, didLongPressTimelineAt: date)
  }
  
  public func timelineView(_ timelineView: TimelineView, didTap event: EventView) {
    delegate?.timelinePagerDidSelectEventView(event)
  }
  
  public func timelineView(_ timelineView: TimelineView, didLongPress event: EventView) {
    delegate?.timelinePagerDidLongPressEventView(event)
  }
}
