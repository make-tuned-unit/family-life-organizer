import SwiftUI

enum KinrowsBrand {
    static let evergreen = Color(hex: "0F3D37")
    static let sage = Color(hex: "8FAE8F")
    static let oat = Color(hex: "F7F3E9")
    static let clay = Color(hex: "C76F4F")
    static let river = Color(hex: "6B8FB0")
    static let sun = Color(hex: "F2C94C")
    static let ink = Color(hex: "1F2A24")
    static let mist = Color(hex: "E8EEE9")
}

extension Color {
    init(hex: String) {
        let v = UInt64(hex, radix: 16) ?? 0
        self.init(.sRGB, red: Double((v >> 16) & 0xff)/255, green: Double((v >> 8) & 0xff)/255, blue: Double(v & 0xff)/255, opacity: 1)
    }
}
