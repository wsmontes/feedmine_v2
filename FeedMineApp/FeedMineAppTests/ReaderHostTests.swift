//
// File: ReaderHostTests.swift
// Module: FeedMineAppTests
//
// The reader host's own presentation, proved in process: one page at a time, one presentation of it, the sheet
// style that makes it draggable, the one finish route (close control, the sheet's own drag, the page's pull-down)
// and the question of whether the reader is up answered only by what the platform reported. The platform acts are
// replaced by a double because a presentation that is refused leaves no trace — UIKit raises no error and calls no
// completion — so nothing else can exercise the refusal that left the reader's close and its site controls wired
// to nothing.
//
// Round 11 also proves two things that are not presentation: a page load is identified by the address the surface
// was given (a redirect does not restart the article) and the pull-down rule is a single shared threshold.
import XCTest
import SwiftUI
import WebKit
import FeedMineUI
@testable import FeedMine

private typealias Host = FeedMineApp.ReaderHost
private typealias Page = FeedMineApp.ReaderPage
private typealias Notice = FeedMineApp.LegacyUpgradeNoticePresenter

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
        /// The page's own top-state report, exactly what the host hands the page for the sheet's drag rule.
        var reportTop: ((Bool) -> Void)?
        var finishes = 0
        var pages: [Page] = []
    }

    private func reader(_ recorder: Recorder)
        -> (Page, @escaping () -> Void, @escaping (Bool) -> Void) -> AnyView {
        { page, close, atTop in
            recorder.pages.append(page)
            recorder.close = close
            recorder.reportTop = atTop
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

    /// V1's reader model, restated as the rule: the site is a page of the **same** sheet, not a second modal
    /// presentation. The controller that is up draws it, the app keeps one reader level, and closing it returns to
    /// the surface the reader was opened from.
    func testTheSitePageIsDrawnByTheSameReaderSheet() async {
        let platform = PlatformDouble()
        let recorder = Recorder()
        let coordinator = coordinator(platform, recorder)

        coordinator.show(.local(Self.content))
        await waitUntil { platform.up != nil }
        guard let readerController = platform.up else { return XCTFail("the reader went up") }

        coordinator.show(.site(Self.url))
        await waitUntil { recorder.pages.count == 2 }

        XCTAssertEqual(platform.attempts.count, 1, "the site is not a second presentation")
        XCTAssertTrue(platform.up === readerController, "the sheet that is up is the sheet that draws the site")
        XCTAssertEqual(platform.dismissals.count, 0, "and nothing was taken down to get there")
        guard case .site(let url) = recorder.pages.last else {
            return XCTFail("the page the app has is the one the sheet draws")
        }
        XCTAssertEqual(url, Self.url)
    }

    /// The presentation the reader is given: a draggable page sheet — one large detent, the system grabber, and
    /// not modal-in-presentation, so the platform's own drag can end it. The style is asserted on the controller
    /// the host really built, not on a value a test could agree with without the screen agreeing too.
    func testTheReaderIsADraggablePageSheetWithAGrabber() async {
        let platform = PlatformDouble()
        let coordinator = coordinator(platform, Recorder())

        coordinator.show(.local(Self.content))
        await waitUntil { platform.up != nil }
        guard let controller = platform.up else { return XCTFail("the reader went up") }

        XCTAssertEqual(controller.modalPresentationStyle, .pageSheet,
            "the reader is a sheet, not a full-screen presentation")
        XCTAssertFalse(controller.isModalInPresentation,
            "the platform's own drag is allowed to end it")
        XCTAssertEqual(controller.overrideUserInterfaceStyle, .light,
            "the legibility declaration travels with the presentation")
        guard let sheet = controller.sheetPresentationController else {
            return XCTFail("a page sheet has a sheet presentation controller")
        }
        XCTAssertEqual(sheet.detents.count, 1)
        XCTAssertEqual(sheet.detents.first?.identifier, .large,
            "one large detent: the reader is a page, not a peek")
        XCTAssertTrue(sheet.prefersGrabberVisible, "the grabber is the visible affordance")
    }

    /// The sheet's own drag reports through the presentation delegate. That report is the reader's finish: it
    /// reaches the app once, and the app's own state afterwards asks the platform for nothing — the controller is
    /// already dismissed, and a second transition would fight the one the reader just made.
    func testTheSheetsOwnDragFinishesTheReaderOnceAndTheStateAsksForNothingMore() async {
        let platform = PlatformDouble()
        let recorder = Recorder()
        let coordinator = coordinator(platform, recorder)

        coordinator.show(.local(Self.content))
        await waitUntil { platform.up != nil }
        guard let controller = platform.up else { return XCTFail("the reader went up") }

        let presentation = UIPresentationController(presentedViewController: controller, presenting: nil)
        coordinator.presentationControllerDidDismiss(presentation)
        XCTAssertEqual(recorder.finishes, 1, "the drag ends the reader once")

        coordinator.show(nil)
        XCTAssertEqual(recorder.finishes, 1, "the app's state does not finish it a second time")
        XCTAssertEqual(platform.dismissals.count, 0,
            "and the platform is not asked to dismiss a controller that already went down")
    }

    /// A presentation the platform refuses must not strand the page: the host makes the attempt again, on the
    /// platform's own report, instead of believing a reader is up that never went up and then never asking again.
    func testARefusedPresentationIsMadeAgainInsteadOfStrandingThePage() async {
        let platform = PlatformDouble(refusals: 1)
        let coordinator = coordinator(platform, Recorder())

        coordinator.show(.local(Self.content))
        await waitUntil { platform.up != nil }

        XCTAssertGreaterThanOrEqual(platform.attempts.count, 1, "the platform was asked to present the reader")
        XCTAssertTrue(platform.attempts.count >= 2,
            "the refused presentation is made again instead of the page staying unshowable")
        XCTAssertTrue(platform.up === platform.attempts.last,
            "and what went up is the controller the host built, not a second one")
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

        coordinator.show(.local(Self.otherContent))
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

        coordinator.show(.local(Self.content))
        await waitUntil { platform.up != nil }

        recorder.close?()
        XCTAssertEqual(recorder.finishes, 1, "the close control reports back to the app")
        XCTAssertEqual(platform.dismissals.count, 0, "and nothing is dismissed behind the app's back")

        coordinator.show(nil)
        XCTAssertEqual(platform.dismissals.count, 1, "the app's own state took the reader down")
        XCTAssertNil(platform.up, "and nothing is up afterwards")
        // The finish was already reported by the close control; the state change does not report it again.
        XCTAssertEqual(recorder.finishes, 1, "the finish is reported once, whatever route reached it")
        coordinator.show(nil)
        XCTAssertEqual(platform.dismissals.count, 1, "a repeated state change asks for nothing")
    }

    /// The on-screen reader's controls report to the closures the app has *now*: the host view is rebuilt with the
    /// app's body while its coordinator stays, so an unrefreshed host leaves the control it drew reporting to a
    /// state that has moved on.
    func testTheCloseControlReportsToTheClosuresTheHostHasNow() async {
        let platform = PlatformDouble()
        let first = Recorder()
        let coordinator = coordinator(platform, first)
        coordinator.show(.local(Self.content))
        await waitUntil { first.close != nil }

        let second = Recorder()
        coordinator.refresh(reader: reader(second), onFinish: { second.finishes += 1 })
        coordinator.show(.local(Self.otherContent))

        XCTAssertNotNil(second.close, "the reader drawn now is built by the closures the host has now")
        second.close?()
        XCTAssertEqual(second.finishes, 1, "and its close reports to the app as it is now")
    }

    /// A redirect changes the browser's own address. That address is the *result* of a load, never an input:
    /// a later render must not load the article again because of it. V1 had this defect, fixed with the same rule.
    func testARedirectDoesNotRestartTheArticle() async {
        let webView = WKWebView()
        let coordinator = ReaderWebContainer.Coordinator()
        var loads: [ReaderWebRequest] = []
        coordinator.requestLoader = { _, request in loads.append(request) }
        let request = ReaderWebRequest(url: Self.url)

        coordinator.apply(request, to: webView)
        XCTAssertEqual(loads, [request], "the first render starts the load")

        // The browser follows the request somewhere else. One runloop turn is enough for the web view to own a
        // new URL; whether it does is not the point — the identity under test is the requested address.
        webView.loadHTMLString("<p>redirected</p>",
            baseURL: URL(string: "https://redirected.example/final"))
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline, webView.url?.host != "redirected.example" {
            try? await Task.sleep(for: .milliseconds(20))
        }

        coordinator.apply(request, to: webView)
        XCTAssertEqual(loads.count, 1, "the same request is not loaded again after a redirect")

        coordinator.apply(ReaderWebRequest(url: Self.url, attempt: 1), to: webView)
        XCTAssertEqual(loads.count, 2, "a retry the reader asked for is an explicit new attempt")
        XCTAssertEqual(loads.last?.attempt, 1)
    }

    /// The pull-down rule is one value, shared by the text page and the publisher's page. The negative cases are
    /// the ones the product promised: a page scrolled down does not dismiss, a bounce after release does not, and
    /// a sideways swipe does not.
    func testThePullDownRuleIsOneSharedThreshold() {
        XCTAssertEqual(ReaderSheetPullDown.dismissalDistance, 80)
        XCTAssertTrue(ReaderSheetPullDown.dismisses(startedAtTop: true, isTracking: true, verticalPull: 80),
            "a deliberate pull at the top dismisses")
        XCTAssertFalse(ReaderSheetPullDown.dismisses(startedAtTop: true, isTracking: true, verticalPull: 79.9),
            "a stray bounce does not")
        XCTAssertFalse(ReaderSheetPullDown.dismisses(startedAtTop: true, isTracking: false, verticalPull: 400),
            "nothing counts once the finger is up")
        XCTAssertFalse(ReaderSheetPullDown.dismisses(startedAtTop: false, isTracking: true, verticalPull: 400),
            "a page scrolled down does not dismiss when the drag reaches the top")
        XCTAssertFalse(ReaderSheetPullDown.dismisses(startedAtTop: true, isTracking: true,
            verticalPull: 90, horizontalPull: 80), "a diagonal swipe is not a pull")

        XCTAssertEqual(ReaderSheetPullDown.pull(contentOffsetY: -140, topInset: 60), 80,
            "rest is -topInset; what is beyond it is the pull")
        XCTAssertEqual(ReaderSheetPullDown.pull(contentOffsetY: 300, topInset: 60), 0,
            "a page scrolled down has no pull")
        XCTAssertTrue(ReaderSheetPullDown.isAtTop(contentOffsetY: -60, topInset: 60))
        XCTAssertFalse(ReaderSheetPullDown.isAtTop(contentOffsetY: -30, topInset: 60))
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
    /// Every opener context the product offers is covered: sources, bookmark boxes and collections.
    func testAReaderRequestReplacesThePageThatIsUpInsteadOfAddingALevel() {
        for opener in [FeedMineApp.SheetSurface.sources, .bookmarkBoxes, .collections] {
            let overASheet = FeedMineApp.pushingReader(.local(Self.content), onto: [.sheet(opener)])
            XCTAssertEqual(overASheet.count, 2, "the reader is a level over the surface that asked for it")
            guard case .reader(.local)? = overASheet.last else { return XCTFail("the reader is what is up") }

            let replaced = FeedMineApp.pushingReader(.site(Self.url), onto: overASheet)
            XCTAssertEqual(replaced.count, 2,
                "a page the chrome asks for replaces that reader, it does not stack")
            guard case .reader(.site(let url))? = replaced.last else {
                return XCTFail("the site is what is up")
            }
            XCTAssertEqual(url, Self.url)
            guard case .sheet(let kept)? = replaced.first else {
                return XCTFail("and the surface the reader was opened from is still there to return to")
            }
            XCTAssertEqual(kept.id, opener.id, "the opener keeps its own identity and its own list")
        }

        guard case .reader(.site)? = FeedMineApp.pushingReader(.site(Self.url), onto: []).last else {
            return XCTFail("with no reader up, the reader is pushed over the feed")
        }
    }

    /// The platform's own drag obeys the product rule, through the page's own report: at the top it dismisses;
    /// scrolled down it does not, and the reader keeps reading. A re-render of the same page (a playback tick, a
    /// feed advance) must not re-arm the drag — that would dismiss a reader who is deep in the article.
    func testAScrolledPageRefusesTheSheetsDragAndATopPageAllowsIt() async {
        let platform = PlatformDouble()
        let recorder = Recorder()
        let coordinator = coordinator(platform, recorder)

        coordinator.show(.local(Self.content))
        await waitUntil { platform.up != nil }
        guard let controller = platform.up else { return XCTFail("the reader went up") }
        let presentation = UIPresentationController(presentedViewController: controller, presenting: nil)

        XCTAssertTrue(coordinator.presentationControllerShouldDismiss(presentation),
            "a page at its top may be dismissed by the sheet's own drag")

        recorder.reportTop?(false)
        XCTAssertFalse(coordinator.presentationControllerShouldDismiss(presentation),
            "a page scrolled down scrolls instead of dismissing")

        coordinator.show(.local(Self.content))
        XCTAssertFalse(coordinator.presentationControllerShouldDismiss(presentation),
            "a re-render of the page that is up does not reset where the reader is in it")

        recorder.reportTop?(true)
        XCTAssertTrue(coordinator.presentationControllerShouldDismiss(presentation),
            "back at the top, the drag dismisses again")
    }

    private static let content = FeedReadingContent(origin: .sourceBody, sourceName: "BBC",
        headline: "A stored body", publishedAt: nil,
        text: "Parágrafo 1: o texto que a fonte publicou para este artigo.",
        siteURL: URL(string: "https://example.test/article"), isPartial: true)

    private static let otherContent = FeedReadingContent(origin: .sourceBody, sourceName: "BBC",
        headline: "Another stored body", publishedAt: nil,
        text: "Parágrafo 2: outro texto que a fonte publicou.",
        siteURL: URL(string: "https://example.test/other"), isPartial: true)
}

/// D7-A: the notice's own window is the one app surface above a full-screen reader. A refused alert leaves that
/// window as an invisible, full-screen shell that takes every touch in the app — the reader's own close and site
/// controls included. The platform act is doubled for the refusal, exactly as the reader's presentation is: a
/// working screen cannot stage it.
@MainActor
final class NoticeWindowTests: XCTestCase {
    private func alertLevelWindows() -> [UIWindow] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { $0.windowLevel == .alert + 1 && !$0.isHidden }
    }

    private func waitUntil(_ condition: @escaping () -> Bool, seconds: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// A presentation the platform refuses raises no error and calls no completion. The window it was going to
    /// show must not survive that refusal: leaving it visible is leaving the whole app inert.
    func testARefusedAlertLeavesNoWindowToTakeEveryTouch() async {
        Notice.dismiss()
        var attempts = 0
        let original = Notice.presentAlert
        defer {
            Notice.presentAlert = original
            Notice.dismiss()
        }
        Notice.presentAlert = { _, _, done in
            attempts += 1
            XCTAssertTrue(Thread.isMainThread, "the platform act runs on the main actor")
            done(false)
        }

        Notice.present(title: "Da versão anterior", message: "Importados") {}
        await waitUntil { self.alertLevelWindows().isEmpty }

        XCTAssertTrue(alertLevelWindows().isEmpty,
            "a visible alert-level window with no alert takes every touch in the app")

        // The refused window is gone and the presenter is free again: the next notice really gets a new window
        // and a new platform act. A stale `current` would make a second notice a silent no-op in production.
        Notice.present(title: "Da versão anterior", message: "Importados") {}
        await waitUntil { attempts == 2 }
        XCTAssertEqual(attempts, 2, "a second notice is attempted after the refused one")
        XCTAssertTrue(alertLevelWindows().isEmpty, "and its refusal is taken down too")
    }

    /// The only gesture that ends the notice: the action the alert's Entendi runs is the same route tested here.
    /// It must take the window down and record exactly one acknowledgement.
    func testTheAcknowledgementEndsTheNoticeAndRecordsIt() async {
        Notice.dismiss()
        let original = Notice.presentAlert
        defer {
            Notice.presentAlert = original
            Notice.dismiss()
        }
        Notice.presentAlert = { _, _, done in done(true) }
        var acknowledged = 0

        Notice.present(title: "Da versão anterior", message: "Importados") { acknowledged += 1 }
        await waitUntil { !self.alertLevelWindows().isEmpty }
        Notice.acknowledge()

        XCTAssertEqual(acknowledged, 1, "the notice's own route records the acknowledgement once")
        XCTAssertTrue(alertLevelWindows().isEmpty, "and the notice window is gone")
    }

    /// The composition on the platform in use: the alert is really up in the notice's own window, and that window
    /// never takes key status away from the app's own window.
    func testTheNoticeAlertIsReallyRaisedInItsOwnWindow() async {
        defer { Notice.dismiss() }
        Notice.present(title: "Da versão anterior", message: "Importados") {}
        await waitUntil { !self.alertLevelWindows().isEmpty }
        guard let window = alertLevelWindows().last else {
            return XCTFail("the notice window was raised")
        }
        XCTAssertNotNil(window.rootViewController?.presentedViewController as? UIAlertController,
            "the visible notice window is showing its alert, not an empty shell")
        XCTAssertFalse(window.isKeyWindow, "the notice does not take key away from the app")
    }
}

/// A surface that reports the controller it has up, as UIKit's own property does: the state a real window can
/// only be put in by a transition, which is what this test cannot stage.
@MainActor
private final class SurfaceDouble: UIViewController {
    var has: UIViewController?
    override var presentedViewController: UIViewController? { has }
}
