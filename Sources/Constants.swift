//
//  File.swift
//  CalendarKit
//
//  Created by Jonathan Wei on 30.12.22.
//

import Foundation

struct K {
    static let ToDoCellIdentifier = "ToDoCell"
    static let ToDoCellNibName = "ToDoTableViewCell"
    static let SettingsCellIdentifier = "SettingsCell"
    static let SettingsCellNibName = "SettingsStaticCellTableViewCell"
    static let CalendarCellIdentifier = "CalendarCell"
    static let CalendarCellNibName = "CalendarViewCell"
    static let CalendarViewTotalHeight = 850
    
    struct TagColors { //tag corresponds to the empty tick boxes as well as the tag color
        static let Purple = "Purple"
        static let Blue = "Blue"
        static let Green = "Green"
        static let Red = "Red"
        static let Default = Blue //tag of new tasks and events
    }

    struct TickEmpty { //corresponds to the empty tick boxes
        static let Purple = "PurpleTick"
        static let Blue = "BlueTick"
        static let Green = "GreenTick"
        static let Red = "RedTick"
    }
    
    struct TickFilled { //corresponds to the filled tick boxes
        static let Purple = "PurpleTickFilled"
        static let Blue = "BlueTickFilled"
        static let Green = "GreenTickFilled"
        static let Red = "RedTickFilled"
    }
    //tag colors use Apple's system colors (light appearance), the tick and circle images use the same values
    struct Colors {
        static let lightBlue = 0xC0E6FF
        static let blue = 0x007AFF //systemBlue
        static let lightPurple = 0xEAC9F7
        static let purple = 0xAF52DE //systemPurple
        static let lightRed = 0xFFC5B8
        static let red = 0xFF3B30 //systemRed
        static let green = 0x34C759 //systemGreen
        static let lightGrey = 0xC7C7CC //systemGray3, events imported from Apple Calendar
    }
}

