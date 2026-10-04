//
//  File.swift
//  CalendarKit
//
//  Created by Jonathan Wei on 30.12.22.
//

import UIKit

//unknown tags fall back to blue, the default tag
func tagToTickImage(tagName :String, isDone: Bool) -> String {
    if isDone == false {
        switch tagName {
            case K.TagColors.Green:
                return K.TickEmpty.Green
            case K.TagColors.Purple:
                return K.TickEmpty.Purple
            case K.TagColors.Red:
                return K.TickEmpty.Red
            default:
                return K.TickEmpty.Blue
        }
        } else {
            switch tagName {
                case K.TagColors.Green:
                    return K.TickFilled.Green
                case K.TagColors.Purple:
                    return K.TickFilled.Purple
                case K.TagColors.Red:
                    return K.TickFilled.Red
                default:
                    return K.TickFilled.Blue
            }
        }
}

//convert color tag to hex value
func tagToHex(tagName: String) -> Int {
    switch tagName {
        case K.TagColors.Green:
            return K.Colors.green
        case K.TagColors.Purple:
            return K.Colors.purple
        case K.TagColors.Red:
            return K.Colors.red
        default:
            return K.Colors.blue
    }
}


//convert system color to Tick image
func colorToTickImage(color: UIColor, isDone: Bool) -> String {
    print("in colorToTickImage")
    if isDone == false {
        switch color {
        case .systemGreen:
            return K.TickEmpty.Green
        case .systemPurple:
            return K.TickEmpty.Purple
        case .systemRed:
            return K.TickEmpty.Red
        default:
            return K.TickEmpty.Blue
        }
    } else {
        switch color {
            case .systemGreen:
                    return K.TickFilled.Green
                case .systemPurple:
                    return K.TickFilled.Purple
                case .systemRed:
                    return K.TickFilled.Red
                default:
                    return K.TickFilled.Blue
        }
    }
}

