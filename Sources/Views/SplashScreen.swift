import SwiftUI

/// 启动页：Logo 呼吸动画 + 服务器探测提示
struct SplashScreen: View {
    @State private var scale: CGFloat = 0.86
    @State private var opacity: Double = 0.0

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.primary.opacity(0.10))
                    .frame(width: 150, height: 150)
                    .blur(radius: 8)
                Image(systemName: "play.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 86, height: 86)
                    .foregroundStyle(
                        LinearGradient(colors: [Theme.primary, Theme.primary.opacity(0.65)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .scaleEffect(scale)
                    .opacity(opacity)
            }
            Text("轻视频")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Theme.textPrimary)
                .opacity(opacity)
            Text("正在连接服务器…")
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .opacity(opacity)
            Spacer()
            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }
}
