//
//  Item.swift
//  SonicNotes
//
//  Created by 何宇晖 on 2026/5/2.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
