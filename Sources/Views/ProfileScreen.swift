import SwiftUI

/// 我的页：用户信息、观看历史、管理后台、退出登录（对应 ProfileFragment）
struct ProfileScreen: View {
    var onOpenPlayer: (PlaybackRequest) -> Void

    @EnvironmentObject private var appState: AppState
    @State private var showHistory = false
    @State private var showAdmin = false
    @State private var showLogoutConfirm = false
    @State private var showServerSheet = false

    private var user: User? { appState.user }

    /// 当前安装包版本号（用于确认装的是哪一版）
    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(v)(\(b))"
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    profileHeader
                    menuSection
                    logoutButton
                    footer
                }
                .padding(.bottom, tabBottomInset() + 16)
            }
        }
        .sheet(isPresented: $showHistory) {
            HistoryScreen(onOpenPlayer: { req in
                showHistory = false
                onOpenPlayer(req)
            })
        }
        .sheet(isPresented: $showAdmin) {
            AdminScreen()
        }
        .sheet(isPresented: $showServerSheet) {
            ServerInfoSheet(server: ApiClient.shared.baseURL)
        }
        .confirmationDialog("退出登录后需要重新输入账号密码", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                appState.logout()
            }
            Button("取消", role: .cancel) {}
        }
        .task {
            if appState.user == nil { await appState.refreshUser() }
        }
    }

    private var profileHeader: some View {
        HStack(spacing: 16) {
            AvatarView(name: user?.displayName ?? "轻", size: 62)
                .overlay(Circle().stroke(Theme.primary.opacity(0.5), lineWidth: 1))

            VStack(alignment: .leading, spacing: 5) {
                Text(user?.displayName ?? "未登录")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    BadgeLabel(text: user?.roleText ?? "用户")
                    if let name = user?.username, !name.isEmpty {
                        Text("账号：\(name)")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 20)
    }

    private var menuSection: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.divider).frame(height: 0.6)

            menuRow(icon: "clock.arrow.circlepath", title: "观看历史", tint: Theme.primary) {
                showHistory = true
            }
            divider
            menuRow(icon: "server.rack", title: "服务器", tint: Theme.accent,
                    detail: currentServerText) {
                showServerSheet = true
            }
            divider
            menuRow(icon: "square.grid.2x2", title: "管理后台", tint: Theme.primary) {
                showAdmin = true
            }
            divider
            menuRow(icon: "info.circle", title: "关于项目", tint: Theme.textSecondary,
                    detail: appVersion) {
                toast("月半追剧 v\(appVersion) · 后端 1.1.5")
            }
            divider
        }
    }

    private var currentServerText: String {
        ApiClient.shared.baseURL
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func menuRow(icon: String, title: String, tint: Color, detail: String? = nil,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(tint)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.12)))
                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                if let detail = detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.textSecondary.opacity(0.75))
            }
            .padding(.horizontal, 20)
            .frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(height: 0.6)
            .padding(.leading, 62)
    }

    private var logoutButton: some View {
        Button {
            showLogoutConfirm = true
        } label: {
            Text("退出登录")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.danger)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.danger.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.danger.opacity(0.28), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 26)
    }

    private var footer: some View {
        Text("月半追剧 · 连接飞牛 NAS 私人影库")
            .font(.system(size: 11))
            .foregroundColor(Theme.textSecondary.opacity(0.65))
            .padding(.top, 26)
    }

    private func tabBottomInset() -> CGFloat {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let bottom = scene?.windows.first?.safeAreaInsets.bottom ?? 34
        return bottom + 49
    }
}

/// 服务器信息弹窗：可切换内外网并立即生效
struct ServerInfoSheet: View {
    var server: String
    @Environment(\.dismiss) private var dismiss
    @State private var input: String = ""
    @State private var detecting = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text("服务器地址")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)

                TextField("http://192.168.0.138:8092", text: $input)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .font(.system(size: 15))
                    .foregroundColor(Theme.textPrimary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))

                HStack(spacing: 10) {
                    Button {
                        Task {
                            detecting = true
                            let best = await ApiClient.shared.detectBestBase()
                            detecting = false
                            if let best = best {
                                input = best
                                toast("已探测到可用服务器")
                            } else {
                                toast("未探测到可用服务器")
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if detecting { ProgressView().tint(Theme.primary).scaleEffect(0.7) }
                            Text(detecting ? "探测中…" : "自动探测")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(Theme.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.primary.opacity(0.12)))
                    }
                    .disabled(detecting)

                    Button {
                        ApiClient.shared.baseURL = input
                        Prefs.rememberServer(ApiClient.shared.baseURL)
                        toast("已切换到 \(ApiClient.shared.baseURL)")
                        dismiss()
                    } label: {
                        Text("保存")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.primary))
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .onAppear {
            input = server.hasSuffix("/") ? String(server.dropLast()) : server
        }
    }
}
