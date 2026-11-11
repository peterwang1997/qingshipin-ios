import SwiftUI
import UIKit

/// 纵向翻页信息流（基于 UIPageViewController）。
/// 相比 SwiftUI .page TabView，在 iPad / 嵌套 TabView 场景下手势更可靠，且是上下滑动。
struct VerticalPager<Content: View>: UIViewControllerRepresentable {
    let pageCount: Int
    @Binding var currentIndex: Int
    @ViewBuilder let page: (Int) -> Content

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let vc = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .vertical,
            options: [.interPageSpacing: 0]
        )
        vc.dataSource = context.coordinator
        vc.delegate = context.coordinator
        vc.view.backgroundColor = .black
        return vc
    }

    func updateUIViewController(_ vc: UIPageViewController, context: Context) {
        if !context.coordinator.initialized {
            context.coordinator.initialized = true
            if pageCount > 0 {
                let holder = PageHolder(index: 0, content: AnyView(page(0)))
                vc.setViewControllers([holder], direction: .forward, animated: false, completion: nil)
            }
        }
    }

    final class PageHolder: UIHostingController<AnyView> {
        let index: Int
        init(index: Int, content: AnyView) {
            self.index = index
            super.init(rootView: content)
        }
        @MainActor required dynamic init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: VerticalPager
        var initialized = false
        init(parent: VerticalPager) { self.parent = parent }

        private func make(_ index: Int) -> PageHolder {
            PageHolder(index: index, content: AnyView(parent.page(index)))
        }

        func pageViewController(_ vc: UIPageViewController, viewControllerBefore vc0: UIViewController) -> UIViewController? {
            guard let h = vc0 as? PageHolder else { return nil }
            let idx = h.index - 1
            guard idx >= 0, idx < parent.pageCount else { return nil }
            return make(idx)
        }

        func pageViewController(_ vc: UIPageViewController, viewControllerAfter vc0: UIViewController) -> UIViewController? {
            guard let h = vc0 as? PageHolder else { return nil }
            let idx = h.index + 1
            guard idx >= 0, idx < parent.pageCount else { return nil }
            return make(idx)
        }

        func pageViewController(_ vc: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController],
                                transitionCompleted completed: Bool) {
            if completed, let h = vc.viewControllers?.first as? PageHolder {
                parent.currentIndex = h.index
            }
        }
    }
}
