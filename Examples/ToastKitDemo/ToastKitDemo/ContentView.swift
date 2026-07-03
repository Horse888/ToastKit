import SwiftUI
import ToastKit

struct ContentView: View {
    @State private var isModal = false
    @State private var duration = 2.0
    @State private var didRunShowcase = false

    var body: some View {
        ZStack {
            if #available(iOS 18.0, *) {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                        [0.0, 0.5], [0.5, 0.45], [1.0, 0.5],
                        [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                    ],
                    colors: [
                        .blue,
                        .purple,
                        .cyan,
                        .mint,
                        .indigo,
                        .teal,
                        .orange,
                        .pink,
                        .yellow
                    ]
                )
                .ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.94, green: 0.98, blue: 1.0),
                        Color(red: 0.98, green: 0.96, blue: 0.91),
                        Color(red: 0.95, green: 0.97, blue: 0.94)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }

            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ToastKit")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    Text("Interactive SwiftUI toast presentation")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 14) {
                    Toggle("Modal overlay", isOn: $isModal)
                        .toggleStyle(.switch)

                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(duration == 0 ? "Manual" : "\(duration.formatted(.number.precision(.fractionLength(0))))s")
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $duration, in: 0...5, step: 1)
                }
                .padding(18)
                .background(.regularMaterial, in: .rect(cornerRadius: 16, style: .continuous))

                VStack(spacing: 12) {
                    DemoButton(title: "Success", symbol: "checkmark.circle.fill") {
                        show(.success)
                    }

                    DemoButton(title: "Warning", symbol: "exclamationmark.triangle.fill") {
                        show(.warning)
                    }

                    DemoButton(title: "Error", symbol: "xmark.octagon.fill") {
                        show(.error)
                    }

                    DemoButton(title: "Loading", symbol: "arrow.triangle.2.circlepath") {
                        show(.loading)
                    }

                    DemoButton(title: "Custom", symbol: "sparkles") {
                        showCustomToast()
                    }
                }

                Spacer()
            }
            .padding(24)
        }
        .onAppear {
            configureToastStyle()
        }
        .task {
            guard !didRunShowcase else { return }
            didRunShowcase = true
            await runShowcase()
        }
    }

    private func configureToastStyle() {
        ToastKit.configure(
            style: ToastStyle(
                font: .system(size: 16, weight: .semibold),
                symbolFont: .system(size: 24, weight: .bold),
                horizontalPadding: 22,
                verticalPadding: 13,
                contentHorizontalPadding: 24,
                topPadding: 14,
                shadowRadius: 24,
                shadowY: 6
            )
        )
    }

    private func show(_ demoToast: DemoToast) {
        ToastKit.show(demoToast.toastInfo, duration: duration, isModal: isModal)
    }

    private func showCustomToast() {
        ToastKit.show(duration: duration, isModal: isModal) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Custom toast")
                        .font(.headline)
                    Text("Bring any SwiftUI view")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .padding(.horizontal, 24)
        }
    }

    private func runShowcase() async {
        try? await Task.sleep(for: .milliseconds(650))
        ToastKit.show(DemoToast.success.toastInfo, duration: 1.35, isModal: false)

        try? await Task.sleep(for: .milliseconds(1550))
        ToastKit.show(DemoToast.warning.toastInfo, duration: 1.35, isModal: false)

        try? await Task.sleep(for: .milliseconds(1550))
        showCustomToast()

        try? await Task.sleep(for: .milliseconds(1550))
        ToastKit.show(DemoToast.error.toastInfo, duration: 1.45, isModal: true)

        try? await Task.sleep(for: .milliseconds(1700))
        ToastKit.show(DemoToast.loading.toastInfo, duration: 1.5, isModal: false)
    }
}

private enum DemoToast {
    case success
    case warning
    case error
    case loading

    var toastInfo: ToastInfo {
        switch self {
        case .success:
            ToastInfo(type: .success, msg: "Saved successfully")
        case .warning:
            ToastInfo(type: .warning, msg: "Network connection is unstable")
        case .error:
            ToastInfo(type: .error, msg: "Save failed. Please try again.")
        case .loading:
            ToastInfo(type: .loading(.blue), msg: "Syncing changes")
        }
    }
}

private struct DemoButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: symbol)
                    .frame(width: 24)
                Text(title)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
        }
        .buttonStyle(.borderedProminent)
    }
}

#Preview {
    ContentView()
}
