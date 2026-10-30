//
// File: ReaderHostTests.swift
// Module: FeedMineAppTests
//
// The reader host's own presentation, proved in process: one page at a time, one presentation of it, and the
// question of whether the reader is up answered only by what the platform reported. The platform acts are
// replaced by a double because a presentation that is refused leaves no trace — UIKit raises no error and calls
// no completion — so nothing else can exercise the refusal that left the reader's close and its two site
// controls wired to nothing.
//
// The four cases below are the measured defects and the rule the fix chose: a refused `present` stranding a page
// for the life of the process, a dismissal skipped because the controller reported no `presentingViewController`,
// a page the reader's chrome asks for stacked as a second presentation, and a close control reporting to the
// closures the host was built with instead of the ones the app has now.
import XCTest
import SwiftUI
import FeedMineUI
@testable import FeedMine

private typealias Host = FeedMineApp.ReaderHost
private typealias Page = FeedMineApp.ReaderPage

@MainActor
final class ReaderHostTests: XCTestCase {
    private static let url = URL(string: "https://example.test/article")!

    /// The platform the host acts on, replaced: it records what it was asked for, and it can refuse a
    /// presentation. `up` is the double's own account of the outcome — the same fact the real presentation
    /// reports, which is the whole point of the seam.
    @MainActor
    private final class PlatformDouble: Host.Presentation {
        /// How many attempts are refused before one is taken.
        private var refusals: Int
        private(set) var attempts: [UIViewController] = []
        private(set) var dismissals: [UIViewController] = []
        private(set) var up: UIViewController?

        init(refusals: Int = 0) { self.refusals = refusals }

        func present(_ reader: UIViewController, done: @escaping (Bool) -> Void) {
            attempts.append(reader)
            guard refusals == 0 else {
                refusals -= 1
                done(false)
                return
            }
            up = reader
            done(true)
        }

        func dismiss(_ reader: UIViewController) {
            dismissals.append(reader)
            if up === reader { up = nil }
        }
    }

    /// Where the reader's own chrome ends up: the content the host builds is the test's, so the close control it
    /// is handed — exactly what `reading.close` calls — is kept where the assertions can reach it.
    @MainActor
    private final class Recorder {
        var close: (() -> Void)?
        var finishes = 0
        var pages: [Page] = []
    }

    private func reader(_ recorder: Recorder) -> (Page, @escaping () -> Void) -> AnyView {
        { page, close in
            recorder.pages.append(page)
            recorder.close = close
            return AnyView(Text(verbatim: "reader"))
        }
    }

    private func coordinator(_ platform: PlatformDouble, _ recorder: Recorder) -> Host.Coordinator {
        Host.Coordinator(platform: platform, reader: reader(recorder),
            onFinish: { recorder.finishes += 1 })
    }

    /// The host presents on its own turn of the main actor, so a run that has just asked for a page waits for the
    /// platform to be told instead of assuming it happened in the same statement.
    private func waitUntil(_ condition: @escaping () -> Bool, seconds: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// A presentation the platform refuses must not strand the page: the host makes the attempt again, on the
    /// platform's own report, instead of believing a reader is up that never went up and then never asking again.
    func testARefusedPresentationIsMadeAgainInsteadOfStrandingThePage() async {
        let platform = PlatformDouble(refusals: 1)
        let coordinator = coordinator(platform, Recorder())

        coordinator.show(.site(Self.url))
        await waitUntil { platform.up != nil }

        XCTAssertGreaterThanOrEqual(platform.attempts.count, 1, "the platform was asked to present the reader")
        XCTAssertTrue(platform.attempts.count >= 2,
            "the refused presentation is made again instead of the page staying unshowable")
        XCTAssertTrue(platform.up === platform.attempts.last,
            "and what went up is the controller the host built, not a second one")
    }

    /// The reader is opaque, but the presenting feed must remain mounted behind it.
    /// UIKit removes the presenting view hierarchy for .fullScreen. Retaining that hierarchy
    /// prevents one source of native ScrollView teardown/re-attachment on browser close.
    func testOpaqueReaderRetainsPresentingFeedHierarchy() async {
        let platform = PlatformDouble()
        let coordinator = coordinator(platform, Recorder())

        coordinator.show(.site(Self.url))
        await waitUntil { platform.up != nil }
        guard let controller = platform.up else { return XCTFail("the browser reader was not presented") }
        XCTAssertEqual(controller.modalPresentationStyle, .overFullScreen,
            "a fullScreen reader can detach the presenting SwiftUI ScrollView")
        XCTAssertEqual(controller.view.backgroundColor, UIColor.systemBackground,
            "the reader must stay opaque even though the feed remains mounted")
    }

    /// The reader is one presentation. A page its own chrome asks for — the site, from the text the app holds —
    /// changes what that one presentation draws; it is never presented as a second one, which would leave the
    /// controller underneath outliving the app state that put it there.
    func testAPageTheReadersChromeAsksForIsDrawnByTheSamePresentation() async {
        let platform = PlatformDouble()
        let recorder = Recorder()
        let coordinator = coordinator(platform, recorder)

        coordinator.show(.local(Self.content))
        await waitUntil { platform.up != nil }
        guard let first = platform.up else { return XCTFail("the reader went up") }

        coordinator.show(.site(Self.url))
        await waitUntil { recorder.pages.count == 2 }
        // The turn a second presentation would have taken, so "it was not presented" is observed rather than
        // assumed from the order of the statements above.
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(platform.attempts.count, 1, "the second page is not a second presentation")
        XCTAssertTrue(platform.up === first, "the reader that is up is the reader that draws the page now")
        XCTAssertEqual(platform.dismissals.count, 0, "and nothing was taken down to get there")
        XCTAssertEqual(recorder.pages.count, 2, "the content was rebuilt for the page the app has now")
    }

    /// The reader's own close reports back to the app — it never dismisses anything behind the app's back — and
    /// when the app's state says the reader is no longer up, the platform is asked to take it down. Inferring
    /// that dismissal from the controller's own `presentingViewController` skipped it on exactly the controller a
    /// refused presentation leaves behind, and the reader stayed on screen with nothing behind it.
    func testClosingTheReaderAsksThePlatformToTakeItDown() async {
        let platform = PlatformDouble()
        let recorder = Recorder()
        let coordinator = coordinator(platform, recorder)

        coordinator.show(.site(Self.url))
        await waitUntil { platform.up != nil }

        recorder.close?()
        XCTAssertEqual(recorder.finishes, 1, "the close control reports back to the app")
        XCTAssertEqual(platform.dismissals.count, 0, "and nothing is dismissed behind the app's back")

        coordinator.show(nil)
        XCTAssertEqual(platform.dismissals.count, 1, "the app's own state took the reader down")
        XCTAssertNil(platform.up, "and nothing is up afterwards")
    }

    /// The on-screen reader's controls report to the closures the app has *now*: the host view is rebuilt with the
    /// app's body while its coordinator stays, so an unrefreshed host leaves the control it drew reporting to a
    /// state that has moved on.
    func testTheCloseControlReportsToTheClosuresTheHostHasNow() async {
        let platform = PlatformDouble()
        let first = Recorder()
        let coordinator = coordinator(platform, first)
        coordinator.show(.site(Self.url))
        await waitUntil { first.close != nil }

        let second = Recorder()
        coordinator.refresh(reader: reader(second), onFinish: { second.finishes += 1 })
        coordinator.show(.site(Self.url))

        XCTAssertNotNil(second.close, "the reader drawn now is built by the closures the host has now")
        second.close?()
        XCTAssertEqual(second.finishes, 1, "and its close reports to the app as it is now")
    }

    /// Only a surface that really has the reader is asked to take it down. A controller whose presentation was
    /// refused reports no `presentingViewController`; the surface the attempt was made from is the fallback only
    /// while that surface really has this reader, so a surface with something else up is left alone.
    func testTheSurfaceAskedToTakeTheReaderDownIsTheOneThatReallyHasIt() {
        let reader = UIViewController()
        let presenter = SurfaceDouble()
        XCTAssertNil(Host.WindowReaderPresentation.owner(of: reader, presentedFrom: nil),
            "no presenting surface and no remembered one: there is nothing to take down")
        XCTAssertNil(Host.WindowReaderPresentation.owner(of: reader, presentedFrom: presenter),
            "a surface with nothing of this reader's up is not asked either")
        presenter.has = reader
        XCTAssertTrue(Host.WindowReaderPresentation.owner(of: reader, presentedFrom: presenter) === presenter,
            "while a transition is in flight, the surface the attempt was made from is what has it up")
    }

    /// The rule the reader's own close depends on: a page the chrome asks for while a reader is up replaces that
    /// reader, and the surface it was opened from — the feed, or the list inside a sheet — is what it returns to.
    func testAReaderRequestReplacesThePageThatIsUpInsteadOfAddingALevel() {
        let overASheet = FeedMineApp.pushingReader(.local(Self.content), onto: [.sheet(.sources)])
        XCTAssertEqual(overASheet.count, 2, "the reader is a level over the surface that asked for it")
        guard case .reader(.local)? = overASheet.last else { return XCTFail("the reader is what is up") }

        let replaced = FeedMineApp.pushingReader(.site(Self.url), onto: overASheet)
        XCTAssertEqual(replaced.count, 2, "a page the chrome asks for replaces that reader, it does not stack")
        guard case .reader(.site(let url))? = replaced.last else { return XCTFail("the site is what is up") }
        XCTAssertEqual(url, Self.url)
        guard case .sheet(.sources)? = replaced.first else {
            return XCTFail("and the surface the reader was opened from is still there to return to")
        }

        guard case .reader(.site)? = FeedMineApp.pushingReader(.site(Self.url), onto: []).last else {
            return XCTFail("with no reader up, the reader is pushed over the feed")
        }
    }

    private static let content = FeedReadingContent(origin: .sourceBody, sourceName: "BBC",
        headline: "A stored body", publishedAt: nil,
        text: "Parágrafo 1: o texto que a fonte publicou para este artigo.",
        siteURL: URL(string: "https://example.test/article"), isPartial: true)
}

/// A surface that reports the controller it has up, as UIKit's own property does: the state a real window can
/// only be put in by a transition, which is what this test cannot stage.
@MainActor
private final class SurfaceDouble: UIViewController {
    var has: UIViewController?
    override var presentedViewController: UIViewController? { has }
}
