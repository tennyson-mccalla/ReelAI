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
                TabView {
                    VideoFeedView()
                        .tabItem {
                            Label("Home", systemImage: "house.fill")
                        }

                    PlaceholderView(feature: "Friends")
                        .tabItem {
                            Label("Friends", systemImage: "person.2.fill")
                        }

                    VideoUploadView()
                        .tabItem {
                            Label("Create", systemImage: "plus.circle.fill")
                        }

                    PlaceholderView(feature: "Messages")
                        .tabItem {
                            Label("Messages", systemImage: "message.fill")
                        }

                    PlaceholderView(feature: "Profile")
                        .tabItem {
                            Label("Profile", systemImage: "person.circle.fill")
                        }
                }
                .tint(.blue)
                .background(Color.black)
                .ignoresSafeArea(.all)
            } else {
                AuthView()
            }
        }
        .environmentObject(authViewModel)
    }
}
