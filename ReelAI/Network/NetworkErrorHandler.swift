import Foundation

enum NetworkErrorType {
    case connectionLost
    case timeout
    case serverError
    case unauthorized
    case forbidden
    case notFound
    case tooManyRequests
    case serviceUnavailable
    case unknown
}

extension Error {
    var networkErrorType: NetworkErrorType {
        let nsError = self as NSError

        // Network-related error domains
        let networkDomains = [
            NSURLErrorDomain,
            "kCFErrorDomainCFNetwork"
        ]

        // Check domain first
        if networkDomains.contains(nsError.domain) {
            // Specific network error codes
            switch nsError.code {
            case NSURLErrorTimedOut:
                return .timeout
            case NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorNotConnectedToInternet:
                return .connectionLost
            default:
                return .unknown
            }
        }

        // Check HTTP response errors
        if let httpResponse = nsError.userInfo["NSHTTPURLResponse"] as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 401: return .unauthorized
            case 403: return .forbidden
            case 404: return .notFound
            case 429: return .tooManyRequests
            case 500...599: return .serviceUnavailable
            default: return .unknown
            }
        }

        return .unknown
    }

    var isRetryableNetworkError: Bool {
        switch networkErrorType {
        case .connectionLost,
             .timeout,
             .serviceUnavailable,
             .tooManyRequests:
            return true
        case .serverError,
             .unauthorized,
             .forbidden,
             .notFound,
             .unknown:
            return false
        }
    }
}

struct NetworkErrorHandler {
    static func handle(_ error: Error,
                       retryAction: (() -> Void)? = nil,
                       fallbackAction: (() -> Void)? = nil) {
        let errorType = error.networkErrorType

        // Log the error
        print("🌐 Network Error: \(errorType)")

        switch errorType {
        case .connectionLost:
            // Attempt retry or show offline mode
            retryAction?()
        case .timeout:
            // Retry with exponential backoff
            retryAction?()
        case .unauthorized:
            // Force re-authentication
            fallbackAction?()
        case .forbidden, .notFound:
            // Critical error, require user intervention
            fallbackAction?()
        case .tooManyRequests:
            // Implement rate limiting or wait
            fallbackAction?()
        case .serviceUnavailable:
            // Retry or show maintenance message
            retryAction?()
        case .serverError:
            // Server-side issue, fallback
            fallbackAction?()
        case .unknown:
            // Generic fallback
            fallbackAction?()
        }
    }

    static func shouldRetry(_ error: Error) -> Bool {
        return error.isRetryableNetworkError
    }
}
