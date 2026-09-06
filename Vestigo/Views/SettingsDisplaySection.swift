import SwiftUI
import Foundation

struct SettingsDisplaySection: View {
    @ObservedObject var model: VestigoModel

    var body: some View {
        Text("Display")
            .sectionTitle()

        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Display style")
                    .font(.headline.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                Picker("Display style", selection: $model.settings.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .settingBubble()

            Toggle("Plain background", isOn: $model.settings.usePlainBackground)
                .font(.headline.bold())
                .tint(model.settings.accentColor)
                .settingBubble()

            ColorPicker(
                "Accent Colour",
                selection: Binding(
                    get: { model.settings.accentColor },
                    set: { model.settings.setAccentColor($0) }
                ),
                supportsOpacity: false
            )
            .font(.headline.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingBubble()

            Text("Home carousels")
                .font(.headline.bold())
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

            CarouselOrderContent(model: model)
        }
    }
}
