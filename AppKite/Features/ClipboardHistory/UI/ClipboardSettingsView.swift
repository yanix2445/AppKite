import AppKit
import Carbon
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardSettingsView: View {
    let history: ClipboardHistoryState

    @State private var monitor: Any?
    @State private var recordingHint: LocalizedStringResource?

    var body: some View {
        Form {
            LabeledContent("Ouvrir l’historique") {
                Button(monitor == nil ? history.shortcut.label : "Appuie sur le raccourci…") {
                    if monitor == nil {
                        beginRecording()
                    } else {
                        stopRecording()
                    }
                }
                .accessibilityIdentifier("clipboard-shortcut")
            }

            if let message = recordingHint ?? history.shortcutMessage {
                Text(message)
                    .foregroundStyle(.secondary)
            }

            ClipboardCollectionSettings(history: history)
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 370)
        .onDisappear(perform: stopRecording)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) {
            _ in
            stopRecording()
        }
    }

    private func beginRecording() {
        recordingHint = "Échap pour annuler."
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
            } else if let shortcut = ClipboardShortcut(event: event) {
                history.setShortcut(shortcut)
                stopRecording()
            } else {
                recordingHint = "Choisis une touche avec au moins un modificateur."
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        recordingHint = nil
    }
}

private struct ClipboardCollectionSettings: View {
    let history: ClipboardHistoryState

    @State private var isChoosingApplication = false
    @State private var importerFailed = false

    var body: some View {
        Section("Confidentialité") {
            Toggle(
                "Ignorer les copies signalées comme confidentielles",
                isOn: Binding(
                    get: { history.ignoresConfidentialCopies },
                    set: history.setIgnoresConfidentialCopies
                )
            )
        }

        Section("Applications exclues") {
            ForEach(history.excludedApplications) { application in
                LabeledContent {
                    Button(role: .destructive) {
                        history.removeExcludedApplication(application)
                    } label: {
                        Label(
                            "Retirer \(application.name) des exclusions",
                            systemImage: "minus.circle"
                        )
                        .labelStyle(.iconOnly)
                    }
                } label: {
                    Text(application.name)
                }
            }
            Button("Ajouter une application…") {
                importerFailed = false
                isChoosingApplication = true
            }
            if importerFailed {
                Text("Impossible d’ouvrir l’application sélectionnée.")
                    .foregroundStyle(.secondary)
            } else if let message = history.settingsMessage {
                Text(message)
                    .foregroundStyle(.secondary)
            }
        }
        .fileImporter(
            isPresented: $isChoosingApplication, allowedContentTypes: [.applicationBundle]
        ) {
            result in
            switch result {
            case .success(let url):
                let isAccessing = url.startAccessingSecurityScopedResource()
                defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
                history.addExcludedApplication(at: url)
            case .failure:
                importerFailed = true
            }
        }
    }
}

#if DEBUG
    #Preview("Réglages du presse-papiers") {
        ClipboardSettingsView(history: .preview)
    }
#endif
