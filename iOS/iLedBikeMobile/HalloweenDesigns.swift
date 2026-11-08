import Foundation

// Original pixel art drawn at the panel's native resolution. Rows run top to bottom.
// Templates are immutable; choosing one only replaces the selected bike's draft.
struct HalloweenTemplate: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let design: Design
}

enum HalloweenDesigns {
    private static let palette: [Character: [UInt8]] = [
        ".": [0, 0, 0], "o": [255, 102, 0], "y": [255, 204, 0],
        "g": [0, 255, 0], "w": [255, 255, 255], "c": [0, 204, 255],
        "p": [153, 0, 255]
    ]
    private static let pumpkin = [
        ".....g.....", "....gg.....", "..ooooooo..", ".ooooooooo.",
        "ooo.ooo.ooo", "oo...o...oo", "ooooo.ooooo", "ooo.ooo.ooo",
        ".oo.....oo.", "..ooooooo..", "...ooooo..."
    ]
    private static let ghost = [
        "...wwww...", "..wwwwww..", ".wwwwwwww.", ".ww.ww.ww.",
        ".ww.ww.ww.", ".wwwwwwww.", ".www..www.", ".wwwwwwww.",
        "wwwwwwwwww", "ww.wwww.ww", "w...ww...w"
    ]
    private static let bat = [
        "p....p.p....p", "pp...ppp...pp", "ppp.ppppp.ppp", "ppppppppppppp",
        ".ppppppppppp.", "..ppp.p.ppp..", "...p.....p..."
    ]
    private static let cat = [
        "p.....p", "pp...pp", "ppp.ppp", "ppppppp", "pypppyp",
        "ppppppp", ".ppppp.", "..ppp..", ".ppppp.", "ppppppp", "ppppppp"
    ]
    private static func image(_ id: String, _ name: String, _ subtitle: String,
                              sprites: [(rows: [String], x: Int, y: Int)]) -> HalloweenTemplate {
        var pixels = [UInt8](repeating: 0, count: 36 * 12 * 3)
        for sprite in sprites {
            for (dy, row) in sprite.rows.enumerated() {
                for (dx, symbol) in row.enumerated() {
                    let x = sprite.x + dx, y = sprite.y + dy
                    precondition((0..<36).contains(x) && (0..<12).contains(y))
                    guard symbol != ".", let rgb = palette[symbol] else { continue }
                    let offset = (y * 36 + x) * 3
                    pixels.replaceSubrange(offset..<offset + 3, with: rgb)
                }
            }
        }
        var design = Design(); design.kind = "image"; design.scrolling = false
        design.imagePixels = pixels
        return HalloweenTemplate(id: id, name: name, subtitle: subtitle, design: design)
    }
    private static func message(_ id: String, _ title: String, _ text: String, _ color: String) -> HalloweenTemplate {
        var design = Design(); design.text = text; design.color = color; design.scrolling = true
        return HalloweenTemplate(id: id, name: title, subtitle: "Scrolling message · tap to customize", design: design)
    }
    static let all: [HalloweenTemplate] = [
        image("pumpkin-patch", "Pumpkin patch", "Three grinning jack-o’-lanterns", sprites: [
            (pumpkin, 0, 0), (pumpkin, 12, 1), (pumpkin, 24, 0)
        ]),
        image("ghost-parade", "Ghost parade", "A little haunting for your ride", sprites: [
            (ghost, 0, 1), (ghost, 13, 0), (ghost, 26, 1)
        ]),
        image("midnight-bats", "Midnight bats", "Purple bats and a golden moon", sprites: [
            ([".yyy.", "yyyyy", "yyyyy", "yyyyy", ".yyy."], 16, 0),
            (bat, 0, 4), (bat, 23, 4)
        ]),
        image("familiar", "The familiar", "A violet cat guarding two pumpkins", sprites: [
            (pumpkin, 0, 1), (cat, 15, 1), (pumpkin, 25, 1)
        ]),
        message("boo-on-wheels", "Boo on wheels", "BOO ON WHEELS!", "#FF6600"),
        message("trick-or-treat", "Trick or treat", "TRICK OR TREAT!", "#00FF00")
    ]
}
