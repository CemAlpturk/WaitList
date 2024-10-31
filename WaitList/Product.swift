//
//  Product.swift
//  WaitList
//
//  Created by Cem Alptürk on 2024-10-30.
//

import Foundation

struct Product: Identifiable, Codable {
    let id: UUID
    let name: String
    let deadline: Date

    func daysLeft() -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.startOfDay(for: deadline)
        let components = calendar.dateComponents([.day], from: start, to: end)
        return components.day ?? 0
    }

    var isActive: Bool {
        return daysLeft() > 0
    }
}
