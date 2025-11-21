//
//  Item.swift
//  tuzi-fuke
//
//  Created by Mike Liu on 2025/11/21.
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
