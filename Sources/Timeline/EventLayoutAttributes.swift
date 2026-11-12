import CoreGraphics

public final class EventLayoutAttributes {
  public let descriptor: EventDescriptor
  public var frame = CGRect.zero
  /// 0 for an event laid out on the timeline itself, 1 for an event drawn over a longer event enclosing it, and so on
  public var nestingLevel = 0

  public init(_ descriptor: EventDescriptor) {
    self.descriptor = descriptor
  }
}
