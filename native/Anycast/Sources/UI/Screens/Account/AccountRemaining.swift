import Foundation

/// `GET /api/user`'s `remaining`, read in one place so the Settings account
/// rows, the Membership page and the transcript refusal path agree. Nil when
/// the request fails or answers login-required (callers decide whether that
/// escalates; none of them do).
@MainActor
enum AccountRemaining {

    static func fetch(context: UIContext) async -> Int? {
        #if DEBUG
        if let state = PlusDebug.state { return state.remaining }
        #endif
        guard let result = try? await context.api.getUser(), case .user(let user) = result else {
            return nil
        }
        return user.remaining
    }
}
