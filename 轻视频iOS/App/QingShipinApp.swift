import SwiftUI

@main
struct QingShipinApp: App {
    @StateObject private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(auth)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var auth: AuthStore
    var body: some View {
        if auth.loggedIn {
            MainTabView()
        } else {
            LoginView()
        }
    }
}
