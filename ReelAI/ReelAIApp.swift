//
//  ReelAIApp.swift
//  ReelAI
//
//  Created by ten dev on 2/3/25.
//

import SwiftUI
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    // Only configure if it hasn't been configured yet
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }
    return true
  }
}

@main
struct ReelAIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authViewModel = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            if authViewModel.isAuthenticated {
                VideoUploadView()
            } else {
                AuthView()
            }
        }
        .environmentObject(authViewModel)
    }
}
