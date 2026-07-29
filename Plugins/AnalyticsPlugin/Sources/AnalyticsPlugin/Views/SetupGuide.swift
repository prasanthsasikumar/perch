import AppKit
import SwiftUI

/// What to do in Google before Perch can read anything.
///
/// Four consoles are involved and none of them are where you would guess, so
/// the steps live next to the button that needs them rather than in a README
/// nobody has open at the time.
struct SetupGuide: View {
    let clientEmail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Getting a service-account key")
                .font(.headline)

            Step(number: 1, title: "Create a service account") {
                Text("In Google Cloud, under IAM & Admin.")
                Link(
                    "Open Service Accounts",
                    destination: URL(string: "https://console.cloud.google.com/iam-admin/serviceaccounts")!
                )
            }

            Step(number: 2, title: "Download a JSON key") {
                Text("On the account's **Keys** tab: Add Key › Create new key › JSON.")
                Text("Google only hands this file over once. If you lose it, delete the old key and make a new one.")
                    .foregroundStyle(.secondary)
            }

            Step(number: 3, title: "Enable the APIs") {
                Link(
                    "Analytics Data API",
                    destination: URL(string: "https://console.cloud.google.com/apis/library/analyticsdata.googleapis.com")!
                )
                Text("Required. **Admin API** as well, if you want Perch to find your properties for you.")
                Link(
                    "Analytics Admin API",
                    destination: URL(string: "https://console.cloud.google.com/apis/library/analyticsadmin.googleapis.com")!
                )
            }

            Step(number: 4, title: "Share your properties with it") {
                Text("In GA4: Admin › Property access management › add the account as a **Viewer**.")
                if let clientEmail {
                    HStack(spacing: 4) {
                        Text(clientEmail)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(clientEmail, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy the address")
                    }
                } else {
                    // The address is inside the key file, so there is nothing
                    // to copy until one has been imported.
                    Text("The address appears here once you've chosen a key.")
                        .foregroundStyle(.secondary)
                }
                Link("Open Google Analytics", destination: URL(string: "https://analytics.google.com")!)
            }

            Divider()

            Text("Perch reads the key file once and stores it in your login Keychain. It doesn't keep the file or remember where it was.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 340)
    }
}

private struct Step<Content: View>: View {
    let number: Int
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(.tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                content
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
