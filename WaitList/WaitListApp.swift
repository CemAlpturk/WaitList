//
//  WaitListApp.swift
//  WaitList
//
//  Created by Cem Alptürk on 2024-10-30.
//

import SwiftUI

@main
struct WaitListApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
