import SwiftUI

/// `app/_layout.tsx`.
///
/// The original wraps the tree in a `QueryClientProvider`, a `GestureHandlerRootView` and a
/// `ThemeProvider`, then gates on `hydrated`. SwiftUI needs none of those wrappers, so what
/// survives is the gate itself: nothing renders until the Keychain read finishes, because a
/// screen that mounts before `hydrated` would fire an unauthenticated request and bounce the
/// user to `/login` even when a valid token exists.
@main
struct LuckyGlassApp: App {
    @State private var session = LuckySession.shared

    var body: some Scene {
        WindowGroup {
            root
                .tint(LuckyTheme.accent)
                .task {
                    guard !session.hydrated else { return }
                    await session.hydrate()
                }
        }
    }

    @ViewBuilder
    private var root: some View {
        if session.hydrated {
            // `app/_layout.tsx` redirects to `/login` whenever `hydrated && !token`, from any
            // route; swapping the whole tree does the same thing and drops every screen's
            // state, which is what the redirect achieved by unmounting the stack.
            if session.isAuthenticated {
                LuckyRoot()
            } else {
                LoginScreen()
            }
        } else {
            // `<ActivityIndicator />` centred on the app background.
            ZStack {
                LuckyBackdrop()
                ProgressView().controlSize(.large).tint(LuckyTheme.accent)
            }
        }
    }
}
