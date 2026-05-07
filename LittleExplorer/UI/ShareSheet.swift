import SwiftUI
import UIKit

/// SwiftUI wrapper around UIActivityViewController. Used for GPX export
/// (writes the file to a temp URL and presents the system share sheet).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
