# iPhone Monitor - PC (C# WinForms) + iOS (Swift)

## Cấu trúc
- PC/   : ứng dụng Windows (Visual Studio 2019+, .NET Framework 4.8, build x64)
- iOS/  : mã nguồn app Swift/SwiftUI (Xcode 14+, iOS 15+)

## Tab 1 - Thông tin & dung lượng (không cần app iOS)
Đọc qua libimobiledevice: tên, model, iOS, serial, UDID, pin, dung lượng. USB-C hoặc Wi-Fi sync.

## Tab 2 - Live CPU/RAM (cần app iOS)
App iOS mở cổng TCP 5050 và gửi 1 dòng JSON/giây: CPU, RAM, pin, nhiệt độ, mạng, tiết kiệm pin, sự kiện.
- Chế độ USB-C : PC mở đường hầm qua usbmuxd (như iproxy) tới cổng 5050 trong iPhone. Không cần Wi-Fi.
- Chế độ Wi-Fi : nhập IP iPhone (app hiển thị sẵn), cùng mạng LAN.

## Cài app iOS (cần Mac + Xcode)
1. Xcode > File > New > Project > iOS > App. Tên "iPhoneMonitor", Interface: SwiftUI, Language: Swift.
2. Xoá 2 file mẫu (iPhoneMonitorApp.swift, ContentView.swift) rồi kéo toàn bộ file .swift trong iOS/iPhoneMonitorApp/ vào project.
3. Thêm 2 khoá Info.plist theo Info-plist-keys.txt.
4. Signing & Capabilities: chọn Team (Apple ID miễn phí được, app hết hạn sau 7 ngày). Cắm iPhone, bấm Run.
5. Lần đầu bấm "Cho phép" quyền Mạng cục bộ.

## Dùng
1. Mở app trên iPhone, để màn hình sáng (iOS dừng app khi chạy nền).
2. PC: tab Live > chọn USB-C hoặc Wi-Fi > Kết nối.

## Build app iOS trên GitHub (không cần Mac)
1. Tạo repo mới trên GitHub, đẩy **toàn bộ nội dung thư mục này** lên (thư mục `.github`, `iOS`, `PC` nằm ở gốc repo).
2. Vào tab **Actions** > workflow **Build iOS (IPA chưa ký)** (tự chạy khi push, hoặc bấm *Run workflow*).
3. Chạy xong, mở lần chạy đó > mục **Artifacts** > tải `iPhoneMonitor-unsigned-ipa`, giải nén ra `iPhoneMonitor-unsigned.ipa`.
4. IPA này **chưa ký**, không cài trực tiếp được. Cài lên iPhone bằng **Sideloadly** hoặc **AltStore** (đăng nhập Apple ID miễn phí, app hết hạn sau 7 ngày, cài lại để gia hạn).
Project Xcode được tạo tự động từ `iOS/project.yml` bằng XcodeGen; 2 khoá Info.plist (Mạng cục bộ, Bonjour) đã khai báo sẵn trong file này.
