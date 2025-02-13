import Foundation

enum VideoAction {
    case delete
    case restore
    case updatePrivacy(isPrivate: Bool)
    case updateCaption(String)
}
