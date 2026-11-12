import SwiftUI

/// 登录页：服务器地址 + 用户名 + 密码，JWT 鉴权（对应安卓 LoginActivity）
struct LoginScreen: View {
    @EnvironmentObject private var appState: AppState

    @State private var server: String = ApiClient.shared.baseURL
    @State private var username: String = Prefs.lastUsername
    @State private var password: String = ""
    @State private var loading = false
    @State private var errorText: String?
    @State private var detecting = false
    @FocusState private var focused: Field?

    private enum Field { case server, username, password }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    form
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .onTapGesture { focused = nil }
        .onChange(of: appState.serverURL) { newValue in
            guard !newValue.isEmpty else { return }
            server = trimmedServer(newValue)
        }
    }

    private func trimmedServer(_ s: String) -> String {
        var v = s
        if v.hasSuffix("/") { v.removeLast() }
        return v
    }

    // MARK: - 头部

    private var header: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Theme.primary.opacity(0.12))
                    .frame(width: 128, height: 128)
                    .blur(radius: 6)
                Image(systemName: "play.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .foregroundStyle(
                        LinearGradient(colors: [Theme.primary, Theme.primary.opacity(0.7)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
            .padding(.top, Screen.isCompactHeight ? 44 : 84)

            Text("月半追剧")
                .font(.system(size: 27, weight: .bold))
                .foregroundColor(Theme.textPrimary)
                .padding(.top, 8)

            Text("沉浸式短视频体验")
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 表单

    private var form: some View {
        VStack(spacing: 14) {
            fieldBox(icon: "server.rack", title: "服务器地址（内网 192.168.0.138 / 外网 wym.peterw.top）") {
                HStack(spacing: 8) {
                    TextField("http://192.168.0.138:8092", text: $server)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .focused($focused, equals: .server)
                        .foregroundColor(Theme.textPrimary)
                        .font(.system(size: 15))
                    if detecting {
                        LoadingIndicator(size: 18)
                    } else {
                        Button {
                            Task { await autoDetect() }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Theme.primary)
                                .frame(width: 30, height: 30)
                        }
                    }
                }
            }
            .padding(.top, Screen.isCompactHeight ? 26 : 44)

            fieldBox(icon: "person.fill", title: "用户名") {
                TextField("用户名", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .focused($focused, equals: .username)
                    .foregroundColor(Theme.textPrimary)
                    .font(.system(size: 15))
            }

            fieldBox(icon: "lock.fill", title: "密码") {
                SecureField("密码", text: $password)
                    .focused($focused, equals: .password)
                    .foregroundColor(Theme.textPrimary)
                    .font(.system(size: 15))
                    .submitLabel(.go)
                    .onSubmit { doLogin() }
            }

            if let errorText = errorText {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13))
                    Text(errorText)
                        .font(.system(size: 13))
                    Spacer(minLength: 0)
                }
                .foregroundColor(Theme.danger)
                .padding(.top, 2)
            }

            Button(action: doLogin) {
                ZStack {
                    RoundedRectangle(cornerRadius: 26)
                        .fill(LinearGradient(colors: [Theme.primary, Theme.primary.opacity(0.85)],
                                             startPoint: .leading, endPoint: .trailing))
                    if loading {
                        HStack(spacing: 8) {
                            ProgressView().tint(.white).scaleEffect(0.85)
                            Text("登录中…")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    } else {
                        Text("登录")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .frame(height: 52)
            }
            .disabled(loading)
            .opacity(loading ? 0.85 : 1)
            .padding(.top, 12)

            Text("暂未开放注册 · 请使用服务器已有账号")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .padding(.top, 4)
        }
    }

    private func fieldBox<Content: View>(icon: String, title: String,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
            }
            content()
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.primary.opacity(0.55), lineWidth: 0.8)
                )
        }
    }

    // MARK: - 动作

    private func autoDetect() async {
        detecting = true
        defer { detecting = false }
        let result = await ApiClient.shared.detectBestBaseDetailed()
        if let best = result.best {
            server = trimmedServer(best)
            toast("已连接 \(best)")
        } else {
            // 两个地址都不通时，也把这个地址填好，便于用户直接改端口或换域名
            server = trimmedServer(ApiClient.shared.baseURL)
            let detail = result.failures.joined(separator: "；")
            errorText = detail.isEmpty ? "未探测到可用服务器，请手动填写" : "自动探测失败：\(detail)"
        }
    }

    private func doLogin() {
        focused = nil
        let s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = password
        guard !s.isEmpty, !u.isEmpty, !p.isEmpty else {
            errorText = "请填写服务器地址、用户名和密码"
            return
        }
        errorText = nil
        loading = true
        Task {
            defer { loading = false }
            do {
                let resp = try await ApiService.shared.login(server: s, username: u, password: p)
                guard let token = resp.token, !token.isEmpty else {
                    errorText = "登录失败：未返回令牌"
                    return
                }
                ApiClient.shared.token = token
                Prefs.lastUsername = u
                Prefs.rememberServer(ApiClient.shared.baseURL)
                var user = resp.user
                if user == nil { user = try? await ApiService.shared.me() }
                toast("登录成功")
                withAnimation(.easeInOut(duration: 0.25)) {
                    appState.didLogin(user: user)
                }
            } catch {
                errorText = "登录失败：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
            }
        }
    }
}
