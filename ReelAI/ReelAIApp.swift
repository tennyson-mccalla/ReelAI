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
    private var connectedRef: DatabaseReference?
    private var stateObserver: NSObjectProtocol?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        logger.debug("🚀 Starting app initialization")

        // 1. Configure Firebase
        configureFirebase()
        logger.debug("✅ Firebase configured")

        // 2. Initialize auth service which sets up persistence
        _ = FirebaseAuthService.shared
        logger.debug("✅ Auth service initialized")

        // 3. Set up offline capabilities and monitoring
        setupConnectionHandling()

        logger.debug("✅ App initialization complete")
        return true
    }

    private func configureFirebase() {
        FirebaseApp.configure()
    }

    private func setupConnectionHandling() {
        // Set up notification observers for app state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        // Initial online state
        Database.database().goOnline()

        // Monitor connection state
        setupConnectionStateMonitoring()
    }

    private func setupConnectionStateMonitoring() {
        // Get a reference to the special .info/connected path
        connectedRef = Database.database()
            .reference(withPath: ".info/connected")

        // Observe connection state changes
        connectedRef?.observe(.value) { [weak self] snapshot in
            guard let self = self,
                  let connected = snapshot.value as? Bool else { return }

            if connected {
                self.logger.debug("💚 Firebase connection: Online")
                // Ensure critical paths are resynced when coming online
                FirebaseAuthService.shared.ensureCriticalPathsSync()
            } else {
                self.logger.debug("🔸 Firebase connection: Offline")
            }
        }
    }

    @objc private func handleAppDidEnterBackground() {
        logger.debug("📱 App entered background")
        Database.database().goOffline()
        logger.debug("📱 Firebase connection closed")
    }

    @objc private func handleAppWillEnterForeground() {
        logger.debug("📱 App entering foreground")
        Database.database().goOnline()
        logger.debug("📱 Firebase connection restored")
    }

    deinit {
        // Clean up observers
        connectedRef?.removeAllObservers()
        NotificationCenter.default.removeObserver(self)
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
