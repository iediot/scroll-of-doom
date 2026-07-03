#if os(iOS)
import SwiftUI

/// Root of the game UI — vertical snap-paging feed where each page is a level.
/// Scroll direction: swipe up = next level (mimics TikTok feed).
struct FeedView: View {

    // TODO: replace fixed count with a real level manifest
    private let levelCount = 5

    /// Set by a page's on-screen controls: while a control is held, paging is
    /// disabled so the drag drives the game instead of scrolling the feed.
    @State private var scrollLocked = false

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(0..<levelCount, id: \.self) { index in
                    LevelPageView(levelIndex: index, scrollLocked: $scrollLocked)
                        .containerRelativeFrame([.horizontal, .vertical])
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollDisabled(scrollLocked)
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}

#Preview {
    FeedView()
}
#endif
