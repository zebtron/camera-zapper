import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SetupWizardView: View {
    @EnvironmentObject private var store: AppStore
    @State private var step = 0
    @State private var configurationIndex = 0
    @State private var flickrKey = ""
    @State private var flickrSecret = ""

    private let titles = ["Welcome", "Local archive", "Choose services", "Deletion gating", "Configure", "Priority", "Review"]
    private var availableServices: [ServiceConfiguration] {
        store.configuration.services.filter { $0.kind != .localStorage && $0.kind != .derivative }
    }
    private var chosenServices: [ServiceConfiguration] {
        availableServices.filter(\.isEnabled).sorted { $0.priority < $1.priority }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch step {
                case 0: welcome
                case 1: localArchive
                case 2: chooseServices
                case 3: deletionGating
                case 4: configureService
                case 5: priorityOrder
                default: review
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            footer
        }
        .frame(width: 850, height: 660)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Camera Zapper Setup").font(.title.bold()).accessibilityAddTraits(.isHeader)
                    Text("Step \(step + 1) of \(titles.count) · \(titles[step])").foregroundStyle(.secondary)
                }
                Spacer()
                Text("BETA 1.350").font(.caption.bold()).foregroundStyle(.blue)
            }
            ProgressView(value: Double(step + 1), total: Double(titles.count))
                .accessibilityLabel("Setup progress")
                .accessibilityValue("Step \(step + 1) of \(titles.count)")
        }.padding(24)
    }

    private var welcome: some View {
        wizardPage(title: "One-way, verified backup", icon: "camera.fill") {
            Text("Camera Zapper moves media from a device to one or more destinations. Optional safe deletion happens only after every destination you mark as required has verified its copy.")
            Label("Device → verified local archive → selected destinations", systemImage: "arrow.right")
            Label("Cloud uploads are private only by design", systemImage: "lock.shield.fill")
            Label("No telemetry and no background data collection", systemImage: "hand.raised.fill")
            Text("Automatic deletion is off. Keep confirmation-only deletion while you test with noncritical media.")
                .font(.callout.weight(.semibold)).foregroundStyle(.orange)
        }
    }

    private var localArchive: some View {
        wizardPage(title: "Verify the local safety archive", icon: "internaldrive.fill") {
            if let service = store.configuration.services.first(where: { $0.kind == .localStorage }) {
                Text("This always-on safety copy protects an interrupted or offline transfer.")
                HStack {
                    Text(service.destination ?? "~/Pictures/Camera Zapper/Archive")
                        .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    Spacer()
                    Button("Choose Folder…") { chooseDestination(for: service.id) }
                    Button("Test") { store.testService(service.id) }.buttonStyle(.borderedProminent)
                }.padding(12).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                ServiceStateLabel(service: service)
            }
        }
    }

    private var chooseServices: some View {
        wizardPage(title: "Which destinations do you want?", icon: "checklist") {
            Text("Unselected services remain Not set up. They will not nag you and cannot block deletion.")
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(availableServices) { service in
                        Toggle(isOn: Binding(get: { serviceValue(service.id).isEnabled }, set: { store.setServiceEnabled(service.id, $0) })) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(service.name).font(.headline)
                                Text(service.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }.toggleStyle(.checkbox).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private var deletionGating: some View {
        wizardPage(title: "Choose your deletion gates", icon: "checkmark.shield.fill") {
            Text("For each selected destination, decide whether it must verify before originals may be deleted. Only checked services can block deletion.")
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(chosenServices) { service in
                        Toggle("Require \(service.name) before deleting originals", isOn: requiredBinding(service.id))
                            .toggleStyle(.checkbox).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            Label("Deletion remains Always ask. Automatic deletion is not enabled by this wizard.", systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var configureService: some View {
        if chosenServices.isEmpty {
            wizardPage(title: "No additional services selected", icon: "checkmark.circle") {
                Text("The verified local archive is enough to use Camera Zapper. You can add services later from Settings.")
            }
        } else {
            let services = chosenServices
            let safeIndex = min(configurationIndex, services.count - 1)
            let service = services[safeIndex]
            wizardPage(title: "Configure \(service.name)", icon: icon(service.kind)) {
                Text(service.detail)
                Text("Service \(safeIndex + 1) of \(services.count)").font(.caption).foregroundStyle(.secondary)
                configurationControls(service)
                ServiceStateLabel(service: service)
                HStack {
                    Button("Previous Service") { configurationIndex = max(0, safeIndex - 1) }.disabled(safeIndex == 0)
                    Spacer()
                    Button("Next Service") { configurationIndex = min(services.count - 1, safeIndex + 1) }.disabled(safeIndex == services.count - 1)
                }
            }
        }
    }

    @ViewBuilder private func configurationControls(_ service: ServiceConfiguration) -> some View {
        switch service.kind {
        case .storage:
            VStack(alignment: .leading, spacing: 10) {
                Text("Mount the share with macOS, select the real destination folder, then run the write → SHA-256 read-back → delete test.")
                HStack {
                    TextField("smb://server/share", text: Binding(get: { serviceValue(service.id).remoteLocation ?? "" }, set: { setRemote(service.id, $0) }))
                    Button("Mount your NAS") { mountNAS(service) }
                }
                HStack {
                    Text(serviceValue(service.id).destination ?? "No folder selected").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Spacer(); Button("Choose Folder…") { chooseDestination(for: service.id) }
                    Button("Test") { store.testService(service.id) }.buttonStyle(.borderedProminent)
                }
            }
        case .googlePhotos:
            HStack { Text("Authorize Google Photos first; YouTube reuses this Google client."); Spacer(); Button("Choose OAuth JSON…") { chooseGoogleJSON(service.id) }; Button("Test") { store.testService(service.id) } }
        case .youtube:
            VStack(alignment: .leading) {
                Text("Private-only uploads. Google currently limits this client to about 100 uploads per project each day.")
                HStack { Spacer(); Button("Authorize Private YouTube") { store.configureYouTube(serviceID: service.id) }; Button("Test") { store.testService(service.id) } }
            }
        case .flickr:
            VStack(alignment: .leading, spacing: 8) {
                TextField("Flickr API key", text: $flickrKey)
                SecureField("Flickr API secret", text: $flickrSecret)
                HStack { Spacer(); Button("Authorize Flickr") { store.configureFlickr(key: flickrKey, secret: flickrSecret, serviceID: service.id) }.disabled(flickrKey.isEmpty || flickrSecret.isEmpty); Button("Test") { store.testService(service.id) } }
            }
        case .photos:
            HStack { Text("macOS asks for Photos permission when the first import runs."); Spacer(); Button("Mark Ready & Test") { store.testService(service.id) }.buttonStyle(.borderedProminent) }
        case .neofinder:
            HStack { Text("Camera Zapper checks for NeoFinder in Applications."); Spacer(); Button("Test") { store.testService(service.id) }.buttonStyle(.borderedProminent) }
        default:
            HStack { Text("This destination is not available in the controlled beta."); Spacer(); Button("Test") { store.testService(service.id) } }
        }
    }

    private var priorityOrder: some View {
        wizardPage(title: "Set execution priority", icon: "line.3.horizontal") {
            Text("Services run from top to bottom. Drag rows to reorder them; the local archive always stays first.")
            List {
                ForEach(store.configuration.services.filter { $0.isEnabled && $0.kind != .derivative }.sorted { $0.priority < $1.priority }) { service in
                    Label(service.name, systemImage: service.kind == .localStorage ? "lock.fill" : "line.3.horizontal")
                }.onMove(perform: store.moveServices)
            }.listStyle(.inset)
        }
    }

    private var review: some View {
        wizardPage(title: "Review and finish", icon: "checkmark.seal.fill") {
            Text("Your selected services and their current state:")
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(store.configuration.services.filter(\.isEnabled).sorted { $0.priority < $1.priority }) { service in
                        HStack { Text(service.name).font(.headline); Spacer(); ServiceStateLabel(service: service); if service.isRequiredForDeletion { Label("Required", systemImage: "lock.fill").font(.caption) } }
                            .padding(10).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
                    }
                }
            }
            Label("Use noncritical test media for your first complete run.", systemImage: "lightbulb.fill").foregroundStyle(.orange)
            if !store.configurationWarnings.isEmpty {
                ForEach(store.configurationWarnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Skip for Now") { store.skipSetupForNow() }
            Spacer()
            Button("Back") { step = max(0, step - 1) }.disabled(step == 0)
            if step < titles.count - 1 {
                Button("Continue") { step += 1 }.buttonStyle(.borderedProminent)
            } else {
                Button("Finish Setup") { store.completeInitialSetup() }.buttonStyle(.borderedProminent)
            }
        }.padding(20)
    }

    private func wizardPage<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label(title, systemImage: icon).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                content()
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func serviceValue(_ id: UUID) -> ServiceConfiguration { store.configuration.services.first(where: { $0.id == id })! }
    private func requiredBinding(_ id: UUID) -> Binding<Bool> { Binding(get: { serviceValue(id).isRequiredForDeletion }, set: { value in if let i = store.configuration.services.firstIndex(where: { $0.id == id }) { store.configuration.services[i].isRequiredForDeletion = value } }) }
    private func setRemote(_ id: UUID, _ value: String) { if let i = store.configuration.services.firstIndex(where: { $0.id == id }) { store.configuration.services[i].remoteLocation = value } }
    private func chooseDestination(for id: UUID) { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.prompt = "Use Destination"; if panel.runModal() == .OK, let url = panel.url { store.updateServiceDestination(id, path: url.path) } }
    private func chooseGoogleJSON(_ id: UUID) { let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false; if panel.runModal() == .OK, let url = panel.url { store.configureGooglePhotos(from: url, serviceID: id) } }
    private func mountNAS(_ service: ServiceConfiguration) { guard let text = service.remoteLocation, let url = URL(string: text), url.scheme == "smb" else { store.serviceOperations[service.id] = "Configuring · enter an smb:// server/share address"; return }; NSWorkspace.shared.open(url) }
    private func icon(_ kind: ServiceKind) -> String { switch kind { case .storage: "externaldrive.fill"; case .googlePhotos: "photo.badge.arrow.down"; case .youtube: "play.rectangle.fill"; case .flickr: "circle.grid.2x1.fill"; case .photos: "photo.on.rectangle.angled"; case .neofinder: "books.vertical.fill"; default: "shippingbox.fill" } }
}

private struct ServiceStateLabel: View {
    @EnvironmentObject private var store: AppStore
    let service: ServiceConfiguration
    var body: some View {
        let text = store.serviceCapability(service)
        Label(text, systemImage: icon(text)).font(.caption.weight(.semibold)).foregroundStyle(color(text))
            .accessibilityLabel("\(service.name) status: \(text)")
    }
    private func icon(_ text: String) -> String { text.hasPrefix("Operational") ? "checkmark.circle.fill" : text.hasPrefix("Not set up") ? "circle.dashed" : text.hasPrefix("Configuring") ? "gearshape.2.fill" : "exclamationmark.triangle.fill" }
    private func color(_ text: String) -> Color { text.hasPrefix("Operational") ? .green : text.hasPrefix("Needs attention") || text.hasPrefix("Unavailable") || text.hasPrefix("Failed") ? .orange : .secondary }
}
