import Testing
@testable import ToastKit

@Test func toastInfoInitializerStoresValues() {
    let toastInfo = ToastInfo(
        type: .warning,
        msg: "Network unstable",
        sfSymbolName: "exclamationmark.triangle.fill"
    )

    if case .warning = toastInfo.type {
        #expect(Bool(true))
    } else {
        #expect(Bool(false))
    }

    #expect(toastInfo.msg == "Network unstable")
    #expect(toastInfo.sfSymbolName == "exclamationmark.triangle.fill")
}

@Test func toastInfoSymbolOverrideDefaultsToNil() {
    let toastInfo = ToastInfo(type: .success, msg: "Saved")

    #expect(toastInfo.sfSymbolName == "checkmark.circle.fill")
}

@Test func toastInfoExplicitNilSymbolHidesIcon() {
    let toastInfo = ToastInfo(type: .success, msg: "Saved", sfSymbolName: nil)

    #expect(toastInfo.sfSymbolName == nil)
}

@Test func toastTypesProvideDefaultSymbols() {
    #expect(ToastType.success.defaultSFSymbolName == "checkmark.circle.fill")
    #expect(ToastType.warning.defaultSFSymbolName == "exclamationmark.triangle.fill")
    #expect(ToastType.error.defaultSFSymbolName == "xmark.circle.fill")
    #expect(ToastType.loading(.blue).defaultSFSymbolName == "progress.indicator")
}

@Test func toastTypesReportLoadingState() {
    #expect(ToastType.loading(.blue).isLoading)
    #expect(!ToastType.success.isLoading)
    #expect(!ToastType.warning.isLoading)
    #expect(!ToastType.error.isLoading)
}

@Test func defaultToastStyleMatchesInitializerDefaults() {
    let defaultStyle = ToastStyle.default
    let initializedStyle = ToastStyle()

    #expect(defaultStyle.horizontalPadding == initializedStyle.horizontalPadding)
    #expect(defaultStyle.verticalPadding == initializedStyle.verticalPadding)
    #expect(defaultStyle.topPadding == initializedStyle.topPadding)
    #expect(defaultStyle.cornerRadius == initializedStyle.cornerRadius)
    #expect(defaultStyle.animationDuration == initializedStyle.animationDuration)
    #expect(String(describing: defaultStyle.symbolFont) == String(describing: initializedStyle.symbolFont))
}

@Test func dragTransitionDismissesUpwardAndDownwardGestures() {
    let transition = ToastInteractiveTransition()

    #expect(transition.dismissReason(translationY: -90, predictedTranslationY: -90) == .dragUp)
    #expect(transition.dismissReason(translationY: 90, predictedTranslationY: 90) == .dragDown)
    #expect(transition.dismissReason(translationY: 20, predictedTranslationY: 20) == nil)
}
