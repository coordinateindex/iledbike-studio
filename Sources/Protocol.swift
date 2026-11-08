import Foundation

enum StudioError: Error, LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

enum BikeProtocol {
    enum Signal: UInt8, CaseIterable {
        case artwork = 0, forward = 1, left = 2, right = 3, brake = 4
        var label: String {
            switch self {
            case .artwork: return "My design"
            case .forward: return "Forward"
            case .left: return "Left"
            case .right: return "Right"
            case .brake: return "Brake"
            }
        }
        var payload: [UInt8] { [0x1b, rawValue] }
        func verifyMode(_ response: [UInt8]) throws {
            guard response == [0x1c, rawValue] else {
                throw StudioError.invalid("The panel reported a different signal. Its remote may have changed it; no command was repeated.")
            }
        }
    }
    enum UploadTarget {
        case ordinary, flashingMode
        var command: UInt8 { self == .ordinary ? 0x02 : 0x1a }
        var label: String { self == .ordinary ? "ordinary display" : "double-flash slot 5" }
    }
    static let width = 36
    static let height = 12
    static func be(_ value: Int, _ count: Int) -> [UInt8] {
        (0..<count).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
    }
    static func envelope(_ payload: [UInt8]) -> Data {
        precondition(payload.count <= 65535)
        var bytes: [UInt8] = [1]
        for byte in be(payload.count, 2) + payload {
            if (1...3).contains(byte) { bytes += [2, byte ^ 4] } else { bytes.append(byte) }
        }
        bytes.append(3)
        return Data(bytes)
    }
    static func crc(_ bytes: [UInt8]) -> UInt32 {
        var value: UInt32 = 0xffffffff
        for byte in bytes {
            value ^= UInt32(byte) << 24
            for _ in 0..<8 { value = value & 0x80000000 != 0 ? (value << 1) ^ 0x04c11db7 : value << 1 }
        }
        return value
    }
    // Literal-only LZSS: valid N=512,F=18 stream, with no backreference ambiguity.
    static func literals(_ bytes: [UInt8]) -> [UInt8] {
        var result: [UInt8] = []
        for start in stride(from: 0, to: bytes.count, by: 8) {
            let group = Array(bytes[start..<min(start + 8, bytes.count)])
            result.append(UInt8((1 << group.count) - 1)); result += group
        }
        return result
    }
    static func quantize(_ value: UInt8) -> UInt8 {
        value >= 238 ? 15 : value <= 30 ? 0 : (value - 30) / 15 + 1
    }
    static func imageProgram(pixels: [UInt8], mode: UInt8 = 1, speed: UInt8 = 128, imageWidth: Int = width) throws -> [UInt8] {
        guard imageWidth > 0, imageWidth <= 512, pixels.count == imageWidth * height * 3, [1, 2].contains(mode) else {
            throw StudioError.invalid("Invalid image dimensions or display mode.")
        }
        var colors: [UInt8] = []
        for x in 0..<imageWidth { for y in 0..<height {
            let i = (y * imageWidth + x) * 3
            colors += [quantize(pixels[i]), (quantize(pixels[i + 1]) << 4) | quantize(pixels[i + 2])]
        }}
        var segment: [UInt8] = [2] + Array(repeating: 0, count: 8)
        segment += be(0, 2) + be(0, 2) + be(imageWidth, 2) + be(height, 2)
        segment += [mode, speed, 3]
        segment += be(colors.count, 4) + colors
        return Array(repeating: 0, count: 8) + [1, 0] + be(segment.count + 4, 4) + segment
    }
    static func upload(_ program: [UInt8], target: UploadTarget = .ordinary) throws -> [Data] {
        guard !program.isEmpty, program.count <= 32_768 else { throw StudioError.invalid("Design is too large.") }
        let compressed = literals(program)
        // State 5 was physically mapped to the center-button double-flash.
        // Never expose an arbitrary state index: states 1–4 are protected.
        let announce: [UInt8] = [target.command] + be(Int(crc(program)), 4) + be(program.count, 4)
            + (target == .ordinary ? [0, 1, 1] : [5])
        var result = [envelope(announce)]
        for (index, start) in stride(from: 0, to: compressed.count, by: 1024).enumerated() {
            let chunk = Array(compressed[start..<min(start + 1024, compressed.count)])
            var body: [UInt8] = [0] + be(compressed.count, 4) + be(index, 2) + be(chunk.count, 2) + chunk
            body.append(body.reduce(0, ^))
            result.append(envelope([3] + body))
        }
        return result
    }
    static func validate(_ payload: [UInt8], target: UploadTarget = .ordinary, displayPower: Bool? = nil, signal: Signal? = nil) throws {
        guard let command = payload.first else { throw StudioError.invalid("Empty command.") }
        let valid: Bool
        switch command {
        case 0x1f: valid = payload.count == 1
        case 0x05:
            valid = displayPower.map { payload == [0x05, $0 ? 1 : 0] } ?? false
        case 0x1b: valid = signal.map { payload == $0.payload } ?? false
        case 0x1c: valid = signal != nil && payload == [0x1c]
        case 0x02: valid = payload.count == 12 && Array(payload.suffix(3)) == [0, 1, 1]
        case 0x1a: valid = target == .flashingMode && payload.count == 10 && payload[9] == 5
        case 0x03:
            valid = payload.count >= 12 && payload[1] == 0
                && Int(payload[8]) * 256 + Int(payload[9]) == payload.count - 11
                && payload.count <= 1035 && payload.dropFirst().reduce(0, ^) == 0
        default: valid = false
        }
        guard valid else { throw StudioError.invalid("Blocked command: outside the selected operation policy.") }
    }
}

// A display switch is separate from an upload and may change only the power byte.
// It does not promise battery isolation or control of the handheld remote.
struct DisplayPowerChange {
    let isOn: Bool
    let baseline: [UInt8]
    var payload: [UInt8] { [0x05, isOn ? 1 : 0] }

    init(isOn: Bool, baseline: [UInt8]) throws {
        guard baseline.count >= 7, baseline[0] == 0x1f, baseline[1] <= 1 else {
            throw StudioError.invalid("Panel power status is not recognized. No switch command sent.")
        }
        self.isOn = isOn; self.baseline = baseline
    }
    func verify(_ response: [UInt8]) throws {
        var expected = baseline; expected[1] = isOn ? 1 : 0
        guard response == expected else {
            throw StudioError.invalid("The panel did not report the requested display state with other settings unchanged. Reconnect and inspect.")
        }
    }
}

struct FrameDecoder {
    private var body: [UInt8] = []
    private var active = false
    private var escaped = false
    mutating func feed(_ data: Data) -> [[UInt8]] {
        var frames: [[UInt8]] = []
        for byte in data {
            if byte == 1 { active = true; escaped = false; body = []; continue }
            guard active else { continue }
            if byte == 3 && !escaped {
                if body.count >= 2, Int(body[0]) * 256 + Int(body[1]) == body.count - 2 { frames.append(Array(body.dropFirst(2))) }
                active = false; body = []; continue
            }
            if escaped {
                guard (5...7).contains(byte) else { active = false; escaped = false; body = []; continue }
                body.append(byte ^ 4); escaped = false
            } else if byte == 2 { escaped = true } else { body.append(byte) }
            if body.count > 65537 { active = false; body = [] }
        }
        return frames
    }
}
