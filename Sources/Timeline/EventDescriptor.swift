import Foundation
import UIKit

public protocol EventDescriptor: AnyObject {
  var dateInterval: DateInterval {get set}
  var isAllDay: Bool {get}
  var text: String {get}
  var attributedText: NSAttributedString? {get}
  var lineBreakMode: NSLineBreakMode? {get}
  var font : UIFont {get}
  var color: UIColor {get}
    //button modification
    var colorTag: String {get set}
  var textColor: UIColor {get}
  var backgroundColor: UIColor {get}
    //button modification
    var isDone: Bool {get set}
    var id: Int {get set}
  var editedEvent: EventDescriptor? {get set}
  func makeEditable() -> Self
  func commitEditing()
}
