#if os(macOS)
    import AppKit
    import FootyKit
    import SwiftUI

    /// The mini player: a small floating window holding the same YouTube player, so the viewer can browse
    /// while it plays. Resizable from any edge (16:9 kept) and movable anywhere; its frame is remembered.
    /// Nothing is drawn over the video: the app's buttons sit in a bar below it.
    @MainActor
    final class MiniPlayerWindow: NSObject, NSWindowDelegate {
        static let shared = MiniPlayerWindow()

        static let barHeight: CGFloat = 34
        /// YouTube requires an embedded player of at least 200×200; 16:9 at 200 high.
        static let minVideoSize = NSSize(width: 356, height: 200)
        static let pinnedKey = "miniPlayer.pinned"

        #if DEBUG
            /// `--mini-test`: keep the window offscreen and don't save its frame.
            static var offscreenForTesting = false
            var testPanel: NSPanel? { panel }
        #endif

        private var panel: NSPanel?
        private weak var model: AppModel?

        /// Keep the mini player above other apps (the pin on its bar). On by default.
        var isPinned: Bool {
            get { UserDefaults.standard.object(forKey: Self.pinnedKey) as? Bool ?? true }
            set {
                UserDefaults.standard.set(newValue, forKey: Self.pinnedKey)
                applyPin()
            }
        }

        /// Moves the current playback into the mini player and returns the main window to browsing.
        func show(model: AppModel) {
            guard let session = model.playback else { return }
            self.model = model
            session.isMini = true
            let panel = panel ?? makePanel()
            self.panel = panel
            // A fresh hosting view each time, so its player view adopts the web view from the player screen.
            panel.contentView = NSHostingView(
                rootView: MiniPlayerView(session: session, window: self).environment(model))
            applyPin()
            panel.orderFront(nil)
            if model.path.last == session.route { model.path.removeLast() }
        }

        /// Back to the full player screen, still playing.
        func expand() {
            guard let model, let session = model.playback else { return close() }
            session.isMini = false
            hide()
            if model.path.last != session.route { model.path.append(session.route) }
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0 !== panel && $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        }

        /// Stops the video and closes the mini player.
        func close() {
            if let model, let session = model.playback, session.isMini {
                session.stop()
                model.playback = nil
            }
            hide()
        }

        /// Hides the window without stopping anything (the player moved elsewhere).
        func hide() {
            panel?.contentView = nil
            panel?.orderOut(nil)
        }

        private func makePanel() -> NSPanel {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 270 + Self.barHeight),
                styleMask: [.titled, .closable, .resizable, .utilityWindow],
                backing: .buffered, defer: false)
            panel.title = "Mini Player"
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.contentMinSize = NSSize(
                width: Self.minVideoSize.width, height: Self.minVideoSize.height + Self.barHeight)
            panel.delegate = self
            #if DEBUG
                if Self.offscreenForTesting {
                    panel.setFrameOrigin(NSPoint(x: -5000, y: -5000))
                    return panel
                }
            #endif
            if !panel.setFrameUsingName("MiniPlayer"), let screen = NSScreen.main?.visibleFrame {
                // First time: bottom-right corner of the screen.
                panel.setFrameOrigin(NSPoint(x: screen.maxX - panel.frame.width - 20, y: screen.minY + 20))
            }
            panel.setFrameAutosaveName("MiniPlayer")
            return panel
        }

        private func applyPin() {
            guard let panel else { return }
            panel.level = isPinned ? .floating : .normal
            panel.collectionBehavior = isPinned ? [.fullScreenAuxiliary, .canJoinAllSpaces] : []
        }

        // MARK: NSWindowDelegate

        /// Keeps the video 16:9 (plus the bar) whichever edge is dragged.
        func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
            let content = sender.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize))
            let width = max(content.width, Self.minVideoSize.width)
            let height = (width * 9 / 16).rounded() + Self.barHeight
            return sender.frameRect(forContentRect: NSRect(x: 0, y: 0, width: width, height: height)).size
        }

        /// The title bar's close button: same as Close.
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            close()
            return false
        }
    }

    /// The mini player's content: the video, then the app's bar below it.
    struct MiniPlayerView: View {
        let session: PlaybackSession
        let window: MiniPlayerWindow
        @State private var pinned = MiniPlayerWindow.shared.isPinned

        var body: some View {
            VStack(spacing: 0) {
                ZStack {
                    Color.black
                    switch session.controller.phase {
                    case .finished:
                        Text(session.mode == .queue ? "Queue finished" : "Finished").foregroundStyle(.white)
                    case .failed:
                        Text("Couldn't play this video. Expand for options.")
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding()
                    default:
                        PlayerWebViewRepresentable(controller: session.controller)
                    }
                }
                .frame(minWidth: MiniPlayerWindow.minVideoSize.width, minHeight: MiniPlayerWindow.minVideoSize.height)
                HStack(spacing: 12) {
                    Button {
                        window.expand()
                    } label: {
                        Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .help("Back to the full player")
                    Spacer()
                    Toggle(isOn: $pinned) {
                        Label("Keep on top", systemImage: pinned ? "pin.fill" : "pin")
                    }
                    .toggleStyle(.button)
                    .help("Keep the mini player above other apps")
                    .onChange(of: pinned) { _, value in window.isPinned = value }
                    Button {
                        window.close()
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                    .help("Stop the video and close the mini player")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .padding(.horizontal, 12)
                .frame(height: MiniPlayerWindow.barHeight)
                .background(.bar)
            }
        }
    }
#endif
