import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var username = ""
    @State private var password = ""
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.08, green: 0.09, blue: 0.12),
                                    Color(red: 0.14, green: 0.10, blue: 0.22)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 20) {
                Text("轻视频")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
                Text("服务器：\(auth.server)")
                    .font(.footnote)
                    .foregroundColor(.gray)

                TextField("账号", text: $username)
                    .textInputAutocapitalization(.never)
                    .padding()
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(10)
                    .foregroundColor(.white)

                SecureField("密码", text: $password)
                    .padding()
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(10)
                    .foregroundColor(.white)

                if let error = error {
                    Text(error).font(.footnote).foregroundColor(.red)
                }

                Button(action: doLogin) {
                    Text(loading ? "登录中…" : "登 录")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(loading)
            }
            .padding(24)
        }
        .onAppear {
            ApiClient.shared.detectEnvironment { server in
                auth.server = server
            }
        }
    }

    private func doLogin() {
        guard !username.isEmpty, !password.isEmpty else { return }
        loading = true
        error = nil
        ApiClient.shared.login(username: username, password: password) { result in
            DispatchQueue.main.async {
                loading = false
                switch result {
                case .success(let r):
                    auth.save(token: r.token ?? "", username: username, server: ApiClient.shared.baseUrl)
                case .failure(let e):
                    error = "登录失败：\(e.localizedDescription)"
                }
            }
        }
    }
}
