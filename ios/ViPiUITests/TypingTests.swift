import XCTest

/// Gõ thử bàn phím ViPi trên simulator. Phím vẽ bằng Core Graphics nên test chạm theo toạ độ màn hình (point).
/// Biến môi trường (xcodebuild chuyển TEST_RUNNER_<tên> thành <tên>):
///   VIPI_TAPS  "x,y x,y ..." các điểm chạm, "w" chờ 1 giây, "p:x,y,giây" giữ, "2:x,y" chạm đúp, "d:x1,y1,x2,y2" kéo
///   VIPI_GLOBE "x,y" nút quả địa cầu của bàn phím hệ thống (mặc định iPhone 18 Pro dọc)
///   VIPI_PICK  "x,y" mục ViPi trong danh sách khi giữ quả địa cầu trên iPad (mặc định iPad Pro 13" dọc)
///   VIPI_LANDSCAPE có thì xoay ngang
///   VIPI_SET   "<nhãn công tắc trong app>=0|1", đặt trước khi gõ
///   VIPI_HOLD  số giây giữ màn hình cuối cùng (để chụp ảnh từ ngoài)
/// In ra VIPI_TEXT=<chữ trong ô "Try it here">.
final class TypingTests: XCTestCase {
    /// Bật ViPi trong Settings như người dùng làm (một lần cho mỗi simulator).
    func testEnableKeyboard() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        for step in [settings.descendants(matching: .any)["General"], settings.descendants(matching: .any)["Keyboard"], settings.cells["KEYBOARDS"]] {
            let item = step.firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 10), settings.debugDescription)
            item.tap()
        }
        if settings.staticTexts["ViPi"].waitForExistence(timeout: 3) { return }
        let add = settings.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Add New Keyboard'")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10), settings.debugDescription)
        add.tap()
        let vipi = settings.descendants(matching: .any)["ViPi"].firstMatch
        XCTAssertTrue(vipi.waitForExistence(timeout: 10), settings.debugDescription)
        vipi.tap()
        XCTAssertTrue(settings.staticTexts["ViPi"].waitForExistence(timeout: 10))
    }

    func testType() throws {
        let env = ProcessInfo.processInfo.environment
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = env["VIPI_LANDSCAPE"] == nil ? .portrait : .landscapeLeft
        app.launch()
        if let set = env["VIPI_SET"], let eq = set.lastIndex(of: "=") {
            // đặt một công tắc trong app (ghi vào App Group), để kiểm tra bàn phím đọc được cài đặt
            let label = String(set[..<eq]), want = String(set[set.index(after: eq)...])
            let toggle = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
            for _ in 0..<6 where !toggle.isHittable { app.swipeUp() }
            if toggle.value as? String != want { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap() }
            print("VIPI_SET=\(label)=\(toggle.value ?? "")")
            for _ in 0..<6 { app.swipeDown() }
        }
        let field = app.descendants(matching: .any)["trial"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        sleep(2)
        // Bàn phím của Apple (kể cả Emoji) nằm trong cây accessibility của app, ViPi thì không:
        // còn thấy nó thì bấm quả địa cầu (iPad: nút "Next keyboard"; iPhone: thanh dưới, chạm theo toạ độ VIPI_GLOBE "x,y").
        // Lần đầu iPad hiện màn "Quickly Change Keyboards" ngoài cây accessibility: bấm Continue bằng VIPI_TAPS.
        for _ in 0..<3 where app.keyboards.firstMatch.exists {
            let globe = app.keyboards.buttons["Next keyboard"]
            if globe.exists {
                // giữ quả địa cầu để chọn ViPi trong danh sách (bấm thường sẽ sang Emoji, mà Emoji trên iPad không có quả địa cầu)
                // danh sách này cũng ngoài cây accessibility: chạm mục ViPi theo toạ độ VIPI_PICK "x,y"
                globe.press(forDuration: 1.2)
                let p = (env["VIPI_PICK"] ?? "51,1239").split(separator: ",").compactMap { Double($0) }
                app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: p[0], dy: p[1])).tap()
            } else {
                let g = (env["VIPI_GLOBE"] ?? "42,833").split(separator: ",").compactMap { Double($0) }
                app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: g[0], dy: g[1])).tap()
            }
            sleep(2)
        }
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for step in (env["VIPI_TAPS"] ?? "").split(separator: " ") {
            if step == "w" { sleep(1); continue }
            let point = { (x: Double, y: Double) in origin.withOffset(CGVector(dx: x, dy: y)) }
            if step.hasPrefix("p:") || step.hasPrefix("d:") || step.hasPrefix("2:") {
                let v = step.dropFirst(2).split(separator: ",").compactMap { Double($0) }
                if step.hasPrefix("p:"), v.count == 3 { point(v[0], v[1]).press(forDuration: v[2]) }
                if step.hasPrefix("2:"), v.count == 2 { point(v[0], v[1]).doubleTap() }
                if step.hasPrefix("d:"), v.count == 4 { point(v[0], v[1]).press(forDuration: 0.2, thenDragTo: point(v[2], v[3])) }
                usleep(300_000)
                continue
            }
            let xy = step.split(separator: ",").compactMap { Double($0) }
            guard xy.count == 2 else { continue }
            origin.withOffset(CGVector(dx: xy[0], dy: xy[1])).tap()
            usleep(150_000)
        }
        sleep(1)
        print("VIPI_TEXT=\(field.value as? String ?? "")")
        if let hold = UInt32(env["VIPI_HOLD"] ?? "") { sleep(hold) }
    }
}
