//
//  BLASTApp.swift
//  BLAST
//
//  Created by Dawid Konopnicki on 01/10/2026.
//

import SwiftUI

@main
struct BLASTApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1000, height: 700)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
