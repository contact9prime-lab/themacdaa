import SwiftUI
import AppKit

/// Screen snapshots captured during calls, each with its AI analysis.
struct ArtifactsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                header("Artifacts", subtitle: "Screenshots captured during calls (⌥⌘S), analyzed by your vision model.")
                Spacer()
                Button {
                    appState.captureScreenshot()
                } label: {
                    Label("Capture now", systemImage: "camera.viewfinder")
                }
                .padding(.trailing).padding(.top)
            }

            if appState.artifacts.isEmpty {
                emptyState("No artifacts yet", "Press ⌥⌘S during a call to snapshot the screen.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(appState.artifacts) { artifact in
                            ArtifactCard(artifact: artifact, appState: appState)
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

struct ArtifactCard: View {
    let artifact: Artifact
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(artifact.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) { appState.deleteArtifact(artifact) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            if let image = NSImage(contentsOfFile: artifact.imagePath) {
                Image(nsImage: image)
                    .resizable().scaledToFit()
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            } else {
                Text("(image missing)").font(.caption).foregroundStyle(.secondary)
            }
            if artifact.analyzing {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Analyzing…").font(.caption).foregroundStyle(.secondary) }
            } else if !artifact.aiText.isEmpty {
                Text(artifact.aiText)
                    .font(.callout).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}
