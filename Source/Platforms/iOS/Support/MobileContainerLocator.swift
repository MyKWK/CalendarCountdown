import CalendarCountdownCore
import Foundation

enum MobileContainerLocator {
    static func appGroupRoot(fileManager: FileManager = .default) throws -> URL {
        try SharedContainer.requiredAppGroupRootURL(fileManager: fileManager)
    }
}
