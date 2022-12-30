//
//  File.swift
//  CalendarKit
//
//  Created by Jonathan Wei on 30.12.22.
//

import Foundation

func tagToTickImage(tagName :String, isDone: Bool) -> String {
    if isDone == false {
        switch tagName {
            case K.TagColors.Blue:
                return K.TickEmpty.Blue
            case K.TagColors.Green:
                return K.TickEmpty.Green
            case K.TagColors.Purple:
                return K.TickEmpty.Purple
            case K.TagCoCClors.Red:
                return K.TickEmpty.Red
            case K.TagColors.Grey:
                return K.TickEmpty.Grey
            default:
                return K.TickEmpty.Grey
        }
        } else {
            switch tagName {
                case K.TagColors.Blue:
                    return K.TickFilled.Blue
                case K.TagColors.Green:
                    return K.TickFilled.Green
                case K.TagColors.Purple:
                    return K.TickFilled.Purple
                case K.TagColors.Red:
                    return K.TickFilled.Red
                case K.TagColors.Grey:
                    return K.TickFilled.Grey
                default:
                    return K.TickFilled.Grey
            }
        }
}

//convert color tag to hex value
func tagToHex(tagName: String) -> Int {
    switch tagName {
        case K.TagColors.Blue:
            return K.Colors.blue
        case K.TagColors.Green:
            return K.Colors.green
        case K.TagColors.Purple:
            return K.Colors.purple
        case K.TagColors.Red:
            return K.Colors.red
        case K.TagColors.Grey:
            return K.Colors.grey
        default:
            return K.Colors.grey
    }
}

