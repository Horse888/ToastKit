//
//  ToastKit.swift
//  ToastKit
//
//  Created by Dio on 2026/1/11.
//

import OSLog
import SwiftUI
import UIKit

@MainActor
public enum ToastKit {
    private static let logger = Logger(subsystem: "ToastKit", category: "ToastKit")
    private static var style = ToastStyle.default

    private static var window: ToastWindow?
    private static var dismissTask: Task<Void, Never>?
    private static var currentDuration: TimeInterval = 0
    private static var hideAction: ((ToastDismissReason) -> Void)?
    private static var toastInfoStore: ToastInfoStore?
    private static var currentPresentation: ToastPresentation?

    public static func configure(style: ToastStyle) {
        self.style = style
    }

    public static var currentStyle: ToastStyle {
        style
    }

    static func setHideAction(_ action: ((ToastDismissReason) -> Void)?) {
        hideAction = action
    }

    static func setInteractiveFrames(_ frames: [CGRect]) {
        window?.interactiveFrames = frames
    }

    public static func show(_ toastInfo: ToastInfo, duration: TimeInterval = 3, isModal: Bool = false) {
        if canUpdatePresentedLoadingToast(with: toastInfo, isModal: isModal) {
            dismissTask?.cancel()
            dismissTask = nil
            currentDuration = duration
            withAnimation(.easeInOut(duration: 0.2)) {
                toastInfoStore?.toastInfo = toastInfo
            }
            scheduleDismissal(after: duration)
            return
        }

        let store = ToastInfoStore(toastInfo: toastInfo)
        toastInfoStore = store
        currentPresentation = .toastInfo(isModal: isModal)

        let didPresent = present(duration: duration, isModal: isModal) {
            LiveCommonToast(store: store, style: style)
        }

        if !didPresent {
            toastInfoStore = nil
            currentPresentation = nil
        }
    }

    public static func showError(_ message: String, duration: TimeInterval = 3, isModal: Bool = false) {
        logger.error("Toast error: \(message, privacy: .public)")
        show(ToastInfo(type: .error, msg: message), duration: duration, isModal: isModal)
    }

    public static func show<Content: View>(
        duration: TimeInterval = 3,
        isModal: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        toastInfoStore = nil
        currentPresentation = .custom(isModal: isModal)

        let didPresent = present(duration: duration, isModal: isModal, content: content)

        if !didPresent {
            currentPresentation = nil
        }
    }

    @discardableResult
    private static func present<Content: View>(
        duration: TimeInterval,
        isModal: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) -> Bool {
        dismissTask?.cancel()
        dismissTask = nil
        currentDuration = duration

        guard let window = activeWindow() else {
            logger.error("Unable to present toast because no UIWindowScene is available.")
            return false
        }

        let host = ToastHostView(isModal: isModal, content: content)
        let controller = UIHostingController(rootView: host)
        controller.view.backgroundColor = .clear

        window.rootViewController = controller
        window.isUserInteractionEnabled = true
        window.passesThroughBackground = !isModal
        window.alpha = 1
        window.isHidden = false
        window.makeKeyAndVisible()

        scheduleDismissal(after: duration)
        return true
    }

    public static func hide() {
        hide(reason: .programmatic)
    }

    public static func hide(reason: ToastDismissReason) {
        dismissTask?.cancel()
        dismissTask = nil
        currentDuration = 0

        if let hideAction {
            hideAction(reason)
            return
        }

        finishHide()
    }

    static func finishHide() {
        hideAction = nil
        toastInfoStore = nil
        currentPresentation = nil

        guard let window else { return }
        guard let controller = window.rootViewController else { return }

        window.rootViewController = nil
        window.isHidden = true
        window.isUserInteractionEnabled = false
        window.passesThroughBackground = true
        window.interactiveFrames = []
        controller.view.alpha = 1
    }

    static func pauseDismissalForInteraction() {
        dismissTask?.cancel()
        dismissTask = nil
    }

    static func resumeDismissalAfterInteraction() {
        scheduleDismissal(after: currentDuration)
    }

    private static func scheduleDismissal(after duration: TimeInterval) {
        dismissTask?.cancel()
        dismissTask = nil

        guard duration > 0 else { return }

        dismissTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(duration))
                try Task.checkCancellation()
                hide(reason: .timeout)
            } catch {
                logger.debug("Toast dismissal task cancelled.")
            }
        }
    }

    private static func activeWindow() -> ToastWindow? {
        guard let scene = ToastWindow.bestAvailableScene() else {
            window = nil
            return nil
        }

        if let window, window.windowScene === scene {
            return window
        }

        let toastWindow = ToastWindow(windowScene: scene)
        window = toastWindow
        return toastWindow
    }

    private static func canUpdatePresentedLoadingToast(with toastInfo: ToastInfo, isModal: Bool) -> Bool {
        guard toastInfo.type.isLoading else {
            return false
        }

        guard let currentPresentation, currentPresentation.isToastInfo, currentPresentation.isModal == isModal else {
            return false
        }

        guard toastInfoStore?.toastInfo.type.isLoading == true else {
            return false
        }

        return window?.rootViewController != nil
    }
}

public enum ToastDismissReason: Sendable, Equatable {
    case timeout
    case dragUp
    case dragDown
    case programmatic
}

struct ToastInteractiveTransition: Sendable {
    var dismissalThreshold: CGFloat = 80
    var predictedDismissalThreshold: CGFloat = 160
    var progressDistance: CGFloat = 140
    var maxDownScaleReduction: CGFloat = 0.12
    var maxBlurRadius: CGFloat = 12
    var maxDownOpacityReduction: Double = 0.35

    func progress(for offsetY: CGFloat) -> CGFloat {
        min(abs(offsetY) / progressDistance, 1)
    }

    func scale(for offsetY: CGFloat) -> CGFloat {
        guard offsetY > 0 else { return 1 }
        return 1 - progress(for: offsetY) * maxDownScaleReduction
    }

    func blurRadius(for offsetY: CGFloat) -> CGFloat {
        progress(for: offsetY) * maxBlurRadius
    }

    func opacity(for offsetY: CGFloat) -> Double {
        let progress = progress(for: offsetY)

        if offsetY < 0 {
            return Double(1 - progress)
        }

        return 1 - Double(progress) * maxDownOpacityReduction
    }

    func dismissReason(translationY: CGFloat, predictedTranslationY: CGFloat) -> ToastDismissReason? {
        guard abs(translationY) > dismissalThreshold || abs(predictedTranslationY) > predictedDismissalThreshold else {
            return nil
        }

        return translationY < 0 || predictedTranslationY < 0 ? .dragUp : .dragDown
    }
}

@MainActor
private struct ToastInteractiveFramePreferenceKey: PreferenceKey {
    static var defaultValue: [CGRect] = []

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

final class ToastWindow: UIWindow {
    var passesThroughBackground = true
    var interactiveFrames: [CGRect] = []

    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)

        frame = windowScene.coordinateSpace.bounds
        windowLevel = .alert + 1
        backgroundColor = .clear
        isHidden = true
        isUserInteractionEnabled = false
    }

    static func bestAvailableScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

        return scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundInactive })
            ?? scenes.first
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if let windowScene {
            frame = windowScene.coordinateSpace.bounds
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)

        guard passesThroughBackground else {
            return hitView
        }

        let expandedFrames = interactiveFrames.map { frame in
            frame.insetBy(dx: -16, dy: -16)
        }

        if expandedFrames.contains(where: { $0.contains(point) }) {
            return hitView
        }

        return nil
    }

    required init?(coder _: NSCoder) {
        return nil
    }
}

struct ToastHostView<Content: View>: View {
    let isModal: Bool
    let content: Content
    @State private var isVisible = false
    @GestureState private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    private let interactiveTransition = ToastInteractiveTransition()

    init(isModal: Bool, @ViewBuilder content: () -> Content) {
        self.isModal = isModal
        self.content = content()
    }

    private var offsetY: CGFloat {
        dragOffset.height
    }

    private var scale: CGFloat {
        interactiveTransition.scale(for: offsetY)
    }

    private var blurRadius: CGFloat {
        interactiveTransition.blurRadius(for: offsetY)
    }

    private var toastOpacity: Double {
        interactiveTransition.opacity(for: offsetY)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if isModal {
                ToastKit.currentStyle.modalOverlayColor
                    .opacity(isVisible ? 1 : 0)
                    .ignoresSafeArea()
            }

            if isModal {
                if isVisible {
                    interactiveContent
                        .padding(.top, ToastKit.currentStyle.topPadding)
                        .padding(.horizontal, ToastKit.currentStyle.contentHorizontalPadding)
                }
            } else {
                VStack {
                    if isVisible {
                        interactiveContent
                            .padding(.top, ToastKit.currentStyle.topPadding)
                    }

                    Spacer()
                }
            }
        }
        .coordinateSpace(name: "ToastKitRoot")
        .onPreferenceChange(ToastInteractiveFramePreferenceKey.self) { frames in
            ToastKit.setInteractiveFrames(frames)
        }
        .onAppear {
            ToastKit.setHideAction { reason in
                dismiss(reason: reason)
            }

            withAnimation(.spring(response: ToastKit.currentStyle.animationDuration, dampingFraction: 0.82)) {
                isVisible = true
            }
        }
        .onDisappear {
            ToastKit.setHideAction(nil)
        }
        .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.82), value: dragOffset)
    }

    private var interactiveContent: some View {
        content
            .offset(y: offsetY)
            .scaleEffect(scale)
            .opacity(toastOpacity)
            .blur(radius: blurRadius)
            .transition(
                .move(edge: .top)
                    .combined(with: .opacity)
                    .combined(with: .scale)
            )
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ToastInteractiveFramePreferenceKey.self,
                        value: [proxy.frame(in: .global)]
                    )
                }
            }
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { _ in
                        if !isDragging {
                            isDragging = true
                            ToastKit.pauseDismissalForInteraction()
                        }
                    }
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        isDragging = false

                        if let reason = interactiveTransition.dismissReason(
                            translationY: value.translation.height,
                            predictedTranslationY: value.predictedEndTranslation.height
                        ) {
                            ToastKit.hide(reason: reason)
                        } else {
                            ToastKit.resumeDismissalAfterInteraction()
                        }
                    }
            )
    }

    private func dismiss(reason: ToastDismissReason) {
        let animation: Animation = switch reason {
        case .dragDown:
            .easeOut(duration: 0.22)
        case .dragUp:
            .easeOut(duration: 0.18)
        case .timeout, .programmatic:
            .easeOut(duration: 0.2)
        }

        withAnimation(animation) {
            isVisible = false
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(240))
            ToastKit.finishHide()
        }
    }
}

public struct ToastInfo: Sendable {
    public var type = ToastType.success
    public var msg: String?
    public var sfSymbolName: String?

    public init(type: ToastType = .success, msg: String? = nil) {
        self.type = type
        self.msg = msg
        sfSymbolName = type.defaultSFSymbolName
    }

    public init(type: ToastType = .success, msg: String? = nil, sfSymbolName: String?) {
        self.type = type
        self.msg = msg
        self.sfSymbolName = sfSymbolName
    }
}

public enum ToastType: Sendable {
    case success
    case warning
    case error
    case loading(Color)

    var defaultSFSymbolName: String? {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.circle.fill"
        case .loading:
            return "progress.indicator"
        }
    }
}

extension ToastType {
    var isLoading: Bool {
        if case .loading = self {
            return true
        }

        return false
    }
}

@MainActor
private final class ToastInfoStore: ObservableObject {
    @Published var toastInfo: ToastInfo

    init(toastInfo: ToastInfo) {
        self.toastInfo = toastInfo
    }
}

private enum ToastPresentation {
    case toastInfo(isModal: Bool)
    case custom(isModal: Bool)

    var isModal: Bool {
        switch self {
        case let .toastInfo(isModal), let .custom(isModal):
            return isModal
        }
    }

    var isToastInfo: Bool {
        if case .toastInfo = self {
            return true
        }

        return false
    }
}

public struct ToastStyle: Sendable {
    public var successBackgroundColor: Color
    public var warningBackgroundColor: Color
    public var errorBackgroundColor: Color
    public var loadingBackgroundColor: Color

    public var successBorderColor: Color
    public var warningBorderColor: Color
    public var errorBorderColor: Color
    public var loadingBorderColor: Color

    public var foregroundColor: Color
    public var font: Font
    public var symbolFont: Font
    public var horizontalPadding: CGFloat
    public var verticalPadding: CGFloat
    public var contentHorizontalPadding: CGFloat
    public var topPadding: CGFloat
    public var cornerRadius: CGFloat
    public var borderWidth: CGFloat
    public var shadowColor: Color
    public var shadowRadius: CGFloat
    public var shadowX: CGFloat
    public var shadowY: CGFloat
    public var modalOverlayColor: Color
    public var animationDuration: Double

    public init(
        successBackgroundColor: Color = .green.opacity(0.12),
        warningBackgroundColor: Color = .orange.opacity(0.12),
        errorBackgroundColor: Color = .red.opacity(0.12),
        loadingBackgroundColor: Color = .blue.opacity(0.12),
        successBorderColor: Color = .green.opacity(0.6),
        warningBorderColor: Color = .orange.opacity(0.6),
        errorBorderColor: Color = .red.opacity(0.6),
        loadingBorderColor: Color = .blue.opacity(0.6),
        foregroundColor: Color = .primary,
        font: Font = .system(size: 16, weight: .medium),
        symbolFont: Font = .system(size: 22, weight: .semibold),
        horizontalPadding: CGFloat = 10,
        verticalPadding: CGFloat = 10,
        contentHorizontalPadding: CGFloat = 30,
        topPadding: CGFloat = 8,
        cornerRadius: CGFloat = 999,
        borderWidth: CGFloat = 0.5,
        shadowColor: Color = .black.opacity(0.1),
        shadowRadius: CGFloat = 30,
        shadowX: CGFloat = 0,
        shadowY: CGFloat = 5,
        modalOverlayColor: Color = .black.opacity(0.18),
        animationDuration: Double = 0.3
    ) {
        self.successBackgroundColor = successBackgroundColor
        self.warningBackgroundColor = warningBackgroundColor
        self.errorBackgroundColor = errorBackgroundColor
        self.loadingBackgroundColor = loadingBackgroundColor
        self.successBorderColor = successBorderColor
        self.warningBorderColor = warningBorderColor
        self.errorBorderColor = errorBorderColor
        self.loadingBorderColor = loadingBorderColor
        self.foregroundColor = foregroundColor
        self.font = font
        self.symbolFont = symbolFont
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.contentHorizontalPadding = contentHorizontalPadding
        self.topPadding = topPadding
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.shadowColor = shadowColor
        self.shadowRadius = shadowRadius
        self.shadowX = shadowX
        self.shadowY = shadowY
        self.modalOverlayColor = modalOverlayColor
        self.animationDuration = animationDuration
    }

    public static let `default` = ToastStyle()

    func backgroundColor(for type: ToastType) -> Color {
        switch type {
        case .success:
            return successBackgroundColor
        case .warning:
            return warningBackgroundColor
        case .error:
            return errorBackgroundColor
        case .loading:
            return loadingBackgroundColor
        }
    }

    func borderColor(for type: ToastType) -> Color {
        switch type {
        case .success:
            return successBorderColor
        case .warning:
            return warningBorderColor
        case .error:
            return errorBorderColor
        case .loading:
            return loadingBorderColor
        }
    }

    func glassTintColor(for type: ToastType) -> Color {
        borderColor(for: type)
            .opacity(0.3)
    }
}

public struct CommonToast: View {
    public let toastInfo: ToastInfo
    public let style: ToastStyle
    @State private var symbolAnimationTrigger = false

    public init(toastInfo: ToastInfo, style: ToastStyle = .default) {
        self.toastInfo = toastInfo
        self.style = style
    }

    private var symbolName: String? {
        if let sfSymbolName = toastInfo.sfSymbolName {
            return sfSymbolName.isEmpty ? nil : sfSymbolName
        }

        return toastInfo.type.defaultSFSymbolName
    }

    private var symbolColor: Color {
        if case let .loading(color) = toastInfo.type {
            return color
        }

        return style.borderColor(for: toastInfo.type)
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let sfSymbolName = symbolName {
                Image(systemName: sfSymbolName)
                    .font(style.symbolFont)
                    .imageScale(.medium)
                    .symbolRenderingMode(.multicolor)
                    .foregroundStyle(symbolColor)
                    .modifier(
                        ToastSymbolEffectModifier(
                            type: toastInfo.type,
                            trigger: symbolAnimationTrigger
                        )
                    )
            }

            if let msg = toastInfo.msg {
                toastMessage(msg)
            }
        }
        .font(style.font)
        .foregroundStyle(style.foregroundColor)
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .modifier(ToastSurfaceModifier(style: style, type: toastInfo.type))
        .padding(.horizontal, style.contentHorizontalPadding)
        .onAppear {
            symbolAnimationTrigger.toggle()
        }
    }

    @ViewBuilder
    private func toastMessage(_ msg: String) -> some View {
        if #available(iOS 17.0, *), let numericValue = numericValue(in: msg) {
            Text(msg)
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .contentTransition(.numericText(value: numericValue))
                .animation(.snappy(duration: 0.25), value: numericValue)
        } else if #available(iOS 17.0, *) {
            Text(msg)
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.25), value: msg)
        } else {
            Text(msg)
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
        }
    }

    private func numericValue(in message: String) -> Double? {
        for token in message.split(whereSeparator: { !"0123456789.-".contains($0) }) {
            let candidate = String(token)

            guard candidate != "-", candidate != ".", candidate != "-." else {
                continue
            }

            if let value = Double(candidate) {
                return value
            }
        }

        return nil
    }
}

@MainActor
private struct LiveCommonToast: View {
    @ObservedObject var store: ToastInfoStore
    let style: ToastStyle

    var body: some View {
        CommonToast(toastInfo: store.toastInfo, style: style)
    }
}

private struct ToastSymbolEffectModifier: ViewModifier {
    let type: ToastType
    let trigger: Bool

    @State private var isLoadingRotating = false

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            switch type {
            case .success:
                content.symbolEffect(.bounce, options: .nonRepeating, value: trigger)
            case .warning:
                content.symbolEffect(.bounce, value: trigger)
            case .error:
                if #available(iOS 18.0, *) {
                    content.symbolEffect(.wiggle, value: trigger)
                } else {
                    content.symbolEffect(.bounce, options: .repeat(2), value: trigger)
                }
            case .loading:
                if #available(iOS 18.0, *) {
                    content
                        .symbolEffect(.variableColor.iterative, options: .repeat(.continuous), isActive: true)
                } else {
                    content
                        .rotationEffect(.degrees(isLoadingRotating ? 360 : 0))
                        .animation(
                            .linear(duration: 1.0).repeatForever(autoreverses: false),
                            value: isLoadingRotating
                        )
                        .onAppear { isLoadingRotating = true }
                        .onDisappear { isLoadingRotating = false }
                }
            }
        } else {
            content
        }
    }
}

private struct ToastSurfaceModifier: ViewModifier {
    let style: ToastStyle
    let type: ToastType

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)

        #if compiler(>=6.4)
            if #available(iOS 26.0, *) {
                content
                    .glassEffect(.regular.tint(style.glassTintColor(for: type)), in: shape)
                    .overlay {
                        shape
                            .strokeBorder(style.borderColor(for: type).opacity(0.35), lineWidth: style.borderWidth)
                    }
                    .shadow(color: style.shadowColor.opacity(0.7), radius: style.shadowRadius, x: style.shadowX, y: style.shadowY)
            } else {
                fallbackSurface(content: content, shape: shape)
            }
        #else
            fallbackSurface(content: content, shape: shape)
        #endif
    }

    private func fallbackSurface(content: Content, shape: RoundedRectangle) -> some View {
        content
            .background(style.backgroundColor(for: type), in: shape)
            .overlay {
                shape
                    .strokeBorder(style.borderColor(for: type), lineWidth: style.borderWidth)
            }
            .compositingGroup()
            .shadow(color: style.shadowColor, radius: style.shadowRadius, x: style.shadowX, y: style.shadowY)
    }
}
