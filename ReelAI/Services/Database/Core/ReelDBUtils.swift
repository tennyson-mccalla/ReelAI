import Foundation
import FirebaseDatabase
import os

extension ReelDB {
    /// Utility functions for Firebase Realtime Database operations
    enum Utils {
        /// Creates a server timestamp value that is properly typed for Firebase
        static func serverTimestamp() -> [String: Any] {
            return [".sv": "timestamp"]
        }

        /// Converts an Encodable value to a dictionary suitable for Firebase
        static func convertToDict<T: Encodable>(_ value: T) throws -> [String: Any] {
            let data = try JSONEncoder().encode(value)
            let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            return dict
        }

        /// Logs the structure of database data for debugging
        static func debugDataStructure(_ data: [String: Any], logger: Logger, prefix: String = "") {
            logger.debug("🔍 Data Structure:")
            for (key, value) in data {
                if let nestedDict = value as? [String: Any] {
                    logger.debug("\(prefix)[\(key)]")
                    debugDataStructure(nestedDict, logger: logger, prefix: prefix + "  ")
                } else {
                    let valueStr: String = String(describing: value)
                    logger.debug("\(prefix)\(key): \(valueStr)")
                }
            }
        }

        /// Creates a database reference with proper error handling
        static func safeReference(_ path: String, from db: DatabaseReference) -> DatabaseReference {
            // Remove any invalid characters from the path
            let safePath = path.components(separatedBy: "/")
                .map { component in
                    component.replacingOccurrences(of: ".", with: "-")
                        .replacingOccurrences(of: "#", with: "-")
                        .replacingOccurrences(of: "$", with: "-")
                        .replacingOccurrences(of: "[", with: "-")
                        .replacingOccurrences(of: "]", with: "-")
                }
                .joined(separator: "/")

            return db.child(safePath)
        }
    }
}
