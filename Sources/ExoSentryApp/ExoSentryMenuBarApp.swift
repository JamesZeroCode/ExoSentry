import ExoSentryCore
import SwiftUI

@main
struct ExoSentryMenuBarApp: App {
    @StateObject private var model = MenuBarViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarDropdownView(model: model)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: model.payload.status.iconName)
                    .foregroundStyle(model.payload.status.statusColor)
                if model.showsWarningDot {
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView(model: model)
        }
    }
}
