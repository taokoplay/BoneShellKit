/// How a tab chooses and renders its icon while selected.
public enum ShellTabSelectedIconMode: String, CaseIterable, Sendable {
    /// Preserve the existing selected-icon and rendering-mode behavior.
    case automatic
    /// Keep the normal artwork and apply the current selected color.
    case selectedColor
    /// Keep the selected artwork's original colors and transparency; fall back to the normal icon.
    case selectedImage
}
