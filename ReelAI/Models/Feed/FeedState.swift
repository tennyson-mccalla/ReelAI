import Foundation

struct FeedState {
    var videos: [Video] = []
    var error: String?
    var isLoading = false
    var loadingMessage: String?
    var lastLoadedKey: String?
    var isLoadingMore = false
    var isLoadingBatch = false
}

enum ScrollDirection {
    case forward
    case backward
    case none
}
