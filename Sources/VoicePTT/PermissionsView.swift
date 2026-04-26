import AppKit
import SwiftUI

struct PermissionsSection: View {
    @ObservedObject var status: AppStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.headline)

            statusRow(
                label: "Microphone access",
                hint: "Required to record your voice.",
                granted: status.micGranted,
                fixURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            )
            statusRow(
                label: "Accessibility",
                hint: "Required to paste the recognized text into the active window.",
                granted: status.accessibilityGranted,
                fixURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
            statusRow(
                label: "Notifications",
                hint: "Used to confirm the app is ready when launched.",
                granted: status.notificationsGranted,
                fixURL: "x-apple.systempreferences:com.apple.preference.notifications"
            )
            statusRow(
                label: "Speech model",
                hint: "Parakeet (~500 MB) downloads on first launch.",
                granted: status.modelLoaded,
                fixURL: nil
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(status.allGreen ? Color.clear : Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(status.allGreen ? Color.secondary.opacity(0.3) : Color.orange, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func statusRow(label: String, hint: String, granted: Bool, fixURL: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? Color.green : Color.orange)
                .imageScale(.large)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.body)
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted, let urlStr = fixURL, let url = URL(string: urlStr) {
                Button("Open Settings") { NSWorkspace.shared.open(url) }
                    .controlSize(.small)
            }
        }
    }
}
