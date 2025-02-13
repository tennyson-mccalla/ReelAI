//
//  ReelAIApp.swift
//  ReelAI
//
//  Created by ten dev on 2/3/25.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseDatabase
import os

class AppDelegate: NSObject, UIApplicationDelegate {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "AppDelegate")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        logger.debug("🚀 Starting app initialization")

        // 1. Configure Firebase
        guard configureFirebase() else {
            logger.error("🔴 Failed to configure Firebase")
            return false
        }
        logger.debug("✅ Firebase configured")

        // 2. Initialize auth service which sets up persistence
        _ = FirebaseAuthService.shared
        logger.debug("✅ Auth service initialized")

        // 3. Set up offline capabilities
        Database.database().goOnline()

        // 4. Add state change listener
        setupConnectionStateMonitoring()

        logger.debug("✅ App initialization complete")
        return true
    }

    private func configureFirebase() -> Bool {
        do {
            FirebaseApp.configure()
            return true
        } catch {
            logger.error("🔴 Firebase configuration failed: \(error.localizedDescription)")
            return false
        }
    }

    private func setupConnectionStateMonitoring() {
        Database.database().addServiceStateObserver { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .online:
                self.logger.debug("💚 Firebase connection: Online")
            case .offline:
                self.logger.debug("🔸 Firebase connection: Offline")
            case .restricted:
                self.logger.error("🔴 Firebase connection: Restricted")
            @unknown default:
                self.logger.error("⚠️ Firebase connection: Unknown state")
            }
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        Database.database().goOffline()
        logger.debug("📱 App entered background - Firebase connection closed")
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        Database.database().goOnline()
        logger.debug("📱 App entered foreground - Firebase connection restored")
    }
}

@main
struct ReelAIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authViewModel = AuthViewModel()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReelAI", category: "ReelAIApp")

    init() {
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
                }
            }
            .environmentObject(authViewModel)
        }
    }
}
