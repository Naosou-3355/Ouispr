// OuisprApp/Views/DictationCollectionView.swift
// Settings screen of the opt-in collection mode: toggle, collected dictations, corrections, export to a Mac.
import AVFoundation
import OuisprCore
import SwiftUI
import UIKit

/// Lets the user collect their own dictations (audio, raw transcript, cleaned text)
/// and write what each one should have been, then send everything to a Mac as a zip.
///
/// WHY it reads the store on appear rather than observing it: samples are written
/// by the dictation pipeline in the background, and this screen is only ever open
/// between dictations. A fresh read when it appears is always current.
struct DictationCollectionView: View {

    @State private var isEnabled = DictationSampleStore.shared.isEnabled
    @State private var samples: [DictationSample] = []
    @State private var exportURL: URL?
    @State private var exportFailed = false
    @State private var showDeleteAll = false

    private let store = DictationSampleStore.shared

    var body: some View {
        List {
            Section {
                Toggle("Collecter mes dictées", isOn: $isEnabled)
                    .onChange(of: isEnabled) { _, newValue in store.isEnabled = newValue }
            } footer: {
                Text("Garde, pour chaque dictée, l'audio, le texte brut et le texte nettoyé, sur cet iPhone uniquement. Ajoutez la bonne version pour en faire un banc de test avec votre voix.")
            }

            Section {
                Button {
                    export()
                } label: {
                    Label("Exporter vers le Mac (AirDrop)", systemImage: "square.and.arrow.up")
                }
                .disabled(samples.isEmpty)
            } footer: {
                Text("\(samples.count) dictée(s), \(correctedCount) corrigée(s). Un fichier .zip : un dossier par dictée (audio.wav, sample.json) et manifest.json.")
            }

            if !samples.isEmpty {
                Section("Dictées collectées") {
                    ForEach(samples) { sample in
                        NavigationLink {
                            DictationSampleDetailView(sample: sample) { reload() }
                        } label: {
                            DictationSampleRow(sample: sample)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { store.delete(id: samples[index].id) }
                        reload()
                    }
                }

                Section {
                    Button("Tout supprimer", role: .destructive) { showDeleteAll = true }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.ouisprBackground.ignoresSafeArea())
        .navigationTitle("Collecte de dictées")
        .onAppear(perform: reload)
        .confirmationDialog("Supprimer toutes les dictées collectées ?", isPresented: $showDeleteAll, titleVisibility: .visible) {
            Button("Tout supprimer", role: .destructive) {
                store.deleteAll()
                reload()
            }
        }
        .alert("Export impossible", isPresented: $exportFailed) {
            Button("OK", role: .cancel) {}
        }
        .sheet(isPresented: Binding(
            get: { exportURL != nil },
            set: { if !$0 { exportURL = nil } }
        )) {
            if let exportURL {
                CollectionShareSheet(items: [exportURL])
            }
        }
    }

    private var correctedCount: Int {
        samples.filter { $0.correction != nil }.count
    }

    private func reload() {
        samples = store.all()
    }

    private func export() {
        do {
            exportURL = try store.makeExportArchive()
        } catch {
            exportFailed = true
        }
    }
}

/// One line of the list: date, duration, and the final text.
private struct DictationSampleRow: View {
    let sample: DictationSample

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(sample.createdAt, format: .dateTime.day().month().hour().minute())
                Text(String(format: "%.0f s", sample.durationSeconds))
                Spacer()
                if sample.correction != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            Text(sample.correction ?? sample.finalText)
                .lineLimit(2)
        }
    }
}

/// One dictation: listen, read both texts, write the right version.
private struct DictationSampleDetailView: View {
    let sample: DictationSample
    let onChange: () -> Void

    @State private var correction: String
    @State private var player: AVAudioPlayer?

    private let store = DictationSampleStore.shared

    init(sample: DictationSample, onChange: @escaping () -> Void) {
        self.sample = sample
        self.onChange = onChange
        // Prefilled with the best text so far: a correction is usually a few words.
        _correction = State(initialValue: sample.correction ?? sample.finalText)
    }

    var body: some View {
        Form {
            Section {
                Button {
                    togglePlayback()
                } label: {
                    Label(player?.isPlaying == true ? "Arrêter" : "Écouter",
                          systemImage: player?.isPlaying == true ? "stop.fill" : "play.fill")
                }
            }
            Section("Texte brut") {
                Text(sample.raw).textSelection(.enabled)
            }
            Section("Texte nettoyé") {
                Text(sample.polished ?? "—").textSelection(.enabled)
            }
            Section {
                TextEditor(text: $correction)
                    .frame(minHeight: 120)
            } header: {
                Text("Bonne version")
            } footer: {
                Text("Ce que vous vouliez obtenir. Enregistrée en quittant l'écran.")
            }
        }
        .navigationTitle("Dictée")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            player?.stop()
            // Saved only when it says something new: an untouched prefill is not a correction.
            let trimmed = correction.trimmingCharacters(in: .whitespacesAndNewlines)
            let untouched = sample.correction == nil && trimmed == sample.finalText
            guard !untouched, trimmed != sample.correction else { return }
            store.setCorrection(trimmed, for: sample.id)
            onChange()
        }
    }

    private func togglePlayback() {
        if let player, player.isPlaying {
            player.stop()
            self.player = nil
            return
        }
        guard let url = store.audioURL(for: sample.id) else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}

/// The system share sheet, for AirDrop to the Mac.
private struct CollectionShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
