import Foundation

extension ReelDB {
    /// Errors that can occur during database operations
    enum Error: LocalizedError {
        case invalidData
        case notAuthenticated
        case offline
        case permissionDenied
        case invalidPath
        case networkError(Swift.Error)
        case encodingError(Swift.Error)
        case decodingError(Swift.Error)

        var errorDescription: String? {
            switch self {
            case .invalidData:
                return "The data structure is invalid or corrupted"
            case .notAuthenticated:
                return "User is not authenticated"
            case .offline:
                return "Device is offline"
            case .permissionDenied:
                return "Permission denied for this operation"
            case .invalidPath:
                return "Invalid database path"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .encodingError(let error):
                return "Failed to encode data: \(error.localizedDescription)"
            case .decodingError(let error):
                return "Failed to decode data: \(error.localizedDescription)"
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .invalidData:
                return "Try refreshing the data or contact support if the issue persists"
            case .notAuthenticated:
                return "Please sign in again"
            case .offline:
                return "Check your internet connection and try again"
            case .permissionDenied:
                return "You don't have permission to perform this action"
            case .invalidPath:
                return "The requested data path is invalid"
            case .networkError:
                return "Check your internet connection and try again"
            case .encodingError:
                return "There was an error preparing the data. Try again or contact support"
            case .decodingError:
                return "There was an error reading the data. Try again or contact support"
            }
        }
    }
}
