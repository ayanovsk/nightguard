//
//  AccessoryCircularView.swift
//  nightguard Widget Extension
//
//  Created by Dirk Hermanns on 07.04.23.
//  Copyright © 2023 private. All rights reserved.
//

import Foundation
import SwiftUI
import WidgetKit

struct AccessoryCircularView : View {
    
    var entry: NightscoutDataEntry
    
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack {
                var ageInMin = Int(calculateAgeInMinutes(fromDouble: entry.lastBGValues.first?.timestamp ?? Date.now.timeIntervalSinceNow-3600)) ?? -1
                Text("\(getTimeMinusMinutes(minutes: ageInMin))")
                    .foregroundColor(Color.blue)
                
                
         //       Text("\(calculateAgeInMinutes(fromDouble: entry.lastBGValues.first?.timestamp ?? // Date.now.timeIntervalSinceNow-3600))m")
              //      .foregroundColor(Color.blue)
                Text("\("M:" + (entry.lastBGValues.first?.value ?? "??"))")
                    .foregroundColor(Color.blue)
                  //  .foregroundColor(
                    //    Color(UIColorChanger.getBgColor(entry.lastBGValues.first?.value ?? //"999")))
                Text("\(entry.lastBGValues.first?.delta ?? "?")")
                    .foregroundColor(Color.blue)
                   // .foregroundColor(
                  //      Color(UIColorChanger.getDeltaLabelColor(Float(entry.lastBGValues.first?.delta ?? "99") ?? 99.0)))
                    .widgetAccentable(true)
                    .unredacted()
            }
        }
    }
    
}

func getTimeMinusMinutes(minutes: Int) -> String {
    // Get the current date and time
    if minutes < 0 {return "??"}
    let currentDate = Date()
    
    // Subtract the given number of minutes
    let calendar = Calendar.current
    if let newDate = calendar.date(byAdding: .minute, value: -minutes, to: currentDate) {
        
        // Format the new date into "hours:minutes" string
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"  // 12-hour format with AM/PM
        
        let formattedTime = formatter.string(from: newDate)
        return formattedTime
    }
    
    return "??"
}


