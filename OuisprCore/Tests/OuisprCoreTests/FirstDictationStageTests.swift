import XCTest
@testable import OuisprCore

final class FirstDictationStageTests: XCTestCase {

    // MARK: - The states (#678, #845)

    func testAnUnfocusedFieldHasNoKeyboard() {
        XCTAssertEqual(FirstDictationStage(isFieldFocused: false, isOuisprKeyboard: false, isAwaitingAutoFocus: false), .beforeTap)
        // The input mode an unfocused text view reports is the last one it had, not one on
        // screen: it must not light the Ouispr banner.
        XCTAssertEqual(FirstDictationStage(isFieldFocused: false, isOuisprKeyboard: true, isAwaitingAutoFocus: false), .beforeTap)
    }

    func testWhileTheAutoFocusIsPendingTheKeyboardIsOpening() {
        XCTAssertEqual(FirstDictationStage(isFieldFocused: false, isOuisprKeyboard: false, isAwaitingAutoFocus: true), .opening)
        XCTAssertEqual(FirstDictationStage(isFieldFocused: false, isOuisprKeyboard: true, isAwaitingAutoFocus: true), .opening)
    }

    func testAFocusedFieldShowsTheKeyboardThatIsUp() {
        for awaiting in [false, true] {
            XCTAssertEqual(FirstDictationStage(isFieldFocused: true, isOuisprKeyboard: false, isAwaitingAutoFocus: awaiting), .otherKeyboard)
            XCTAssertEqual(FirstDictationStage(isFieldFocused: true, isOuisprKeyboard: true, isAwaitingAutoFocus: awaiting), .ouisprKeyboard)
        }
    }

    // MARK: - Auto-focus fallback, 1 s (#845)

    func testTheAutoFocusIsStillAwaitedBeforeOneSecond() {
        XCTAssertFalse(FirstDictationStage.autoFocusHasFailed(secondsSinceRequest: 0, isFieldFocused: false))
        XCTAssertFalse(FirstDictationStage.autoFocusHasFailed(secondsSinceRequest: 0.99, isFieldFocused: false))
    }

    func testTheAutoFocusHasFailedAtAndAfterOneSecond() {
        XCTAssertTrue(FirstDictationStage.autoFocusHasFailed(secondsSinceRequest: 1, isFieldFocused: false))
        XCTAssertTrue(FirstDictationStage.autoFocusHasFailed(secondsSinceRequest: 5, isFieldFocused: false))
    }

    func testAFocusedFieldNeverFailsItsAutoFocus() {
        XCTAssertFalse(FirstDictationStage.autoFocusHasFailed(secondsSinceRequest: 1, isFieldFocused: true))
        XCTAssertFalse(FirstDictationStage.autoFocusHasFailed(secondsSinceRequest: 60, isFieldFocused: true))
    }

    // MARK: - Continue, 15 s (#845)

    func testContinueIsHiddenBeforeFifteenSeconds() {
        XCTAssertFalse(FirstDictationStage.showsContinue(secondsSinceOtherKeyboard: 0, hasSeenOuisprKeyboard: false))
        XCTAssertFalse(FirstDictationStage.showsContinue(secondsSinceOtherKeyboard: 14.9, hasSeenOuisprKeyboard: false))
    }

    func testContinueShowsAtAndAfterFifteenSeconds() {
        XCTAssertTrue(FirstDictationStage.showsContinue(secondsSinceOtherKeyboard: 15, hasSeenOuisprKeyboard: false))
        XCTAssertTrue(FirstDictationStage.showsContinue(secondsSinceOtherKeyboard: 120, hasSeenOuisprKeyboard: false))
    }

    func testContinueNeedsAnotherKeyboardToHaveBeenUp() {
        XCTAssertFalse(FirstDictationStage.showsContinue(secondsSinceOtherKeyboard: nil, hasSeenOuisprKeyboard: false))
    }

    func testContinueIsHiddenOnceOuisprHasBeenDetected() {
        XCTAssertFalse(FirstDictationStage.showsContinue(secondsSinceOtherKeyboard: 15, hasSeenOuisprKeyboard: true))
        XCTAssertFalse(FirstDictationStage.showsContinue(secondsSinceOtherKeyboard: 120, hasSeenOuisprKeyboard: true))
    }

    // MARK: - Which input mode is Ouispr

    func testTheKeyboardExtensionIsOuispr() {
        XCTAssertTrue(FirstDictationStage.isOuisprInputMode(identifier: "com.pivi.dictus.keyboard"))
    }

    func testAppleKeyboardsAreNotOuispr() {
        XCTAssertFalse(FirstDictationStage.isOuisprInputMode(identifier: "fr_FR@sw=AZERTY-French;hw=Automatic"))
        XCTAssertFalse(FirstDictationStage.isOuisprInputMode(identifier: "en_US@sw=QWERTY;hw=Automatic"))
        XCTAssertFalse(FirstDictationStage.isOuisprInputMode(identifier: "emoji@sw=Emoji"))
        XCTAssertFalse(FirstDictationStage.isOuisprInputMode(identifier: "com.apple.dictation"))
    }

    func testAnIdentifierThatOnlyContainsThePrefixIsNotOuispr() {
        XCTAssertFalse(FirstDictationStage.isOuisprInputMode(identifier: "com.example.com.pivi.dictus.keyboard"))
        XCTAssertFalse(FirstDictationStage.isOuisprInputMode(identifier: "com.pivi.dictusplus.keyboard"))
    }

    func testAnUnreadableIdentifierIsNotOuispr() {
        XCTAssertFalse(FirstDictationStage.isOuisprInputMode(identifier: nil))
        XCTAssertFalse(FirstDictationStage.isOuisprInputMode(identifier: ""))
    }

    // MARK: - Completion, as before #678

    func testTextBeforeTheOuisprKeyboardDoesNotComplete() {
        XCTAssertFalse(FirstDictationStage.completes(text: "Bonjour à tous", hasSeenOuisprKeyboard: false))
    }

    func testThreeCharactersCompleteOnceOuisprHasBeenUp() {
        XCTAssertTrue(FirstDictationStage.completes(text: "oui", hasSeenOuisprKeyboard: true))
        XCTAssertTrue(FirstDictationStage.completes(text: "Bonjour à tous", hasSeenOuisprKeyboard: true))
    }

    func testFewerThanThreeCharactersDoNotComplete() {
        XCTAssertFalse(FirstDictationStage.completes(text: "", hasSeenOuisprKeyboard: true))
        XCTAssertFalse(FirstDictationStage.completes(text: "ok", hasSeenOuisprKeyboard: true))
        // Whitespace does not count: a stray space and return are not a dictation.
        XCTAssertFalse(FirstDictationStage.completes(text: "  a \n ", hasSeenOuisprKeyboard: true))
    }

    // MARK: - Typed text (#845)

    /// The rule takes no chip: typing with the Ouispr keyboard completes the step on an
    /// A14 or later (where the page asks for a dictation) as on an older chip (where it
    /// asks for typing, #635). Both pages feed the same call, so one input covers both.
    func testTypedTextCompletesOnceOuisprHasBeenUpOnEveryChip() {
        XCTAssertTrue(FirstDictationStage.completes(text: "abc", hasSeenOuisprKeyboard: true))
        XCTAssertTrue(FirstDictationStage.completes(text: "Je tape au clavier", hasSeenOuisprKeyboard: true))
    }

    func testTypedTextWithoutOuisprSeenDoesNotComplete() {
        XCTAssertFalse(FirstDictationStage.completes(text: "abc", hasSeenOuisprKeyboard: false))
        XCTAssertFalse(FirstDictationStage.completes(text: "Je tape au clavier", hasSeenOuisprKeyboard: false))
    }
}
