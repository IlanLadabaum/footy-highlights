#if os(macOS)
    import AppKit

    /// Single-letter shortcuts (no modifier keys) for the player: T for the table, I for the mini player.
    /// They're picked so they don't clash with YouTube's own player keys (k, j, l, f, m, c, 0–9, <, >).
    enum PlainKey {
        /// The letter typed, when it's pressed without modifiers and not into a text field; nil otherwise.
        static func letter(_ event: NSEvent) -> String? {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .numericPad, .function])
            guard modifiers.isEmpty, !event.isARepeat else { return nil }
            if let text = event.window?.firstResponder as? NSTextView, text.isEditable { return nil }
            return event.charactersIgnoringModifiers?.lowercased()
        }
    }
#endif
