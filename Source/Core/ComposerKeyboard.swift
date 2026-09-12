import Foundation

public enum ComposerReturnAction: Equatable, Sendable {
    case insertNewline
    case submit

    /// A multi-line editor must behave like a document editor: Return creates a
    /// paragraph. Saving is an explicit action (or Command-Return on macOS).
    public static func fromReturn(commandPressed: Bool) -> ComposerReturnAction {
        commandPressed ? .submit : .insertNewline
    }
}
