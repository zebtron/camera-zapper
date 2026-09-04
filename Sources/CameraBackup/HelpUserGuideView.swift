import SwiftUI

struct HelpUserGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Help & User Guide").font(.largeTitle.bold())
                    Text("Connect once. Verify every copy. Delete only when the evidence agrees.")
                        .font(.title3).foregroundStyle(.secondary)
                }

                GuideSection(title: "The everyday one-button workflow", icon: "checkmark.shield.fill", color: .red) {
                    GuideStep(number: 1, title: "Connect and unlock the device", text: "For Android, choose File transfer / Android Auto, enable USB debugging, and approve this Mac. Camera Zapper remembers the device and shows it Offline when disconnected.")
                    GuideStep(number: 2, title: "Review required destinations", text: "In Services & Priority, enable the services you use, drag them into order, and mark only destinations that truly must succeed before source deletion.")
                    GuideStep(number: 3, title: "Run the large red button", text: "RUN COMPLETE BACKUP, VERIFY & DELETE scans the device, creates a verified local staging copy, processes services in order, checks required receipts, and deletes source originals only after the entire preflight passes.")
                    GuideStep(number: 4, title: "Watch the live status", text: "Progress and the operation log distinguish copying, hashing, uploading, duplicates, completed receipts, failures, and deletion. Do not disconnect while an operation is active.")
                }

                GuideSection(title: "Advanced actions", icon: "slider.horizontal.3", color: .blue) {
                    GuideRow(title: "Scan & Preview", text: "Counts supported files without copying or deleting anything.")
                    GuideRow(title: "Local Verified Backup", text: "Copies into interruption-safe local staging and records SHA-256 receipts, but does not run other services.")
                    GuideRow(title: "Sync All Services", text: "Processes enabled operational services in priority order without deleting source files.")
                    GuideRow(title: "Verify & Delete Only", text: "Rechecks the connected source and every applicable required receipt, then removes source originals. Nothing is deleted if preflight fails.")
                }

                GuideSection(title: "Services, priority, and receipts", icon: "point.3.connected.trianglepath.dotted", color: .green) {
                    GuideRow(title: "Local Device Archive", text: "Durable staging on this Mac. Interrupted work resumes from verified files instead of starting over.")
                    GuideRow(title: "NAS storage", text: "Uses the volume mounted by macOS, copies files atomically, and compares SHA-256 before recording success.")
                    GuideRow(title: "Apple Photos, Google Photos, Flickr, and YouTube", text: "Each successful item gets its own receipt. Existing receipts are skipped on catch-up. Google Photos is deliberately paced around its write-request limit; YouTube uploads are private.")
                    GuideRow(title: "Cloud visibility is locked", text: "Camera Zapper has no public-upload mode. Google Photos uses only the append-only scope and never calls sharing APIs. Flickr always sends private and hidden flags. YouTube always sends privacyStatus=private. These settings cannot be changed in the app.")
                    GuideRow(title: "Flickr limits", text: "Flickr accepts photos up to 200 MB and videos up to 1 GB. Camera Zapper logs oversized filenames and continues eligible uploads. If Flickr is required for that media type, an unsupported item correctly blocks source deletion; use YouTube/NAS for large videos or remove Video from Flickr's accepted media.")
                    GuideRow(title: "NeoFinder", text: "Catalogs the verified archive and records catalog receipts. It may be marked required when catalog completion is part of your deletion policy.")
                    Text("A service applies only to media types it accepts. A video-only destination will not block deletion of a photo.")
                        .font(.callout).foregroundStyle(.secondary)
                }

                GuideSection(title: "Android connection checklist", icon: "cable.connector.horizontal", color: .orange) {
                    GuideBullet("Use a USB cable that supports data, not charging only.")
                    GuideBullet("On Samsung: Settings → About phone/tablet → Software information → tap Build number seven times; then Settings → Developer options → USB debugging.")
                    GuideBullet("Reconnect, select File transfer / Android Auto, and approve ‘Always allow from this computer.’")
                    GuideBullet("Keep the device unlocked. If it is missing, use Probe Again, try a direct USB port, revoke USB-debugging authorizations, and approve the Mac again.")
                    GuideBullet("MacDroid, OpenMTP, and other MTP applications can compete for the same interface. Quit them when testing direct access.")
                }

                GuideSection(title: "When an Android tablet does not appear", icon: "ipad.and.iphone.slash", color: .orange) {
                    GuideRow(title: "Android tablet setup", text: "Open Settings → About tablet → Software information and tap Build number seven times. Return to Settings → Developer options, enable USB debugging, reconnect by USB, and select File transfer / Android Auto.")
                    GuideRow(title: "Approve the debugging fingerprint", text: "Keep the tablet unlocked. When ‘Allow USB debugging?’ appears, select ‘Always allow from this computer’ and tap Allow. An authorized device appears by its model name over ADB USB.")
                    GuideRow(title: "If only Nexus 4 appears", text: "MacDroid can expose a legacy Nexus 4 / occam compatibility endpoint when no such physical phone exists. Camera Zapper filters that endpoint. Seeing only Nexus 4 means the actual tablet is still not visible to ADB.")
                    GuideRow(title: "If the prompt never appears", text: "Try a known data-capable cable and a direct Mac USB port. Set USB controlled by This device, choose File transfer rather than Image transfer, then revoke USB debugging authorizations, toggle debugging off and on, reconnect, and approve the Mac again.")
                    GuideRow(title: "If the device says unauthorized", text: "Unlock the tablet and accept the authorization dialog. If another Android utility owns the connection, quit it, use Probe Again, and reconnect. ADB must report the real device as authorized before verified hashing, copying, or deletion can run.")
                }

                GuideSection(title: "Offline use and recovery", icon: "internaldrive.fill.badge.clock", color: .purple) {
                    GuideRow(title: "Away from the NAS", text: "Verified files remain in local staging. Reconnect to the LAN or VPN and run service catch-up later.")
                    GuideRow(title: "Interrupted copy", text: "Partial files are not treated as verified. Restarting scans receipts and safely continues outstanding work.")
                    GuideRow(title: "Interrupted cloud upload", text: "Completed receipts are skipped. If an app is terminated in the tiny interval after a provider accepts a file but before its receipt is written, that one in-flight item may need provider-side duplicate handling.")
                    GuideRow(title: "Interrupted deletion", text: "Reconnect the same device and run Verify & Delete again. Camera Zapper reconciles files already removed and continues with originals still present.")
                }

                GuideSection(title: "Safety and troubleshooting", icon: "exclamationmark.triangle.fill", color: .yellow) {
                    GuideBullet("Beta software: keep an independent backup and test noncritical media before enabling deletion for a new device or destination.")
                    GuideBullet("Required means required. A failed, offline, unauthorized, or quota-limited required service blocks deletion but never invalidates verified copies already completed.")
                    GuideBullet("Credentials are stored in macOS Keychain. Version 1.338 and later consolidate API credentials into one vault to minimize unlock prompts.")
                    GuideBullet("Use Activity and the on-screen operation log when diagnosing a failure. Logs contain filenames and results, so review them before sharing.")
                }

                GroupBox {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Report a bug").font(.headline)
                            Text("Include the app version, device model, connection method, steps to reproduce, and last visible error. Never send passwords, API secrets, OAuth tokens, personal paths, or private filenames.").foregroundStyle(.secondary)
                            Text("Camera Zapper is independently maintained in limited spare time. Every useful report is appreciated, but replies and fixes may take a while—thank you for being patient.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Link("Report a Bug…", destination: URL(string: "mailto:zapper@zebtron.com?subject=Camera%20Zapper%201.350%20bug%20report&body=Please%20describe%20what%20happened%3A%0A%0AWhat%20you%20expected%3A%0A%0ASteps%20to%20reproduce%3A%0A%0ADevice%20model%20and%20connection%20method%3A%0A%0AmacOS%20version%3A%0A%0ALast%20visible%20error%3A%0A%0APlease%20remove%20passwords%2C%20API%20secrets%2C%20OAuth%20tokens%2C%20personal%20paths%2C%20and%20private%20filenames%20before%20sending.")!)
                    }.padding(8)
                }
            }.padding(28).frame(maxWidth: 900, alignment: .leading)
        }.navigationTitle("Help & User Guide")
    }
}

private struct GuideSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 13) { content }
                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
        } label: {
            Label(title, systemImage: icon).font(.title2.bold()).foregroundStyle(color)
        }
    }
}

private struct GuideStep: View {
    let number: Int
    let title: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)").font(.headline).foregroundStyle(.white).frame(width: 28, height: 28).background(.red, in: Circle())
            GuideRow(title: title, text: text)
        }
    }
}

private struct GuideRow: View {
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline)
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct GuideBullet: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).padding(.top, 2)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
