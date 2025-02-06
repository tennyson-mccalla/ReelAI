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
    print("AppDelegate: Configuring Firebase") // Debug print
    FirebaseApp.configure()
    print("AppDelegate: Firebase configured") // Debug print
    return true
  }
}

@main
struct ReelAIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authViewModel = AuthViewModel()

    init() {
        print("ReelAIApp: Initializing")
    }

    var body: some Scene {
        WindowGroup {
            Group {
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

                        ProfileView()
                            .tabItem {
                                Label("Profile", systemImage: "person.circle.fill")
                            }
                    }
                    .tint(.blue)
                    .background(Color.black)
                    .ignoresSafeArea(.all)
                    .onAppear { print("ReelAIApp: Showing TabView") }
                } else {
                    AuthView()
                        .onAppear { print("ReelAIApp: Showing AuthView") }
                }
            }
            .onAppear {
                print("ReelAIApp: Building view hierarchy")
                print("Auth state: \(authViewModel.isAuthenticated)")
            }
        }
        .environmentObject(authViewModel)
    }
}
