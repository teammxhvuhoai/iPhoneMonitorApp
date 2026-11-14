import SwiftUI

@main
struct iPhoneMonitorApp: App {
    @StateObject private var vm = MonitorViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
                .onAppear { vm.start() }
        }
    }
}
