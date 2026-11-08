# iLedBike Studio user guide

See the [README](../README.md) for Mac setup and [iPhone setup](../iOS/README.md) for native builds. The apps connect to one panel at a time and do not send artwork merely because you edit or import a design.

## Identify the intended panel

Close or disconnect other controllers, turn the panel display on, and keep only the intended unit in range while identifying it. The same remote can trigger both panels; discovery order, names, signal strength, and an incoming button event alone are insufficient identification.

On Mac, choose **Find panel**. Connection details can show a fresh `Response: 1e03` after a short RIGHT press on the remote; also confirm the arrow on the physically isolated panel. Disconnect before selecting another unit.

On iPhone, open **Bikes → Find Bike 1** or **Find Bike 2**, connect, short-press RIGHT, and confirm the large LED panel showed the arrow before saving the connection. Discovery shows any existing saved owner. If a verified panel has the wrong saved name, explicitly move its connection into an unassigned profile; both drafts and saved designs are retained. Each phone has its own Bluetooth identifiers, so Mac identifiers are not copied.

## Messages, images, and drawing

Messages support up to 40 characters; longer messages need scrolling. Imported images fit inside the 36 × 12 panel with a black background. GIF import uses its first frame. The preview reflects pixel layout and encoded colors, but simulated scrolling and physical LED appearance can differ.

On Mac, choose **Image** to paint or erase on the canvas. Undo/Redo retain up to 100 session changes, including strokes, clears, and imports. **Custom color** opens the native picker for text or the brush. Colors are opaque and quantized to the panel’s 4096 RGB444 combinations.

On iPhone, use **Studio → Image → Draw & edit pixels**. Paint, Erase, Move, zoom, undo/redo, and the native color picker support touch editing; switch to Move to pan a zoomed canvas. Photos import fits an image to the panel. Each bike retains its own draft.

The iPhone **Designs** tab also includes six Halloween templates. Selecting one copies it into the current draft; edit or save a named copy before sending. Template selection never uploads automatically.

## Save and transfer designs

On Mac, **Save design** writes `.iledbike.json`; **Open design** reopens it without sending. **Export pixels** creates a PNG rather than an editable design file.

To transfer a design, save `.iledbike.json` on Mac, send it through AirDrop or Files, then choose **Designs → Import from Files** on iPhone. Import replaces the selected bike’s draft and opens Studio. Save a named library entry if desired, then use the named Send button when ready. Importing does not send. Ordinary images use **Studio → Image → Import photo** after saving to Photos.

## Uploads and double-flash artwork

**Send to panel** on Mac and the named **Send to Bike 1 / Bike 2** button on iPhone update the selected panel. Keep the app open until the upload and settings check finish, then inspect the LEDs and remote.

The Mac option **Use this design in the double-flash slot, too** and iPhone option **Same design when cycling** default on and remember changes across restarts. They replace both ordinary artwork and state 5—the double-flash/hazard slot—with the same design. Every route to that slot then shows the new artwork. This does not remove a firmware mode or change its cycling behavior.

Disabling the option changes only the next upload; it does not restore factory arrows. Existing factory artwork cannot be read back for restoration. The preference is separate from saved designs. Forward, left, right, and brake artwork cannot be overwritten; remote configuration, pairing/settings, reset, and firmware writes remain blocked.

The two artwork uploads are sequential, not atomic. Interruption can leave only one slot updated. Disconnecting or backgrounding cancels the operation without automatic replay. A protocol acknowledgement is not proof that the intended pixels appeared or the physical remote still works.

## iPhone display and signal controls

While connected, use **Studio → [bike name] display → Display on / Display off** to change LED display state without replacing artwork. Off can leave Bluetooth awake and does not turn off the handheld remote; battery savings have not been measured.

Expand **Signals** for **Forward**, **Left**, **Right**, **Brake**, and **My design**. These select existing panel modes; My design returns to ordinary uploaded artwork, not an unsent draft. The display must be on. Remote presses can override the selection.

Both operations use fresh device information and response checks. Keep the app open until verification completes. A timeout can leave the outcome unknown; there is no automatic retry or background control. Detailed command evidence and limits are in [protocol.md](protocol.md).

## Storage and recovery

The phone’s `Documents/BikeLibrary.json` contains profiles, separate drafts, and saved designs. Writes are atomic and protected until first device unlock. Invalid files are preserved with saving blocked instead of overwriting them. Older libraries migrate to neutral profile IDs while retaining names, assignments, and artwork.

Files sharing is enabled for backup/recovery. Export important artwork before removing the app; updating or renewing signing should preserve the existing installation. A discovered panel may still have its LEDs off, so identity, connection, and readiness remain separate checks.
