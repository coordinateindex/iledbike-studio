"""Deterministic lightweight source, output and data inventories. Stdlib only."""
import html
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sources = sorted(p for folder in ("Sources", "Tests", "scripts") for p in (ROOT / folder).glob("*") if p.is_file())
sources += sorted((ROOT / "iOS").rglob("*.swift"))
code = {"schema": 1, "note": "Heuristic symbol/call inventory, not a compiler semantic graph.", "files": []}
for path in sources:
    text = path.read_text()
    code["files"].append({"path": str(path.relative_to(ROOT)),
        "imports": sorted(set(re.findall(r"^(?:import|from) ([\w.]+)", text, re.M))),
        "symbols": [{"kind": m.group(1), "name": m.group(2), "line": text[:m.start()].count("\n") + 1}
                    for m in re.finditer(r"\b(class|struct|enum|func|def)\s+(\w+)", text)],
        "calls": sorted(set(re.findall(r"\b([A-Za-z_]\w*)\s*\(", text)))})
outputs = {"schema": 1, "artifacts": [
    {"path": ".build/halloween-*.png", "writer": "Tests/Checks.swift", "trigger": "offline preset validation", "owner": "developer", "committed": False},
    {"path": ".build/*advertisements.jsonl", "writer": "scripts/scan_advertisements.swift", "trigger": "explicit bounded read-only BLE scan", "owner": "user", "committed": False},
    {"path": "iOS/iLedBikeMobile.xcodeproj", "writer": "scripts/generate_ios_project.py", "trigger": "project regeneration", "owner": "developer", "committed": True},
    {"path": "iOS/iLedBikeMobile/Assets.xcassets", "writer": "scripts/generate_app_icon.py", "trigger": "icon regeneration", "owner": "developer", "committed": True},
    {"path": "iPhone Documents/BikeLibrary.json", "writer": "LibraryStore.saveNow", "trigger": "debounced editing, bike assignment, background save", "owner": "user", "committed": False},
    {"path": ".build/ios*/Build/Products", "writer": "xcodebuild", "trigger": "simulator or Personal Team device build", "owner": "developer", "committed": False},
    {"path": "local app preference replaceFlashingMode", "writer": "StudioView AppStorage", "trigger": "double-flash checkbox changed", "owner": "user", "committed": False},
    {"path": "dist/iLedBike Studio.app", "writer": "scripts/build.sh", "trigger": "local build", "owner": "developer", "committed": False},
    {"path": "*.iledbike.json", "writer": "StudioView.saveDesign", "trigger": "Save design", "owner": "user", "committed": False},
    {"path": "*.png", "writer": "StudioView.exportPreview", "trigger": "Export pixels", "owner": "user", "committed": False},
    {"path": "panel ordinary program", "writer": "BikeConnection.upload", "trigger": "Send to panel", "owner": "user", "committed": False},
    {"path": "panel display power state", "writer": "BikeConnection.setDisplayPower", "trigger": "explicit Display on/off for selected saved bike", "owner": "user", "committed": False},
    {"path": "panel active driving mode", "writer": "BikeConnection.selectSignal", "trigger": "explicit signal button for selected saved bike", "owner": "user", "committed": False},
    {"path": "panel double-flash artwork (state 5)", "writer": "BikeConnection.finishUpload / BikeProtocol.upload", "trigger": "Send to panel with explicit double-flash replacement selected", "owner": "user", "committed": False},
    {"path": "docs/{code,output,data}_map.{html,json}", "writer": "scripts/generate_cockpit.py", "trigger": "regenerate after structural changes", "owner": "developer", "committed": True},
    {"path": ".build/text-preview.png", "writer": "Tests/Checks.swift", "trigger": "offline checks", "owner": "developer", "committed": False},
]}
data = {"schema": 1, "contracts": [
    {"name": "Halloween templates", "owner": "iOS/iLedBikeMobile/HalloweenDesigns.swift", "fields": {"images": "four original 36x12 row-major RGB pixel designs", "messages": "two scrolling text designs", "storage": "immutable bundled source; selecting copies into current bike draft"}, "monitor": "Design validation and program encoding; explicit Send remains required"},
    {"name": "Advertisement observations", "owner": "scripts/scan_advertisements.swift", "fields": {"identity": "local peripheral UUID and advertised or cached name; private", "metadata": "service UUIDs, manufacturer length/company bytes, connectability, RSSI", "counts": "CoreBluetooth callbacks, not guaranteed over-the-air packet counts", "time": "monotonic first/final observations; no power measurement"}, "monitor": "5–45 second scan; no connections, pairing or GATT operations; absence is inconclusive"},
    {"name": "PhoneLibrary", "owner": "iOS/LibraryStore.swift", "fields": {"version": "2; version 1 migrates on load", "bikes": "two local profiles, distinct optional phone-scoped peripheral UUIDs", "selectedBikeID": "bike-1|bike-2", "drafts": "per-bike Design", "designs": "up to 200 named Design snapshots"}, "monitor": "validate before load/save, atomic writes; corrupt input preserved"},
    {"name": "Phone connection identity and readiness", "owner": "PhoneStudio / BikeConnection", "fields": {"identity": "validated 36x12 advertisement, physical isolation and confirmed LED panel plus fresh RIGHT event before naming", "readiness": "connected and fresh info reports display on", "lifetime": "disconnect in background; no automatic upload replay"}, "monitor": "saved owner shown during setup; explicit guarded connection-only reassignment; named destination CTA; preflight info query; stale peripheral callbacks ignored"},
    {"name": "Double-flash preference", "owner": "StudioView AppStorage", "fields": {"key": "replaceFlashingMode", "type": "boolean; default true", "scope": "local app-wide; survives reconnects and restarts; separate from design files"}, "monitor": "checkbox state; content writes still require Send to panel"},
    {"name": "Pixel drawing", "owner": "PixelDrawing.swift / StudioView", "fields": {"canvas": "36 columns × 12 rows", "pixels": "same Design.imagePixels RGB888 array", "history": "up to 100 image snapshots; session-only"}, "monitor": "bounded pointer coordinates, continuous cell interpolation, explicit Send only"},
    {"name": "Design", "owner": "Design.swift", "fields": {"version": "1", "kind": "message|image", "text": "up to 40 characters", "color": "#RRGGBB", "scrolling": "boolean", "speed": "1..255", "imagePixels": "optional 1296-byte row-major RGB array"}, "monitor": "Design.validate before render/open/send"},
    {"name": "Raster", "owner": "Design.swift", "fields": {"width": "36 or message width <=255", "height": "12", "pixels": "row-major RGB888"}, "monitor": "bounded image decode, exact size validation"},
    {"name": "BLE frame", "owner": "Protocol.swift", "fields": {"start": "0x01", "length": "big-endian UInt16", "body": "escaped payload", "end": "0x03"}, "monitor": "strict length/escape decoder, opcode allowlist"},
    {"name": "Program upload", "owner": "Bluetooth.swift", "fields": {"announce": "ordinary 0x02; optional 0x1A restricted to state 5", "data": "0x03, 1024-byte application chunks", "delivery": "MTU-limited BLE fragments", "atomicity": "ordinary first, optional flash second; may partially succeed"}, "monitor": "target-scoped command policy, indexed acknowledgements, timeout, settings comparison"},
    {"name": "Display power operation", "owner": "DisplayPowerChange / BikeConnection / PhoneStudio", "fields": {"request": "05 00 off or 05 01 on; explicit exact-value command grant", "identity": "connected UUID must match selected saved bike", "sequence": "fresh 1F baseline, matching 05 echo, fresh 1F verification", "scope": "LED display state; no handheld-remote or full-power-isolation claim"}, "monitor": "only requested power byte may differ; busy gate, timeout/disconnect/background cancel without replay; hardware check separate"},
    {"name": "Signal selection", "owner": "BikeProtocol.Signal / BikeConnection / PhoneStudio", "fields": {"request": "1B plus fixed mode 0..4; selects existing artwork", "query": "1C with exact state readback", "identity": "selected saved bike UUID and fresh display-on baseline", "source": "manufacturer-hosted app static DEX analysis; UD and UX formats differ"}, "monitor": "exact-operation command scope, fresh mode reply and unchanged info, conflicting remote report fails, no retries or background actions; physical test separate"},
    {"name": "Remote mode observations", "owner": "docs/protocol.md / Bluetooth.swift", "fields": {"notification": "1E plus state byte", "mapping": "0 ordinary, 1 forward, 2 left, 3 right, 4 brake/back, 5 double-flash", "scope": "physically correlated on the connected panel; no button-origin field"}, "monitor": "user reports physical behavior; no assumption that cycle entries can be deleted"},
    {"name": "Reference knowledge", "owner": "docs/protocol.md", "fields": {"sources": "pinned public SDK and protocol references", "hardware": "compatible 36×12 iLedBike", "usage": "README.md, iOS/README.md, docs/user-guide.md"}, "monitor": "physical visual and remote checks; no hardware identity in maps"},
]}
docs = ROOT / "docs"
docs.mkdir(exist_ok=True)
for name, content in (("code", code), ("output", outputs), ("data", data)):
    payload = json.dumps(content, indent=2, sort_keys=True) + "\n"
    (docs / f"{name}_map.json").write_text(payload)
    (docs / f"{name}_map.html").write_text("<!doctype html><html lang='en'><meta charset='utf-8'><meta name='viewport' content='width=device-width'><title>iLedBike " + name + " map</title><style>body{background:#11171b;color:#e1e9ed;font:15px system-ui;max-width:1100px;margin:40px auto;padding:20px}a{color:#b0f55c}pre{background:#1b2328;padding:24px;white-space:pre-wrap;overflow-wrap:anywhere;font:12px/1.6 monospace}nav{display:flex;gap:24px}</style><nav>" + "".join(f"<a href='{n}_map.html'>{n.title()} map</a>" for n in ("code", "output", "data")) + f"</nav><h1>iLedBike Studio · {name.title()} map</h1><pre>" + html.escape(payload) + "</pre></html>\n")
print("Generated six deterministic cockpit maps.")
