import Foundation
import AppKit

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
func payload(_ frame: Data) -> [UInt8] {
    var decoder = FrameDecoder(); let result = decoder.feed(frame)
    check(result.count == 1, "one valid frame"); return result[0]
}
func read(_ bytes: [UInt8], _ start: Int, _ count: Int) -> Int {
    bytes[start..<start + count].reduce(0) { ($0 << 8) | Int($1) }
}
// Independent LZSS decoder, used to verify the actual upload bytes.
func decompress(_ input: [UInt8]) -> [UInt8] {
    var ring = [UInt8](repeating: 0x20, count: 512), cursor = 494
    var index = 0, output: [UInt8] = []
    while index < input.count {
        let flags = input[index]; index += 1
        for bit in 0..<8 where index < input.count {
            if flags & (1 << bit) != 0 {
                let value = input[index]; index += 1; output.append(value); ring[cursor] = value; cursor = (cursor + 1) & 511
            } else {
                check(index + 1 < input.count, "complete LZSS reference")
                let first = Int(input[index]), second = Int(input[index + 1]); index += 2
                let offset = first | ((second & 0xf0) << 4)
                for j in 0..<(second & 0x0f) + 3 {
                    let value = ring[(offset + j) & 511]; output.append(value); ring[cursor] = value; cursor = (cursor + 1) & 511
                }
            }
        }
    }
    return output
}

@main struct Checks {
    static func main() throws {
        for template in HalloweenDesigns.all {
            try template.design.validate()
            let raster = try template.design.raster()
            check(raster.height == 12 && raster.width >= 36, "Halloween canvas dimensions")
            check(raster.pixels.contains(where: { $0 != 0 }), "Halloween design is visible")
            _ = try template.design.program()
            try raster.png().write(to: URL(fileURLWithPath: ".build/halloween-\(template.id).png"))
        }
        check(BikeProtocol.crc(Array("123456789".utf8)) == 0x0376e6e7, "published CRC-32/MPEG-2 check value")
        let bytes = (0...255).map(UInt8.init)
        let frame = BikeProtocol.envelope(bytes)
        check(payload(frame) == bytes, "all byte values escape correctly")
        for split in 0...frame.count {
            var decoder = FrameDecoder()
            let frames = decoder.feed(frame.prefix(split)) + decoder.feed(frame.dropFirst(split))
            check(frames == [bytes], "fragment boundary \(split)")
        }
        var combined = FrameDecoder()
        check(combined.feed(frame + frame) == [bytes, bytes], "coalesced notifications")
        var malformed = FrameDecoder()
        check(malformed.feed(Data([1, 0, 10, 30, 3])).isEmpty, "reject inconsistent length")
        check(malformed.feed(Data([1, 2, 9, 3])).isEmpty, "reject invalid escape")
        for count in [0, 1, 7, 8, 9, 1024, 2049] {
            let data = (0..<count).map { UInt8(truncatingIfNeeded: $0 * 19) }
            check(decompress(BikeProtocol.literals(data)) == data, "LZSS roundtrip \(count)")
        }
        for value in 0...255 where ![2, 3, 31].contains(value) {
            do { try BikeProtocol.validate([UInt8(value)]); check(false, "forbidden opcode \(value)") } catch {}
        }
        try BikeProtocol.validate([31])
        check(BikeProtocol.envelope(BikeProtocol.Signal.left.payload) == Data([1, 0, 2, 6, 0x1b, 2, 6, 3]), "bike left command frame")
        for signal in BikeProtocol.Signal.allCases {
            try BikeProtocol.validate(signal.payload, signal: signal)
            try BikeProtocol.validate([0x1c], signal: signal)
            try signal.verifyMode([0x1c, signal.rawValue])
            do { try BikeProtocol.validate(signal.payload); check(false, "signal selection requires explicit scope") } catch {}
            do { try signal.verifyMode([0x1e, signal.rawValue]); check(false, "unsolicited notification is not query confirmation") } catch {}
            for state in 0...255 where state != Int(signal.rawValue) {
                do { try BikeProtocol.validate([0x1b, UInt8(state)], signal: signal); check(false, "different state blocked") } catch {}
                do { try signal.verifyMode([0x1c, UInt8(state)]); check(false, "different reported state rejected") } catch {}
            }
            for body: [UInt8] in [[0x1c, 1], [0x1b], [0x1b, signal.rawValue, 0], [0x1e, signal.rawValue], [0x05, 0], [0xfe, 0]] {
                do { try BikeProtocol.validate(body, signal: signal); check(false, "signal permission must not allow unrelated operations") } catch {}
            }
        }
        do { try BikeProtocol.validate([0x1c]); check(false, "drive query scoped to signal operation") } catch {}
        for on in [false, true] {
            let baseline: [UInt8] = [0x1f, on ? 0 : 1, 255, 0, 0, 0, 0]
            let change = try DisplayPowerChange(isOn: on, baseline: baseline)
            check(payload(BikeProtocol.envelope(change.payload)) == [5, on ? 1 : 0], "display power wire bytes")
            do { try BikeProtocol.validate(change.payload); check(false, "power blocked outside explicit operation") } catch {}
            try BikeProtocol.validate(change.payload, displayPower: on)
            do { try BikeProtocol.validate(change.payload, displayPower: !on); check(false, "opposite power command blocked") } catch {}
            var expected = baseline; expected[1] = on ? 1 : 0
            try change.verify(expected)
            do { try change.verify(baseline); check(false, "unchanged power is not success") } catch {}
            for index in 2..<expected.count {
                var changed = expected; changed[index] ^= 1
                do { try change.verify(changed); check(false, "unrelated setting change rejected") } catch {}
            }
            do { try change.verify(Array(expected.dropLast())); check(false, "truncated power check rejected") } catch {}
        }
        for body: [UInt8] in [[5], [5, 2], [5, 0, 0], [0x1e, 2], [0x1c, 2], [0xfe, 0]] {
            do { try BikeProtocol.validate(body, displayPower: false); check(false, "power grant must not allow other controls") } catch {}
        }
        do { _ = try DisplayPowerChange(isOn: false, baseline: [0x1f, 2, 255, 0, 0, 0, 0]); check(false, "unknown power state rejected") } catch {}
        let pixels = (0..<36 * 12 * 3).map { UInt8(truncatingIfNeeded: $0 * 7) }
        let program = try BikeProtocol.imageProgram(pixels: pixels)
        check(program[8] == 1 && program[14] == 2, "ordinary program with one image segment")
        check(read(program, 10, 4) == program.count - 10, "image segment length")
        check(read(program, 27, 2) == 36 && read(program, 29, 2) == 12, "image dimensions")
        check(read(program, 34, 4) == 864, "image pixel byte length")
        check(program[38] == BikeProtocol.quantize(pixels[0]), "first image pixel red")
        check(program[40] == BikeProtocol.quantize(pixels[36 * 3]), "column-major order")
        let longProgram = program + Array(repeating: 77, count: 2100)
        let packets = try BikeProtocol.upload(longProgram)
        let announce = payload(packets[0])
        check(announce[0] == 2 && Array(announce.suffix(3)) == [0, 1, 1], "ordinary single-program slot")
        check(read(announce, 1, 4) == Int(BikeProtocol.crc(longProgram)), "announce checksum")
        check(read(announce, 5, 4) == longProgram.count, "announce raw size")
        var compressed: [UInt8] = []
        for (index, packet) in packets.dropFirst().enumerated() {
            let data = payload(packet); try BikeProtocol.validate(data)
            check(read(data, 6, 2) == index, "ordered chunk index")
            let length = read(data, 8, 2)
            check(length == 1024 || index == packets.count - 2, "SDK packet size")
            check(data.dropFirst().reduce(0, ^) == 0, "chunk XOR")
            compressed += data[10..<10 + length]
        }
        check(decompress(compressed) == longProgram, "complete transport reconstructs original program")
        let flashPackets = try BikeProtocol.upload(program, target: .flashingMode)
        let flashAnnounce = payload(flashPackets[0])
        check(flashAnnounce.count == 10 && flashAnnounce[0] == 0x1a && flashAnnounce[9] == 5, "only verified double-flash slot 5 is addressable")
        check(read(flashAnnounce, 1, 4) == Int(BikeProtocol.crc(program)) && read(flashAnnounce, 5, 4) == program.count, "driving announcement checksum and raw size")
        do { try BikeProtocol.validate(flashAnnounce); check(false, "ordinary mode must reject driving writes") } catch {}
        try BikeProtocol.validate(flashAnnounce, target: .flashingMode)
        for state in 0...255 where state != 5 {
            var forbidden = flashAnnounce; forbidden[9] = UInt8(state)
            do { try BikeProtocol.validate(forbidden, target: .flashingMode); check(false, "protect every other driving state \(state)") } catch {}
        }
        for command: UInt8 in [0x1c, 0x1e, 0xfe, 0xff, 0x05] {
            do { try BikeProtocol.validate([command, 0, 0], target: .flashingMode); check(false, "flash mode must not enable settings or firmware") } catch {}
        }
        var flashCompressed: [UInt8] = []
        for (index, packet) in flashPackets.dropFirst().enumerated() {
            let body = payload(packet); try BikeProtocol.validate(body, target: .flashingMode)
            check(read(body, 6, 2) == index, "flash upload preserves chunk indexes")
            flashCompressed += body[10..<10 + read(body, 8, 2)]
        }
        check(decompress(flashCompressed) == program, "slot 5 receives the exact same image program")
        _ = NSApplication.shared
        var design = Design()
        design.text = "HELLO BIKE"; design.color = "#36D9FF"
        let raster = try design.raster()
        check(raster.height == 12 && raster.pixels.contains(where: { $0 != 0 }), "text raster contains visible pixels")
        let text = try design.program()
        check(text[8] == 1 && text[14] == 2, "messages use a single image layer, with no color-fill layer")
        check(text[31] == 2 && read(text, 27, 2) == raster.width, "scrolling image covers the complete text width")
        check(text.count == 38 + raster.width * 12 * 2, "no trailing segment or decorative pixel data")
        for x in 0..<raster.width { for y in 0..<12 {
            let source = (y * raster.width + x) * 3, wire = 38 + (x * 12 + y) * 2
            check(text[wire] == BikeProtocol.quantize(raster.pixels[source]), "message red matches preview")
            check(text[wire + 1] == (BikeProtocol.quantize(raster.pixels[source + 1]) << 4) | BikeProtocol.quantize(raster.pixels[source + 2]), "message green/blue matches preview")
        }}
        var still = design; still.text = "HI"; still.scrolling = false
        let stillProgram = try still.program()
        check(stillProgram[31] == 1 && read(stillProgram, 27, 2) == 36, "short static message uses fixed image mode")
        still.text = "HELLO BIKE"
        do { _ = try still.program(); check(false, "long static text must not silently clip") } catch {}
        var invalid = design; invalid.text = String(repeating: "a", count: 41)
        do { try invalid.validate(); check(false, "length cap") } catch {}
        let roundtrip = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(design))
        let roundtripProgram = try roundtrip.program()
        check(roundtripProgram == text, "saved design reproduces upload")
        try raster.png().write(to: URL(fileURLWithPath: ".build/text-preview.png"))
        let imported = try Raster.importImage(URL(fileURLWithPath: ".build/text-preview.png"))
        check(imported.pixels.count == 1296, "import fits physical display")
        print("PASS: framing, fragmentation, CRC, LZSS, command policy, packet layout, bitmap order, rendering, image import and design roundtrip.")
    }
}
