import SwiftUI

/// App chứa bàn phím: hướng dẫn bật ViPi và cài đặt. Giao diện SwiftUI chuẩn nên tự có Liquid Glass của iOS 26.
@main
struct ViPiApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                SettingsView()
            }
        }
    }
}
