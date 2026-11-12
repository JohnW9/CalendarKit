import UIKit

public protocol TimelineViewDelegate: AnyObject {
  func timelineView(_ timelineView: TimelineView, didTapAt date: Date)
  func timelineView(_ timelineView: TimelineView, didLongPressAt date: Date)
  func timelineView(_ timelineView: TimelineView, didTap event: EventView)
  func timelineView(_ timelineView: TimelineView, didLongPress event: EventView)
}

public final class TimelineView: UIView {
  public weak var delegate: TimelineViewDelegate?

  public var date = Date() {
    didSet {
      setNeedsLayout()
    }
  }

  private var currentTime: Date {
    Date()
  }

  private var eventViews = [EventView]()
  public private(set) var regularLayoutAttributes = [EventLayoutAttributes]()
  public private(set) var allDayLayoutAttributes = [EventLayoutAttributes]()
  
  public var layoutAttributes: [EventLayoutAttributes] {
    get {
      allDayLayoutAttributes + regularLayoutAttributes
    }
    set {
      
      // update layout attributes by separating all-day from non-all-day events
      allDayLayoutAttributes.removeAll()
      regularLayoutAttributes.removeAll()
      for anEventLayoutAttribute in newValue {
        let eventDescriptor = anEventLayoutAttribute.descriptor
        if eventDescriptor.isAllDay {
          allDayLayoutAttributes.append(anEventLayoutAttribute)
        } else {
          regularLayoutAttributes.append(anEventLayoutAttribute)
        }
      }
      
      recalculateEventLayout()
      prepareEventViews()
      allDayView.events = allDayLayoutAttributes.map { $0.descriptor }
      allDayView.isHidden = allDayLayoutAttributes.count == 0
      allDayView.scrollToBottom()
      
      setNeedsLayout()
    }
  }
  private var pool = ReusePool<EventView>()

  public var firstEventYPosition: CGFloat? {
    let first = regularLayoutAttributes.sorted{$0.frame.origin.y < $1.frame.origin.y}.first
    guard let firstEvent = first else {return nil}
    let firstEventPosition = firstEvent.frame.origin.y
    let beginningOfDayPosition = dateToY(date)
    return max(firstEventPosition, beginningOfDayPosition)
  }

  private lazy var nowLine: CurrentTimeIndicator = CurrentTimeIndicator()
  
  /// Shows the all-day events. It is not a subview of the timeline: the TimelineContainerController places it
  /// above the scrolling timeline, so it pushes the hours down instead of covering them
  public private(set) lazy var allDayView: AllDayView = {
    let allDayView = AllDayView(frame: CGRect.zero)
    allDayView.translatesAutoresizingMaskIntoConstraints = false
    allDayView.addGestureRecognizer(allDayTapGestureRecognizer)
    allDayView.addGestureRecognizer(allDayLongPressGestureRecognizer)
    return allDayView
  }()

  private lazy var allDayTapGestureRecognizer = UITapGestureRecognizer(target: self,
                                                                       action: #selector(allDayTap(_:)))
  private lazy var allDayLongPressGestureRecognizer = UILongPressGestureRecognizer(target: self,
                                                                                   action: #selector(allDayLongPress(_:)))

  var style = TimelineStyle()
  private var horizontalEventInset: CGFloat = 3

  public var fullHeight: CGFloat {
    style.verticalInset * 2 + style.verticalDiff * 24
  }

  public var calendarWidth: CGFloat {
    bounds.width - style.leadingInset
  }
    
  public private(set) var is24hClock = true {
    didSet {
      setNeedsDisplay()
    }
  }

  public var calendar: Calendar = Calendar.autoupdatingCurrent {
    didSet {
      eventEditingSnappingBehavior.calendar = calendar
      nowLine.calendar = calendar
      regenerateTimeStrings()
      setNeedsLayout()
    }
  }

  public var eventEditingSnappingBehavior: EventEditingSnappingBehavior = SnapTo15MinuteIntervals() {
    didSet {
      eventEditingSnappingBehavior.calendar = calendar
    }
  }

  private var times: [String] {
    is24hClock ? _24hTimes : _12hTimes
  }

  private lazy var _12hTimes: [String] = TimeStringsFactory(calendar).make12hStrings()
  private lazy var _24hTimes: [String] = TimeStringsFactory(calendar).make24hStrings()
  
  private func regenerateTimeStrings() {
    let factory = TimeStringsFactory(calendar)
    _12hTimes = factory.make12hStrings()
    _24hTimes = factory.make24hStrings()
  }
  
  public lazy private(set) var longPressGestureRecognizer = UILongPressGestureRecognizer(target: self,
                                                                                         action: #selector(longPress(_:)))
  
  public lazy private(set) var tapGestureRecognizer = UITapGestureRecognizer(target: self,
                                                                             action: #selector(tap(_:)))

  private var isToday: Bool {
    calendar.isDateInToday(date)
  }
  
  // MARK: - Initialization
  
  public init() {
    super.init(frame: .zero)
    frame.size.height = fullHeight
    configure()
  }

  override public init(frame: CGRect) {
    super.init(frame: frame)
    configure()
  }

  required public init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
    configure()
  }

  private func configure() {
    contentScaleFactor = 1
    layer.contentsScale = 1
    contentMode = .redraw
    backgroundColor = .white
    addSubview(nowLine)
    
    // Add long press gesture recognizer
    addGestureRecognizer(longPressGestureRecognizer)
    addGestureRecognizer(tapGestureRecognizer)
  }
  
  // MARK: - Event Handling
  
  @objc private func longPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
    if (gestureRecognizer.state == .began) {
      // Get timeslot of gesture location
      let pressedLocation = gestureRecognizer.location(in: self)
      if let eventView = findEventView(at: pressedLocation) {
        delegate?.timelineView(self, didLongPress: eventView)
      } else {
        delegate?.timelineView(self, didLongPressAt: yToDate(pressedLocation.y))
      }
    }
  }
  
  @objc private func tap(_ sender: UITapGestureRecognizer) {
    let pressedLocation = sender.location(in: self)
    if let eventView = findEventView(at: pressedLocation) {
      delegate?.timelineView(self, didTap: eventView)
    } else {
      delegate?.timelineView(self, didTapAt: yToDate(pressedLocation.y))
    }
  }
  
  @objc private func allDayTap(_ sender: UITapGestureRecognizer) {
    if let eventView = findAllDayEventView(at: sender.location(in: allDayView)) {
      delegate?.timelineView(self, didTap: eventView)
    }
  }

  @objc private func allDayLongPress(_ sender: UILongPressGestureRecognizer) {
    if sender.state == .began, let eventView = findAllDayEventView(at: sender.location(in: allDayView)) {
      delegate?.timelineView(self, didLongPress: eventView)
    }
  }

  private func findEventView(at point: CGPoint) -> EventView? {
    // an event drawn over a longer one is picked rather than the one below it
    var found: (eventView: EventView, nestingLevel: Int)?
    for (idx, eventView) in eventViews.enumerated() where eventView.frame.contains(point) {
      let nestingLevel = regularLayoutAttributes.indices.contains(idx) ? regularLayoutAttributes[idx].nestingLevel : 0
      if nestingLevel > (found?.nestingLevel ?? -1) {
        found = (eventView, nestingLevel)
      }
    }
    return found?.eventView
  }

  /// - Parameter point: location in the allDayView's coordinates
  private func findAllDayEventView(at point: CGPoint) -> EventView? {
    allDayView.eventViews.first { $0.convert($0.bounds, to: allDayView).contains(point) }
  }
  
  // MARK: - Style

  public func updateStyle(_ newStyle: TimelineStyle) {
    style = newStyle
    allDayView.updateStyle(style.allDayStyle)
    nowLine.updateStyle(style.timeIndicator)
    
    switch style.dateStyle {
      case .twelveHour:
        is24hClock = false
      case .twentyFourHour:
        is24hClock = true
      default:
        is24hClock = calendar.locale?.uses24hClock() ?? Locale.autoupdatingCurrent.uses24hClock()
    }
    
    backgroundColor = style.backgroundColor
    setNeedsDisplay()
  }
  
  // MARK: - Background Pattern

  public var accentedDate: Date?

  /// Event hidden from the timeline, used while its editable copy is being dragged so it doesn't appear twice
  public var hiddenEvent: EventDescriptor? {
    didSet {
      setNeedsLayout()
    }
  }

  // MARK: - Drop Preview

  /// Where a dragged event would be dropped, the timeline is laid out as if it already was there
  private struct DropPreview {
    let event: EventDescriptor
    let interval: DateInterval
    let columnX: CGFloat?
  }
  private var dropPreview: DropPreview?
  /// Frame of the previewed event, computed like `EventLayoutAttributes.frame`
  private var dropPreviewLayoutFrame: CGRect?
  /// Nesting level of the previewed event, see `EventLayoutAttributes.nestingLevel`
  private var dropPreviewNestingLevel = 0
  /// Events sharing the timeline's width with the previewed event, from the first column to the last, including it
  public private(set) var dropPreviewEvents = [EventDescriptor]()

  /// Grey box showing where the dragged event will be dropped
  private lazy var dropPlaceholder: UIView = {
    let view = UIView()
    view.isUserInteractionEnabled = false
    view.backgroundColor = UIColor.systemGray.withAlphaComponent(0.22)
    view.layer.borderColor = UIColor.systemGray.withAlphaComponent(0.45).cgColor
    view.layer.borderWidth = 1
    view.layer.cornerRadius = 10
    view.layer.cornerCurve = .continuous
    view.alpha = 0
    return view
  }()

  /// Frame the dragged event will have once dropped, in the timeline's coordinates, nil when there is no preview
  public var dropPreviewFrame: CGRect? {
    dropPreviewLayoutFrame.map(eventViewFrame(for:))
  }

  /// Lays the timeline out as if `event` was dropped at `interval`: the events happening at the same time make room for it
  /// and a grey box shows its place. `event` doesn't need to be on the timeline (e.g. a new event)
  /// - Parameter columnX: the event goes into the column under this x (in the timeline's coordinates) among the
  ///   concurrent events, nil keeps its `columnOrder`
  public func setDropPreview(for event: EventDescriptor, at interval: DateInterval, columnAt columnX: CGFloat?, animated: Bool) {
    if let preview = dropPreview, preview.event === event, preview.interval == interval, preview.columnX == columnX {
      return
    }
    dropPreview = DropPreview(event: event, interval: interval, columnX: columnX)
    if dropPlaceholder.superview == nil {
      insertSubview(dropPlaceholder, at: 0) // below the events, which are pushed aside around it
    }
    animateLayoutChange(animated: animated) {
      self.dropPlaceholder.alpha = 1
    }
  }

  /// Removes the drop preview, events go back to their own place
  /// - Parameter animated: if false, the timeline is only laid out again on the next layout pass, so new data
  ///   set in the meantime (e.g. the dropped event) is laid out directly
  public func clearDropPreview(animated: Bool) {
    guard dropPreview != nil else {return}
    dropPreview = nil
    dropPreviewLayoutFrame = nil
    dropPreviewEvents = []
    if animated {
      animateLayoutChange(animated: true) {
        self.dropPlaceholder.alpha = 0
      }
    } else {
      dropPlaceholder.alpha = 0
      setNeedsLayout()
    }
  }

  private func animateLayoutChange(animated: Bool, alongside: @escaping () -> Void) {
    let changes = {
      self.setNeedsLayout()
      self.layoutIfNeeded()
      alongside() // after the layout, so a placeholder that just appears is placed without flying in
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

  override public func draw(_ rect: CGRect) {
    super.draw(rect)

    var hourToRemoveIndex = -1

    var accentedHour = -1
    var accentedMinute = -1

    if let accentedDate = accentedDate {
      accentedHour = eventEditingSnappingBehavior.accentedHour(for: accentedDate)
      accentedMinute = eventEditingSnappingBehavior.accentedMinute(for: accentedDate)
    }

    if isToday {
      let minute = component(component: .minute, from: currentTime)
      let hour = component(component: .hour, from: currentTime)
      if minute > 39 {
        hourToRemoveIndex = hour + 1
      } else if minute < 21 {
        hourToRemoveIndex = hour
      }
    }

    let mutableParagraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
    mutableParagraphStyle.lineBreakMode = .byWordWrapping
    mutableParagraphStyle.alignment = .right
    let paragraphStyle = mutableParagraphStyle.copy() as! NSParagraphStyle

    let attributes = [NSAttributedString.Key.paragraphStyle: paragraphStyle,
                      NSAttributedString.Key.foregroundColor: self.style.timeColor,
                      NSAttributedString.Key.font: style.font] as [NSAttributedString.Key : Any]

    let scale = UIScreen.main.scale
    let hourLineHeight = 1 / UIScreen.main.scale

    let center: CGFloat
    if Int(scale) % 2 == 0 {
        center = 1 / (scale * 2)
    } else {
        center = 0
    }
    
    let offset = 0.5 - center
    
    for (hour, time) in times.enumerated() {
        let rightToLeft = UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .rightToLeft
        
        let hourFloat = CGFloat(hour)
        let context = UIGraphicsGetCurrentContext()
        context!.interpolationQuality = .none
        context?.saveGState()
        context?.setStrokeColor(style.separatorColor.cgColor)
        context?.setLineWidth(hourLineHeight)
        let xStart: CGFloat = {
            if rightToLeft {
                return bounds.width - 53
            } else {
                return 53
            }
        }()
        let xEnd: CGFloat = {
            if rightToLeft {
                return 0
            } else {
                return bounds.width
            }
        }()
        let y = style.verticalInset + hourFloat * style.verticalDiff + offset
        context?.beginPath()
        context?.move(to: CGPoint(x: xStart, y: y))
        context?.addLine(to: CGPoint(x: xEnd, y: y))
        context?.strokePath()
        context?.restoreGState()
    
        if hour == hourToRemoveIndex { continue }
    
        let fontSize = style.font.pointSize
        let timeRect: CGRect = {
            var x: CGFloat
            if rightToLeft {
                x = bounds.width - 53
            } else {
                x = 2
            }
            
            return CGRect(x: x,
                          y: hourFloat * style.verticalDiff + style.verticalInset - 7,
                          width: style.leadingInset - 8,
                          height: fontSize + 2)
        }()
    
        let timeString = NSString(string: time)
        timeString.draw(in: timeRect, withAttributes: attributes)
    
        if accentedMinute == 0 {
            continue
        }
    
        if hour == accentedHour {
            
            var x: CGFloat
            if UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .rightToLeft {
                x = bounds.width - (style.leadingInset + 7)
            } else {
                x = 2
            }
            
            let timeRect = CGRect(x: x, y: hourFloat * style.verticalDiff + style.verticalInset - 7     + style.verticalDiff * (CGFloat(accentedMinute) / 60),
                                width: style.leadingInset - 8, height: fontSize + 2)
            
            let timeString = NSString(string: ":\(accentedMinute)")
            
            timeString.draw(in: timeRect, withAttributes: attributes)
        }
    }
  }
  
  // MARK: - Layout

  override public func layoutSubviews() {
    super.layoutSubviews()
    recalculateEventLayout()
    layoutEvents()
    layoutNowLine()
  }

  private func layoutNowLine() {
    if !isToday {
      nowLine.alpha = 0
    } else {
		bringSubviewToFront(nowLine)
      nowLine.alpha = 1
      let size = CGSize(width: bounds.size.width, height: 20)
      let rect = CGRect(origin: CGPoint.zero, size: size)
      nowLine.date = currentTime
      nowLine.frame = rect
      nowLine.center.y = dateToY(currentTime)
    }
  }

  /// Frame of an event view, from the frame computed by the layout
  private func eventViewFrame(for layoutFrame: CGRect) -> CGRect {
    var x: CGFloat
    if UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .rightToLeft {
      x = bounds.width - layoutFrame.minX - layoutFrame.width
    } else {
      x = layoutFrame.minX
    }
    return CGRect(x: x + style.eventHorizontalInset,
                  y: layoutFrame.minY,
                  width: layoutFrame.width - 2 * style.eventHorizontalInset,
                  height: layoutFrame.height - style.eventGap)
  }

  private func layoutDropPlaceholder() {
    guard let frame = dropPreviewFrame else {return}
    if dropPlaceholder.alpha == 0 {
      // it just appears, so it is placed right away instead of flying in from where it was last shown
      UIView.performWithoutAnimation {
        dropPlaceholder.frame = frame
      }
    } else {
      dropPlaceholder.frame = frame
    }
  }

  private func layoutEvents() {
    layoutDropPlaceholder()
    if eventViews.isEmpty { return }

    for (idx, attributes) in regularLayoutAttributes.enumerated() {
      let descriptor = attributes.descriptor
      let eventView = eventViews[idx]
      eventView.frame = eventViewFrame(for: attributes.frame)
      eventView.updateWithDescriptor(event: descriptor)
      // set on every layout, as event views are reused from a pool
      eventView.isHidden = hiddenEvent.map { $0 === descriptor } ?? false
      // an event drawn over another one is opaque, so the two don't blend
      eventView.baseFillColor = attributes.nestingLevel > 0 ? style.backgroundColor : nil
    }

    // events drawn over another one go above it, the most nested ones last
    let deepestNestingLevel = regularLayoutAttributes.map { $0.nestingLevel }.max() ?? 0
    if deepestNestingLevel > 0 {
      for nestingLevel in 1...deepestNestingLevel {
        for (idx, attributes) in regularLayoutAttributes.enumerated() where attributes.nestingLevel == nestingLevel {
          bringSubviewToFront(eventViews[idx])
        }
      }
    }
    // the grey box of a drop over a longer event shows above it, otherwise below the events making room for it
    if dropPreviewNestingLevel > 0 {
      bringSubviewToFront(dropPlaceholder)
    } else if dropPlaceholder.superview != nil {
      sendSubviewToBack(dropPlaceholder)
    }
  }
  
  /// Splits events into groups of concurrent events, which share the width of the timeline.
  /// Each group is ordered from its first column to its last, by `columnOrder` and then by start time
  private func concurrentGroups<Item>(of items: [Item],
                                      interval: (Item) -> DateInterval,
                                      columnOrder: (Item) -> Int) -> [[Item]] {
    let sortedItems = items.sorted { interval($0).start < interval($1).start }

    var groupsOfEvents = [[Item]]()
    var overlappingEvents = [Item]()

    for event in sortedItems {
      if overlappingEvents.isEmpty {
        overlappingEvents.append(event)
        continue
      }

      if style.eventsWillOverlap {
        guard let earliestEvent = overlappingEvents.first.map({ interval($0).start }) else { continue }
        let dateInterval = getDateInterval(date: earliestEvent)
        if interval(event).contains(dateInterval.start) {
          overlappingEvents.append(event)
          continue
        }
      } else {
        // Events only overlap if one starts strictly before another ends;
        // back-to-back events (e.g. 12–13 and 13–14) keep the full width
        let groupEnd = overlappingEvents.map { interval($0).end }.max()!
        if interval(event).start < groupEnd {
          overlappingEvents.append(event)
          continue
        }
      }
      groupsOfEvents.append(overlappingEvents)
      overlappingEvents = [event]
    }

    if !overlappingEvents.isEmpty {
      groupsOfEvents.append(overlappingEvents)
    }

    // the user can rearrange concurrent events, see `columnOrder`
    return groupsOfEvents.map { group in
      group.sorted {
        let order1 = columnOrder($0), order2 = columnOrder($1)
        return order1 != order2 ? order1 < order2 : interval($0).start < interval($1).start
      }
    }
  }

  /// Frame of the view showing `descriptor`, in the timeline's coordinates, nil if it isn't on the timeline
  public func eventViewFrame(of descriptor: EventDescriptor) -> CGRect? {
    regularLayoutAttributes.first { $0.descriptor === descriptor }.map { eventViewFrame(for: $0.frame) }
  }

  // MARK: Events drawn over a longer event

  /// Space between the leading edge of an event and the events drawn over it, which leaves its color stripe visible
  private let nestedEventIndent: CGFloat = 10
  /// Space kept between the text of an event and the top of an event drawn over it
  private let nestedEventTextSpacing: CGFloat = 2
  /// Narrowest an event drawn over another one can be
  private let minimumNestedEventWidth: CGFloat = 44
  /// Used to measure where the text of an event ends, it is never on screen
  private lazy var measuringEventView = EventView()

  /// Bottom of the text and tick box of `descriptor`'s event when shown at `size`, from the top of the event
  private func contentBottom(of descriptor: EventDescriptor, size: CGSize) -> CGFloat {
    measuringEventView.frame = CGRect(origin: .zero, size: size)
    measuringEventView.updateWithDescriptor(event: descriptor)
    return measuringEventView.contentBottom
  }

  private func recalculateEventLayout() {
    typealias Item = (descriptor: EventDescriptor, interval: DateInterval, attributes: EventLayoutAttributes?)
    // only non allDay events need their frames to be set.
    // While previewing a drop, the dragged event is laid out where it would be dropped
    var items: [Item] = regularLayoutAttributes.map { attributes in
      if let preview = dropPreview, attributes.descriptor === preview.event {
        return (attributes.descriptor, preview.interval, attributes)
      }
      return (attributes.descriptor, attributes.descriptor.dateInterval, attributes)
    }
    if let preview = dropPreview, !items.contains(where: { $0.descriptor === preview.event }) {
      items.append((preview.event, preview.interval, nil)) // e.g. a new event, not on the timeline yet
    }

    // An event starting while an earlier one is still going on is drawn over it (its container), instead of sharing the
    // width with it, as long as it leaves the earlier event's text visible. It may end after its container, it then
    // carries on below it in the same column. The preferred container is the latest one to start, then the shortest
    let candidateContainers: [[Int]] = items.indices.map { index in
      let start = items[index].interval.start
      return items.indices
        .filter { other in
          // starting strictly earlier, so an event can never end up within itself
          other != index && items[other].interval.start < start && start < items[other].interval.end
        }
        .sorted { first, second in
          let start1 = items[first].interval.start, start2 = items[second].interval.start
          return start1 != start2 ? start1 > start2 : items[first].interval.duration < items[second].interval.duration
        }
    }
    var rejectedContainers = [Set<Int>](repeating: [], count: items.count)
    var containers: [Int?] = candidateContainers.map { $0.first }

    var frames = [CGRect](repeating: .zero, count: items.count)
    var nestingLevels = [Int](repeating: 0, count: items.count)
    var previewEvents = [EventDescriptor]()
    // end of each event together with the events drawn over it, which may carry on below it
    var spanEnds = items.map { $0.interval.end }
    let rightToLeft = UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .rightToLeft

    /// Lays out the events within `container` (the timeline itself when nil) in columns, then the events within them
    func layOutEvents(in container: Int?, minX: CGFloat, width: CGFloat, nestingLevel: Int) {
      let members = items.indices.filter { containers[$0] == container }
      // an event shares the width with the events overlapping it or the events drawn over it,
      // so these never cover an event next to their container
      let groups = concurrentGroups(of: members,
                                    interval: { DateInterval(start: items[$0].interval.start, end: spanEnds[$0]) },
                                    columnOrder: { items[$0].descriptor.columnOrder })
      for var group in groups {
        if let preview = dropPreview,
           let previewIndex = group.firstIndex(where: { items[$0].descriptor === preview.event }) {
          if let columnX = preview.columnX {
            // the layout is computed left to right, it is mirrored when shown right to left
            let x = rightToLeft ? bounds.width - columnX : columnX
            let column = Int(floor((x - minX) / (width / CGFloat(group.count))))
            let member = group.remove(at: previewIndex)
            group.insert(member, at: column.clamped(to: 0...group.count))
          }
          previewEvents = group.map { items[$0].descriptor }
        }
        let columnWidth = width / CGFloat(group.count)
        for (column, member) in group.enumerated() {
          let startY = dateToY(items[member].interval.start)
          let endY = dateToY(items[member].interval.end)
          frames[member] = CGRect(x: minX + CGFloat(column) * columnWidth, y: startY, width: columnWidth, height: endY - startY)
          nestingLevels[member] = nestingLevel
          layOutEvents(in: member,
                       minX: frames[member].minX + nestedEventIndent,
                       width: columnWidth - nestedEventIndent,
                       nestingLevel: nestingLevel + 1)
        }
      }
    }

    // An event that would hide the text of its container, or be too narrow, is drawn over its next candidate instead,
    // or shares the width with it if there is none left. Containers are only ever rejected, so this always ends
    var measuredContainers = [Int: (size: CGSize, contentBottom: CGFloat)]()
    while true {
      previewEvents = []
      spanEnds = items.map { $0.interval.end }
      // an event starts after its container, so going from the latest start handles it before its container
      for index in items.indices.sorted(by: { items[$0].interval.start > items[$1].interval.start }) {
        if let container = containers[index] {
          spanEnds[container] = max(spanEnds[container], spanEnds[index])
        }
      }
      layOutEvents(in: nil, minX: style.leadingInset, width: calendarWidth, nestingLevel: 0)
      var didChange = false
      for index in items.indices {
        guard let container = containers[index] else { continue }
        let containerSize = eventViewFrame(for: frames[container]).size
        if measuredContainers[container]?.size != containerSize {
          measuredContainers[container] = (containerSize, contentBottom(of: items[container].descriptor, size: containerSize))
        }
        let textBottom = frames[container].minY + (measuredContainers[container]?.contentBottom ?? 0) + nestedEventTextSpacing
        let width = eventViewFrame(for: frames[index]).width
        if frames[index].minY < textBottom || width < minimumNestedEventWidth {
          rejectedContainers[index].insert(container)
          containers[index] = candidateContainers[index].first { !rejectedContainers[index].contains($0) }
          didChange = true
        }
      }
      if !didChange { break }
    }

    dropPreviewLayoutFrame = nil
    dropPreviewNestingLevel = 0
    dropPreviewEvents = previewEvents
    for (index, item) in items.enumerated() {
      item.attributes?.frame = frames[index]
      item.attributes?.nestingLevel = nestingLevels[index]
      if let preview = dropPreview, item.descriptor === preview.event {
        dropPreviewLayoutFrame = frames[index]
        dropPreviewNestingLevel = nestingLevels[index]
      }
    }
  }

  private func prepareEventViews() {
    pool.enqueue(views: eventViews)
    eventViews.removeAll()
    for _ in regularLayoutAttributes {
      let newView = pool.dequeue()
      if newView.superview == nil {
        addSubview(newView)
      }
      eventViews.append(newView)
    }
  }

  public func prepareForReuse() {
    pool.enqueue(views: eventViews)
    eventViews.removeAll()
    setNeedsDisplay()
  }

  // MARK: - Helpers

  public func dateToY(_ date: Date) -> CGFloat {
    let provisionedDate = date.dateOnly(calendar: calendar)
    let timelineDate = self.date.dateOnly(calendar: calendar)
    var dayOffset: CGFloat = 0
    if provisionedDate > timelineDate {
      // Event ending the next day
      dayOffset += 1
    } else if provisionedDate < timelineDate {
      // Event starting the previous day
      dayOffset -= 1
    }
    let fullTimelineHeight = 24 * style.verticalDiff
    let hour = component(component: .hour, from: date)
    let minute = component(component: .minute, from: date)
    let hourY = CGFloat(hour) * style.verticalDiff + style.verticalInset
    let minuteY = CGFloat(minute) * style.verticalDiff / 60
    return hourY + minuteY + fullTimelineHeight * dayOffset
  }

  public func yToDate(_ y: CGFloat) -> Date {
    let timeValue = y - style.verticalInset
    var hour = Int(timeValue / style.verticalDiff)
    let fullHourPoints = CGFloat(hour) * style.verticalDiff
    let minuteDiff = timeValue - fullHourPoints
    let minute = Int(minuteDiff / style.verticalDiff * 60)
    var dayOffset = 0
    if hour > 23 {
      dayOffset += 1
      hour -= 24
    } else if hour < 0 {
      dayOffset -= 1
      hour += 24
    }
    let offsetDate = calendar.date(byAdding: DateComponents(day: dayOffset),
                                   to: date)!
    let newDate = calendar.date(bySettingHour: hour,
                                minute: minute.clamped(to: 0...59),
                                second: 0,
                                of: offsetDate)
    return newDate!
  }

  private func component(component: Calendar.Component, from date: Date) -> Int {
    return calendar.component(component, from: date)
  }
  
  private func getDateInterval(date: Date) -> DateInterval {
    let earliestEventMintues = component(component: .minute, from: date)
    let splitMinuteInterval = style.splitMinuteInterval
    let minute = component(component: .minute, from: date)
    let minuteRange = (minute / splitMinuteInterval) * splitMinuteInterval
    let beginningRange = calendar.date(byAdding: .minute, value: -(earliestEventMintues - minuteRange), to: date)!
    let endRange = calendar.date(byAdding: .minute, value: splitMinuteInterval, to: beginningRange)!
    return DateInterval(start: beginningRange, end: endRange)
  }
}
