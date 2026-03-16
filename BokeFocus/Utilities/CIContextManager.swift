import CoreImage

/// Shared CIContext — created once at launch, reused throughout
final class CIContextManager {
    static let shared = CIContextManager()
    let context: CIContext

    private init() {
        context = CIContext(options: [.useSoftwareRenderer: false])
    }
}
