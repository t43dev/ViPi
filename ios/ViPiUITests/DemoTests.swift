import XCTest

/// Video cho App Review, quay trên iPhone thật (scripts/ios-demo.sh): mở app từ màn hình chính, bật bàn phím trong
/// Settings, gõ tiếng Việt, tiếng Anh, tiếng Trung trong app và trong Notes, xem cài đặt. Ghi hình bằng nút Screen
/// Recording của Control Center trên chính máy, video nằm trong Photos (lấy về bằng AFC, thư mục DCIM).
/// Toạ độ phím theo iPhone 6,1" (393 × 852 pt), xem KeyboardView.metrics: rộng < 410 thì hàng 54 pt, thanh 36 pt.
/// Biến môi trường (TEST_RUNNER_<tên>):
///   VIPI_RECORD   có thì bật / tắt Screen Recording ở đầu và cuối
///   VIPI_GLOBE    "x,y" quả địa cầu ở thanh dưới (mặc định 40,811)
///   VIPI_STEP     "dump" in cây accessibility của màn hình chính, Control Center, Notes; "reset" gỡ ViPi khỏi danh
///                 sách bàn phím và xoá ghi chú vừa tạo
final class DemoTests: XCTestCase {
    let env = ProcessInfo.processInfo.environment
    let vipi = XCUIApplication(bundleIdentifier: "dev.t43.vipi")
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    let notes = XCUIApplication(bundleIdentifier: "com.apple.mobilenotes")

    // iPhone 6,1": hàng phím (tâm), thanh gợi ý, 1 đơn vị = (393 − 2 × 3,7) / 10
    let rowY: [Double] = [593, 647, 701, 755]
    let barY = 548.0
    let unit = (393 - 7.4) / 10

    func pause(_ s: Double) { usleep(UInt32(s * 1_000_000)) }

    func tap(_ x: Double, _ y: Double, in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y)).tap()
    }

    /// Gõ như người: chữ hoa thì bấm Shift trước, khoảng cách giữa hai phím ~0,3 giây.
    func type(_ text: String, in app: XCUIApplication) {
        let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
        for ch in text {
            if ch == " " {
                tap(3.7 + unit * 5, rowY[3], in: app)
            } else if let r = rows.firstIndex(where: { $0.contains(Character(ch.lowercased())) }) {
                if ch.isUppercase { tap(3.7 + unit * 0.75, rowY[2], in: app); pause(0.25) }
                let i = Double(rows[r].distance(from: rows[r].startIndex, to: rows[r].firstIndex(of: Character(ch.lowercased()))!))
                tap(3.7 + unit * (i + 0.5 + [0, 0.5, 1.5][r]), rowY[r], in: app) // hàng 2 lùi 0,5 phím, hàng 3 sau Shift 1,5
            }
            pause(0.3)
        }
    }

    /// Phím ngôn ngữ (VI ↔ 拼), cạnh phím 123
    func modeKey(_ app: XCUIApplication) { tap(3.7 + unit * 2, rowY[3], in: app) }

    /// Giữ phím góc trái dưới (iOS 27 có bàn phím Emoji thì đó là nút emoji), chọn ViPi trong danh sách.
    func chooseViPi(in app: XCUIApplication) {
        let g = (env["VIPI_GLOBE"] ?? "40,811").split(separator: ",").compactMap { Double($0) }
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: g[0], dy: g[1])).press(forDuration: 1.0)
        let item = app.cells.matching(NSPredicate(format: "label BEGINSWITH 'ViPi'")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3), app.debugDescription)
        pause(0.8)
        item.tap()
        pause(1.5)
    }

    func screenRecording() {
        openControlCenter()
        let button = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'Screen Recording'")).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), springboard.debugDescription)
        button.tap()
        pause(4.5) // đếm ngược 3 giây
        XCUIDevice.shared.press(.home)
        pause(1)
    }

    /// Tắt ViPi trong trang Settings của app (để lần quay sau có cảnh bật), xoá các ghi chú demo, về màn hình chính.
    func testReset() throws {
        unlock()
        for app in [vipi, settings, notes] { app.terminate() }
        vipi.launch()
        vipi.buttons["Open Settings"].tap()
        let keyboards = settings.descendants(matching: .any)["Keyboards"].firstMatch
        XCTAssertTrue(keyboards.waitForExistence(timeout: 10), settings.debugDescription)
        keyboards.tap()
        let toggle = settings.switches["ViPi"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        if toggle.value as? String == "1" { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); pause(1) }
        print("VIPI_KEYBOARD=\(toggle.value ?? "")")
        for app in [vipi, settings] { app.terminate() }
        notes.launch()
        pause(2)
        // Notes mở lại trang lần trước: lùi về danh sách thư mục rồi vào thư mục Notes
        for _ in 0..<4 where notes.buttons["BackButton"].exists { notes.buttons["BackButton"].firstMatch.tap(); pause(1.2) }
        // chỉ các ghi chú do bài demo gõ
        let demo = NSPredicate(format: "label CONTAINS 'English' OR label CONTAINS 'Emglish' OR label CONTAINS 'Tiếng Việt' OR label CONTAINS 'Tieem'")
        for _ in 0..<20 {
            let folder = notes.cells["Folder[id=DefaultFolder-CloudKit]"].firstMatch
            if folder.exists { folder.tap(); pause(1.5) }
            // sau khi xoá, Notes mở ghi chú kế tiếp: lùi về danh sách
            if notes.textViews.firstMatch.exists && notes.buttons["BackButton"].exists { notes.buttons["BackButton"].firstMatch.tap(); pause(1.2) }
            let note = notes.cells.matching(demo).firstMatch
            guard note.waitForExistence(timeout: 2) else { break }
            print("VIPI_DELETE=\(note.label.prefix(60))")
            // mở ghi chú, More → Delete (vuốt trái trong danh sách có lúc xoá luôn, có lúc không)
            note.tap()
            pause(1.2)
            let more = notes.buttons.matching(NSPredicate(format: "identifier == 'TopOverflowBarButtonItem' OR label == 'More'")).firstMatch
            guard more.waitForExistence(timeout: 5) else { print("VIPI_DUMP note\n\(notes.debugDescription)"); break }
            more.tap()
            pause(1)
            let delete = notes.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] 'Delete'")).firstMatch
            guard delete.waitForExistence(timeout: 3) else { print("VIPI_DUMP more\n\(notes.debugDescription)"); break }
            delete.tap()
            pause(1.5)
        }
        // lần mở sau (lúc quay) Notes hiện danh sách thư mục, không lộ tiêu đề ghi chú
        for _ in 0..<4 where notes.buttons["BackButton"].exists { notes.buttons["BackButton"].firstMatch.tap(); pause(1.2) }
        print("VIPI_NOTES_FOLDERS=\(notes.cells["Folder[id=DefaultFolder-CloudKit]"].exists)")
        notes.terminate()
        XCUIDevice.shared.press(.home)
    }

    /// Mở khoá (máy không có mật mã): bấm Home rồi vuốt lên từ đáy.
    func unlock() {
        XCUIDevice.shared.press(.home)
        pause(1)
        if springboard.otherElements["Home indicator"].exists || springboard.buttons["camera-orb-button"].exists {
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99))
                .press(forDuration: 0.05, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
            pause(1.5)
        }
    }

    func openControlCenter() {
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.005))
            .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.6)))
        pause(1.5)
    }

    /// Chuẩn bị máy (không quay): qua màn Welcome của Notes, thêm nút Screen Recording vào Control Center, bật Do Not Disturb.
    func testSetup() throws {
        unlock()
        notes.launch()
        pause(2)
        for label in ["Continue", "Not Now", "OK"] where notes.buttons[label].exists { notes.buttons[label].tap(); pause(1) }
        print("VIPI_DUMP notes\n\(notes.debugDescription)")
        notes.terminate()
        XCUIDevice.shared.press(.home)
        openControlCenter()
        let rec = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'Screen Recording'")).firstMatch
        if !rec.exists {
            springboard.buttons["Add Controls"].tap()
            pause(1.5)
            print("VIPI_DUMP edit\n\(springboard.debugDescription)")
            let add = springboard.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Add a Control'")).firstMatch
            if add.waitForExistence(timeout: 3) { add.tap(); pause(2) }
            print("VIPI_DUMP gallery\n\(springboard.debugDescription)")
            let search = springboard.searchFields.firstMatch
            if search.waitForExistence(timeout: 3) { search.tap(); search.typeText("Screen Recording"); pause(2) }
            print("VIPI_DUMP search\n\(springboard.debugDescription)")
            let item = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'Screen Recording'")).firstMatch
            if item.waitForExistence(timeout: 3) { item.tap(); pause(2) }
            print("VIPI_DUMP added\n\(springboard.debugDescription)")
            XCUIDevice.shared.press(.home)
            pause(1)
            openControlCenter()
        }
        print("VIPI_REC=\(rec.exists)")
        let focus = springboard.buttons["Focus"].firstMatch
        if focus.exists {
            focus.press(forDuration: 1.0)
            pause(1.5)
            let dnd = springboard.buttons["mode-Do Not Disturb"].firstMatch
            if dnd.exists { print("VIPI_DND_BEFORE=\(dnd.value ?? "")"); dnd.tap(); pause(1) }
        }
        XCUIDevice.shared.press(.home)
    }

    /// Giữ phím góc trái dưới (emoji / quả địa cầu) và in cây accessibility của danh sách bàn phím.
    func testGlobe() throws {
        unlock()
        vipi.activate()
        let field = vipi.descendants(matching: .any)["trial"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        pause(1.5)
        print("VIPI_DUMP kb\n\(vipi.keyboards.firstMatch.debugDescription)")
        let g = (env["VIPI_GLOBE"] ?? "40,811").split(separator: ",").compactMap { Double($0) }
        vipi.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: g[0], dy: g[1])).press(forDuration: 1.2)
        pause(1)
        print("VIPI_DUMP menu\n\(vipi.debugDescription)")
        print("VIPI_DUMP menu-sb\n\(springboard.debugDescription)")
        pause(4)
    }

    /// Tắt Do Not Disturb mà testSetup đã bật.
    func testDndOff() throws {
        unlock()
        openControlCenter()
        let focus = springboard.buttons["Focus"].firstMatch
        XCTAssertTrue(focus.waitForExistence(timeout: 5))
        focus.press(forDuration: 1.0)
        pause(1.5)
        let dnd = springboard.buttons["mode-Do Not Disturb"].firstMatch
        XCTAssertTrue(dnd.waitForExistence(timeout: 5))
        print("VIPI_DND=\(dnd.isSelected) \(dnd.label)")
        if dnd.isSelected || dnd.label.contains("On") { dnd.tap(); pause(1) }
        XCUIDevice.shared.press(.home)
    }

    func testDump() throws {
        unlock()
        print("VIPI_DUMP home\n\(springboard.debugDescription)")
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.005))
        top.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.6)))
        pause(1.5)
        print("VIPI_DUMP cc\n\(springboard.debugDescription)")
        XCUIDevice.shared.press(.home)
        notes.launch()
        pause(2)
        print("VIPI_DUMP notes\n\(notes.debugDescription)")
        notes.terminate()
        XCUIDevice.shared.press(.home)
    }

    func testDemo() throws {
        let record = env["VIPI_RECORD"] != nil
        for app in [vipi, settings, notes] { app.terminate() }
        unlock()
        // Notes để chạy nền ở danh sách thư mục (mở lại có thể vào ghi chú cũ, kể cả trong Recently Deleted)
        notes.launch()
        pause(2)
        for _ in 0..<4 where notes.buttons["BackButton"].exists { notes.buttons["BackButton"].firstMatch.tap(); pause(1.2) }
        XCUIDevice.shared.press(.home)
        pause(1)
        if record { screenRecording() }

        // 1. mở ViPi từ màn hình chính
        let icon = springboard.icons["ViPi"]
        for _ in 0..<6 where !(icon.exists && icon.isHittable) { springboard.swipeLeft(); pause(0.8) }
        if icon.exists && icon.isHittable { icon.tap() } else { vipi.activate() }
        XCTAssertTrue(vipi.wait(for: .runningForeground, timeout: 10))
        pause(3)

        // 2. bật bàn phím: Open Settings → Keyboards → ViPi
        vipi.buttons["Open Settings"].tap()
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 10))
        pause(2)
        let keyboards = settings.descendants(matching: .any)["Keyboards"].firstMatch
        XCTAssertTrue(keyboards.waitForExistence(timeout: 10), settings.debugDescription)
        keyboards.tap()
        pause(1.5)
        let toggle = settings.switches["ViPi"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), settings.debugDescription)
        if toggle.value as? String != "1" { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        pause(2)

        // 3. về ViPi, gõ trong ô "Try it here"
        vipi.activate()
        pause(1.5)
        let field = vipi.descendants(matching: .any)["trial"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        pause(1.5)
        chooseViPi(in: vipi)
        XCTAssertFalse(vipi.keyboards.firstMatch.exists, "ViPi is not the current keyboard")
        pause(1)
        type("vieejt Nam ", in: vipi)       // Việt Nam
        pause(0.8)
        type("server ", in: vipi)           // server (English stays)
        pause(0.8)
        type("xin chaof ", in: vipi)        // xin chào
        pause(1.5)
        modeKey(vipi)                       // 拼
        pause(1)
        type("nihao", in: vipi)
        pause(1.5)
        tap(90, barY, in: vipi)             // 你好: ứng viên đầu, sau chữ pinyin ở đầu thanh
        pause(1.5)
        modeKey(vipi)                       // về VI
        print("VIPI_TEXT=\(field.value as? String ?? "")")
        pause(2)

        // 4. trong Notes: một ghi chú mới
        notes.activate()
        XCTAssertTrue(notes.wait(for: .runningForeground, timeout: 10))
        pause(1.5)
        let new = notes.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'New Note' OR identifier CONTAINS[c] 'compose'")).firstMatch
        XCTAssertTrue(new.waitForExistence(timeout: 10), notes.debugDescription)
        new.tap()
        pause(2)
        type("tooi ddang vieets Tieengs Vieejt ", in: notes) // Tôi đang viết Tiếng Việt (chữ T đầu: tự viết hoa)
        pause(0.8)
        type("and English ", in: notes)
        pause(0.8)
        modeKey(notes)
        pause(1)
        type("xiexie", in: notes)
        pause(1.5)
        tap(90, barY, in: notes)                              // 谢谢
        pause(1)
        modeKey(notes)
        print("VIPI_NOTE=\(notes.textViews.firstMatch.value as? String ?? "")")
        pause(2.5)

        // 5. cài đặt trong app
        vipi.activate()
        pause(1.5)
        for _ in 0..<3 { vipi.swipeUp(velocity: .slow); pause(1.2) }
        pause(1.5)
        for _ in 0..<3 { vipi.swipeDown(velocity: .fast) }
        pause(2)

        if record { screenRecording() }
    }
}
