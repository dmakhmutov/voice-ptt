import AVFoundation
import ApplicationServices
import Combine
import Foundation
import UserNotifications

/// Single source of truth for "is the app fully set up" — observed by the
/// SwiftUI status section in Settings, kept in sync by AppDelegate.
@MainActor
final class AppStatus: ObservableObject {
    static let shared = AppStatus()

    @Published var micGranted: Bool = false
    @Published var accessibilityGranted: Bool = false
    @Published var notificationsGranted: Bool = false
    @Published var modelLoaded: Bool = false

    var allGreen: Bool {
        micGranted && accessibilityGranted && notificationsGranted && modelLoaded
    }

    /// Read-only TCC checks — no prompts. Calling repeatedly is cheap.
    func refreshPermissions() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let granted = settings.authorizationStatus == .authorized
            Task { @MainActor in
                self.notificationsGranted = granted
            }
        }
    }
}
