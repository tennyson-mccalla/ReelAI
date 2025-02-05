// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ReelAI",
    platforms: [.iOS(.v16)],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "10.19.0")
    ],
    targets: [
        .target(
            name: "ReelAI",
            dependencies: [
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseStorage", package: "firebase-ios-sdk"),
                .product(name: "FirebaseDatabase", package: "firebase-ios-sdk")
            ]
        )
    ]
)
