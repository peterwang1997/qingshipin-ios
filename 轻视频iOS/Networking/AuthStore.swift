import Foundation
import Combine

/// 登录态管理（token 持久化到 UserDefaults）
final class AuthStore: ObservableObject {
    @Published var loggedIn: Bool
    @Published var username: String
    @Published var server: String

    init() {
        let token = UserDefaults.standard.string(forKey: "qs_token") ?? ""
        self.loggedIn = !token.isEmpty
        self.username = UserDefaults.standard.string(forKey: "qs_username") ?? ""
        self.server = UserDefaults.standard.string(forKey: "qs_server") ?? ServerEnv.internalNet.rawValue
        if !token.isEmpty {
            ApiClient.shared.token = token
            ApiClient.shared.baseUrl = self.server
        }
    }

    func save(token: String, username: String, server: String) {
        UserDefaults.standard.set(token, forKey: "qs_token")
        UserDefaults.standard.set(username, forKey: "qs_username")
        UserDefaults.standard.set(server, forKey: "qs_server")
        ApiClient.shared.token = token
        ApiClient.shared.baseUrl = server
        self.loggedIn = true
        self.username = username
        self.server = server
    }

    func logout() {
        UserDefaults.standard.removeObject(forKey: "qs_token")
        UserDefaults.standard.removeObject(forKey: "qs_username")
        ApiClient.shared.token = ""
        self.loggedIn = false
    }
}
