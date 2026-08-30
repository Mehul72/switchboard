import SwiftUI
#if canImport(Translation)
import Translation
#endif

extension View {
    /// Translation is macOS 15 and later. Below that, captured text is copied
    /// exactly as it was read.
    @ViewBuilder
    func translationBridge(_ store: TweakStore) -> some View {
        #if canImport(Translation)
        if #available(macOS 15.0, *) {
            modifier(TranslationBridge(store: store))
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#if canImport(Translation)
/// The Translation framework only vends a session from inside this SwiftUI
/// modifier, so the popover carries an invisible bridge the store can drive.
@available(macOS 15.0, *)
struct TranslationBridge: ViewModifier {
    @ObservedObject var store: TweakStore

    /// Held in state on purpose. Building the configuration inside `body`
    /// makes a new one on every redraw, and each new configuration restarts
    /// the task and cancels the translation already in flight.
    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .onChange(of: store.pendingTranslation) { _, pending in
                guard let pending else {
                    configuration = nil
                    return
                }
                configuration = TranslationSession.Configuration(
                    source: pending.source,
                    target: Locale.Language(identifier: "en")
                )
            }
            .translationTask(configuration) { session in
                await translate(with: session)
            }
    }

    private func translate(with session: TranslationSession) async {
        guard let pending = store.pendingTranslation else { return }
        do {
            // Downloads the language pair the first time it is needed, showing
            // the system's own progress rather than failing silently.
            try await session.prepareTranslation()
            let response = try await session.translate(pending.text)
            await store.finishTranslation(response.targetText, from: pending.source, failure: nil)
        } catch is CancellationError {
            // A newer capture superseded this one; its own task reports back.
            return
        } catch {
            await store.finishTranslation(nil, from: pending.source,
                                          failure: error.localizedDescription)
        }
    }
}
#endif
