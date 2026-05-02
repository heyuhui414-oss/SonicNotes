//
//  SonicNotesApp.swift
//  SonicNotes
//
//  Created by 何宇晖 on 2026/5/2.
//

import SwiftUI
import SwiftData
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .portrait
    }
}

@main

struct SonicNotesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {

        WindowGroup {

            ContentView()
                .preferredColorScheme(.light)

        }

    }

}
