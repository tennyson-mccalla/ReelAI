//
//  ReelAIApp.swift
//  ReelAI
//
//  Created by ten dev on 2/3/25.
//

import SwiftUI
import FirebaseCore
import FirebaseDatabase
import os

class AppDelegate: NSObject, UIApplicationDelegate {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "AppDelegate")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        logger.debug("🔧 Configuring Firebase")
        FirebaseApp.configure()

        // Disable persistence completely
        Database.database().isPersistenceEnabled = false

        logger.debug("✅ Firebase configured with persistence disabled")
        return true
    }
}

@main
struct ReelAIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authViewModel = AuthViewModel()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "ReelAIApp")

    init() {
        logger.debug("🚀 Initializing app")
        // Configure tab bar appearance
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = .black

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if authViewModel.isAuthenticated {
                        TabView {
                            NavigationStack {
                                VideoFeedView()
                            }
                            .tabItem {
                                Label("Home", systemImage: "house.fill")
                            }

                            NavigationStack {
                                Text("Friends Coming Soon")
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color.black)
                            }
                            .tabItem {
                                Label("Friends", systemImage: "person.2.fill")
                            }

                            NavigationStack {
                                VideoUploadView()
                            }
                            .tabItem {
                                Label("Create", systemImage: "plus.circle.fill")
                            }

                            NavigationStack {
                                Text("Messages Coming Soon")
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color.black)
                            }
                            .tabItem {
                                Label("Messages", systemImage: "message.fill")
                            }

                            NavigationStack {
                                ProfileView()
                            }
                            .tabItem {
                                Label("Profile", systemImage: "person.circle.fill")
                            }
                        }
                        .tint(.blue)
                    } else {
                        AuthView()
                    }
                }
                .onAppear {
                    logger.debug("📱 Building view hierarchy")
                    logger.debug("🔑 Auth state: \(authViewModel.isAuthenticated)")
                }
            }
            .environmentObject(authViewModel)
        }
    }
}
