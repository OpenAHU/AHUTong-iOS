import SwiftUI
import UIKit

/// Keeps SwiftUI detail destinations attached to UIKit's native navigation
/// gestures. UIKit owns both recognizers and their transition coordination;
/// this bridge only makes sure they remain enabled after the root screen hides
/// its navigation bar and a detail screen makes it visible again.
struct NativeNavigationGestureBridge: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> NavigationGestureProbeViewController {
        NavigationGestureProbeViewController()
    }

    func updateUIViewController(
        _ uiViewController: NavigationGestureProbeViewController,
        context: Context
    ) {
        uiViewController.configureNavigationGestures()
    }
}

final class NavigationGestureProbeViewController: UIViewController {
    override func loadView() {
        view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        configureNavigationGestures()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        configureNavigationGestures()
    }

    func configureNavigationGestures() {
        guard let navigationController else { return }

        let canPop = navigationController.viewControllers.count > 1
        navigationController.interactivePopGestureRecognizer?.isEnabled = canPop
        if #available(iOS 26.0, *) {
            navigationController.interactiveContentPopGestureRecognizer?.isEnabled = canPop
        }
    }
}
