import SwiftUI

/// 管理后台：媒体库路径管理 + 用户管理（对应 AdminActivity）
struct AdminScreen: View {
    @Environment(\.dismiss) private var dismiss

    @State private var tab: Int = 0
    @State private var paths: [AdminPath] = []
    @State private var users: [AdminUserRow] = []
    @State private var loadingPaths = true
    @State private var loadingUsers = false
    @State private var errorPaths: String?
    @State private var errorUsers: String?

    @State private var showAddPath = false
    @State private var newName = ""
    @State private var newPath = ""
    @State private var newType = "series"

    @State private var resetTarget: AdminUserRow?
    @State private var newPassword = ""
    @State private var deleteTarget: DeleteTarget?

    private enum DeleteTarget: Identifiable {
        case path(AdminPath)
        case user(AdminUserRow)
        var id: String {
            switch self {
            case let .path(p): return "p-\(p.id)"
            case let .user(u): return "u-\(u.id)"
            }
        }
        var title: String {
            switch self {
            case let .path(p): return "删除媒体库路径"
            case let .user(u): return "删除用户"
            }
        }
        var message: String {
            switch self {
            case let .path(p): return "确定删除「\(p.displayName)」吗？"
            case let .user(u): return "确定删除用户「\(u.username)」吗？"
            }
        }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                NavBar(title: "管理后台", onBack: { dismiss() })
                tabSwitcher
                ZStack {
                    if tab == 0 { pathsTab } else { usersTab }
                }
            }
        }
        .task {
            await loadPaths()
            await loadUsers()
        }
        .sheet(isPresented: $showAddPath) { addPathSheet }
        .sheet(item: $resetTarget) { target in resetPasswordSheet(target) }
        .alert(item: $deleteTarget) { target in
            Alert(title: Text(target.title),
                  message: Text(target.message),
                  primaryButton: .destructive(Text("删除")) {
                      performDelete(target)
                  },
                  secondaryButton: .cancel(Text("取消")))
        }
    }

    private var tabSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(["媒体库", "用户"], id: \.self) { name in
                let idx = name == "媒体库" ? 0 : 1
                Button {
                    tab = idx
                } label: {
                    VStack(spacing: 6) {
                        Text(name)
                            .font(.system(size: 14, weight: tab == idx ? .semibold : .regular))
                            .foregroundColor(tab == idx ? Theme.primary : Theme.textSecondary)
                        Rectangle()
                            .fill(tab == idx ? Theme.primary : Color.clear)
                            .frame(width: 28, height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.divider).frame(height: 0.5)
        }
    }

    // MARK: - 媒体库

    private var pathsTab: some View {
        VStack(spacing: 0) {
            Button {
                newName = ""
                newPath = ""
                newType = "series"
                showAddPath = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text("添加媒体库路径")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(Theme.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.primary.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if loadingPaths && paths.isEmpty {
                LoadingIndicator(size: 32).frame(maxHeight: .infinity)
            } else if paths.isEmpty {
                EmptyStateView(text: errorPaths ?? "暂无媒体库路径")
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(paths) { p in
                            pathCard(p)
                        }
                    }
                    .padding(.bottom, 20)
                }
                .refreshable { await loadPaths() }
            }
        }
    }

    private func pathCard(_ p: AdminPath) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(p.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                BadgeLabel(text: p.typeText)
                if p.scanning {
                    HStack(spacing: 4) {
                        ProgressView().tint(Theme.accent).scaleEffect(0.6).frame(width: 12, height: 12)
                        Text("扫描中")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.accent)
                    }
                }
                Spacer(minLength: 0)
            }

            Text(p.path ?? "")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, 6)

            HStack(spacing: 10) {
                Text("共 \(p.fileCount) 个文件 · 上次扫描 \(shortDate(p.lastScan))")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    Task { await toggleScan(p) }
                } label: {
                    Text(p.scanning ? "停止" : "扫描")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.primary)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.primary.opacity(0.12)))
                }
                .buttonStyle(.plain)

                Button {
                    deleteTarget = .path(p)
                } label: {
                    Text("删除")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.danger)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.danger.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 10)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private func shortDate(_ s: String?) -> String {
        guard let s = s, !s.isEmpty else { return "-" }
        if s.count >= 16 { return String(s.prefix(16)).replacingOccurrences(of: "T", with: " ") }
        return s
    }

    // MARK: - 用户

    private var usersTab: some View {
        Group {
            if loadingUsers && users.isEmpty {
                LoadingIndicator(size: 32).frame(maxHeight: .infinity)
            } else if users.isEmpty {
                EmptyStateView(text: errorUsers ?? "暂无用户")
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(users) { u in
                            userCard(u)
                        }
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 20)
                }
                .refreshable { await loadUsers() }
            }
        }
    }

    private func userCard(_ u: AdminUserRow) -> some View {
        HStack(spacing: 10) {
            AvatarView(name: u.username, size: 34)
            Text(u.username)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
            BadgeLabel(text: u.roleText)
            Spacer(minLength: 0)
            Button {
                newPassword = ""
                resetTarget = u
            } label: {
                Text("重置密码")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.primary)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.primary.opacity(0.12)))
            }
            .buttonStyle(.plain)

            Button {
                deleteTarget = .user(u)
            } label: {
                Text("删除")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.danger)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.danger.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    // MARK: - 弹窗

    private var addPathSheet: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text("添加媒体库路径")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)

                inputField("名称（如：短剧）", text: $newName)
                inputField("NAS 路径（如 /vol3/1000/影视/短剧）", text: $newPath)

                HStack(spacing: 10) {
                    ForEach([("series", "短剧"), ("video", "视频")], id: \.0) { pair in
                        Button {
                            newType = pair.0
                        } label: {
                            Text(pair.1)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(newType == pair.0 ? .white : Theme.textSecondary)
                                .padding(.horizontal, 16)
                                .frame(height: 34)
                                .background(
                                    Capsule().fill(newType == pair.0 ? Theme.primary : Theme.surface)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        showAddPath = false
                    } label: {
                        Text("取消")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await createPath() }
                    } label: {
                        Text("确定")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.primary))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)

                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .presentationDetents([.height(340)])
    }

    private func resetPasswordSheet(_ target: AdminUserRow) -> some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text("重置 \(target.username) 的密码")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)

                SecureField("新密码", text: $newPassword)
                    .font(.system(size: 15))
                    .foregroundColor(Theme.textPrimary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))

                HStack(spacing: 10) {
                    Button {
                        resetTarget = nil
                    } label: {
                        Text("取消")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await resetPassword(target) }
                    } label: {
                        Text("确定")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.primary))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .presentationDetents([.height(250)])
    }

    private func inputField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 15))
            .foregroundColor(Theme.textPrimary)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
    }

    // MARK: - 动作

    private func loadPaths() async {
        loadingPaths = true
        errorPaths = nil
        do {
            paths = try await ApiService.shared.adminPaths()
        } catch {
            errorPaths = "加载媒体库失败：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
        loadingPaths = false
    }

    private func loadUsers() async {
        loadingUsers = true
        errorUsers = nil
        do {
            users = try await ApiService.shared.adminUsers()
        } catch {
            errorUsers = "加载用户失败：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
        loadingUsers = false
    }

    private func toggleScan(_ p: AdminPath) async {
        do {
            if p.scanning {
                try await ApiService.shared.stopScan(p.id)
                toast("已停止扫描")
            } else {
                try await ApiService.shared.scanPath(p.id)
                toast("已开始扫描")
            }
        } catch {
            toast("操作失败：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
        }
        await loadPaths()
    }

    private func createPath() async {
        let n = newName.trimmingCharacters(in: .whitespaces)
        let p = newPath.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !p.isEmpty else {
            toast("请填写完整")
            return
        }
        do {
            try await ApiService.shared.createPath(name: n, path: p, type: newType)
            toast("已添加")
            showAddPath = false
            await loadPaths()
        } catch {
            toast("添加失败：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
        }
    }

    private func resetPassword(_ user: AdminUserRow) async {
        let pwd = newPassword.trimmingCharacters(in: .whitespaces)
        guard !pwd.isEmpty else {
            toast("请输入新密码")
            return
        }
        do {
            try await ApiService.shared.resetPassword(user.id, password: pwd)
            toast("已重置密码")
            resetTarget = nil
        } catch {
            toast("重置失败：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
        }
    }

    private func performDelete(_ target: DeleteTarget) {
        Task {
            switch target {
            case let .path(p):
                do {
                    try await ApiService.shared.deletePath(p.id)
                    toast("已删除")
                } catch {
                    toast("删除失败：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
                }
                await loadPaths()
            case let .user(u):
                do {
                    try await ApiService.shared.deleteUser(u.id)
                    toast("已删除")
                } catch {
                    toast("删除失败：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
                }
                await loadUsers()
            }
        }
    }
}
