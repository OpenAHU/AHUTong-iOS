import SwiftUI

private struct AndroidScaledFontModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight

    init(size: CGFloat, relativeTo textStyle: Font.TextStyle, weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}

extension View {
    func androidScaledFont(
        size: CGFloat,
        relativeTo textStyle: Font.TextStyle = .body,
        weight: Font.Weight = .regular
    ) -> some View {
        modifier(AndroidScaledFontModifier(size: size, relativeTo: textStyle, weight: weight))
    }
}

enum AndroidParityPalette {
    private static var selectedTheme: Color {
        AndroidThemeColor.color(for: UserDefaults.standard.string(forKey: "theme.color") ?? "default")
    }

    static var brand: Color { selectedTheme }
    static var accent: Color { selectedTheme }
    static var systemTheme: Color { selectedTheme }
    static var primaryTone90: Color { selectedTheme.opacity(0.18) }
    static var primaryTone80: Color { selectedTheme.opacity(0.3) }
    static let liquidToggle = Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255)
    static let folder = Color(red: 255 / 255, green: 179 / 255, blue: 0 / 255)
    static let success = Color(red: 76 / 255, green: 175 / 255, blue: 80 / 255)
    static let warning = Color(red: 255 / 255, green: 179 / 255, blue: 0 / 255)
    static let error = Color(red: 255 / 255, green: 82 / 255, blue: 82 / 255)

    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 26 / 255, green: 26 / 255, blue: 26 / 255)
            : Color(red: 248 / 255, green: 247 / 255, blue: 253 / 255)
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 48 / 255, green: 48 / 255, blue: 48 / 255)
            : .white
    }

    static func raisedSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 42 / 255, green: 42 / 255, blue: 42 / 255)
            : Color(red: 252 / 255, green: 252 / 255, blue: 252 / 255)
    }

    static func primaryContainer(_ scheme: ColorScheme) -> Color {
        selectedTheme.opacity(scheme == .dark ? 0.28 : 0.16)
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 201 / 255, green: 201 / 255, blue: 201 / 255)
            : Color(red: 92 / 255, green: 92 / 255, blue: 92 / 255)
    }

    static func separator(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 72 / 255, green: 72 / 255, blue: 72 / 255)
            : Color(red: 214 / 255, green: 214 / 255, blue: 214 / 255)
    }
}

enum AndroidParitySymbol {
    // The Android lost-and-found glyph is a question mark inside an outlined bag.
    // SF Symbols does not provide that combined name, so the tool cell layers these
    // two stable symbols instead of passing an invalid composite name to Image.
    static let lostAndFoundBag = "bag"
    static let lostAndFoundQuestion = "questionmark"
    static let feedback = "exclamationmark.bubble"

    static let requiredSystemNames = [
        lostAndFoundBag,
        lostAndFoundQuestion,
        feedback
    ]
}

enum AndroidThemeColor {
    static let options: [(value: String, name: String)] = [
        ("default", "默认"),
        ("#FF4A90E2", "极光蓝"),
        ("#FFE07A9F", "樱花粉"),
        ("#FFF4A261", "落日橙"),
        ("#FF5C6BC0", "靛夜蓝"),
        ("#FF6A994E", "苔藓绿"),
        ("#FF9B7EDE", "薰衣草紫"),
        ("#FFD64550", "绯红花"),
        ("#FF4CC9F0", "天空青"),
        ("#FF2E8B57", "森林翡翠"),
        ("#FF6A4C93", "午夜紫"),
        ("#FFFF6F61", "珊瑚粉"),
        ("#FF7ED9C3", "北极薄荷")
    ]

    static func color(for value: String) -> Color {
        if value == "default" || value == "blue" { return Color(red: 103 / 255, green: 80 / 255, blue: 164 / 255) }
        if value == "green" { return .green }
        if value == "purple" { return .purple }
        if value == "orange" { return .orange }

        let components = rgbComponents(for: value)
        return Color(red: components.red, green: components.green, blue: components.blue)
    }

    static func rgbComponents(for value: String) -> (red: Double, green: Double, blue: Double) {
        let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard let raw = UInt64(hex, radix: 16) else { return (0, 127 / 255, 172 / 255) }
        let rgb = hex.count == 8 ? raw & 0x00FF_FFFF : raw
        return (
            Double((rgb >> 16) & 0xFF) / 255,
            Double((rgb >> 8) & 0xFF) / 255,
            Double(rgb & 0xFF) / 255
        )
    }
}

struct AndroidScreen<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            AndroidParityPalette.background(colorScheme).ignoresSafeArea()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AndroidParityPalette.background(colorScheme).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct AndroidHeader<Actions: View>: View {
    let title: String
    var large = false
    private let actions: Actions

    init(title: String, large: Bool = false, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.large = large
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(large ? .largeTitle : .title2)
                .fontWeight(large ? .regular : .semibold)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .padding(.horizontal, large ? 24 : 16)
        .padding(.top, large ? 32 : 12)
        .padding(.bottom, large ? 8 : 12)
    }
}

extension AndroidHeader where Actions == EmptyView {
    init(title: String, large: Bool = false) {
        self.init(title: title, large: large) { EmptyView() }
    }
}

struct AndroidIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .regular))
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct AndroidCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let radius: CGFloat
    let background: Color?
    private let content: Content

    init(
        radius: CGFloat = 16,
        background: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.radius = radius
        self.background = background
        self.content = content()
    }

    var body: some View {
        content
            .background(
                background ?? AndroidParityPalette.surface(colorScheme),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
    }
}

struct AndroidSearchField: View {
    @Binding var text: String
    let prompt: String
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空")
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 16)
        .background(.clear)
    }
}

struct AndroidSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .fontWeight(.bold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
    }
}

struct AndroidEmptyState: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(48)
    }
}

private struct AndroidDetailScreenModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(false)
            .toolbar(.visible, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .background(NativeNavigationGestureBridge())
    }
}

extension View {
    func androidDetailScreen() -> some View {
        modifier(AndroidDetailScreenModifier())
    }
}
