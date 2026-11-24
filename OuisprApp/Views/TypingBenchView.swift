// OuisprApp/Views/TypingBenchView.swift
// Settings screen of the typing bench: pick the keyboard, type 20 phrases, compare the scores.
import OuisprCore
import SwiftUI
import UIKit

/// Compares Ouispr's keyboard with Apple's on the same phrases, on the user's own iPhone.
///
/// WHY a screen in the app rather than a simulation: the simulated bench
/// (`tools/typing-bench`) draws taps from a model, with no thumb, no habit and no
/// context. Only real typing says whether a change helps. The app cannot tell which
/// keyboard is up (iOS does not expose it), so the user picks the label before starting.
struct TypingBenchView: View {

    static let keyboards = ["Ouispr", "Apple"]

    @State private var keyboard = TypingBenchView.keyboards[0]
    @State private var sessions: [TypingBenchSession] = []
    @State private var isRunning = false
    @State private var showDeleteAll = false

    private let store = TypingBenchStore.shared

    var body: some View {
        List {
            Section {
                Picker("Clavier testé", selection: $keyboard) {
                    ForEach(Self.keyboards, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)

                Button {
                    isRunning = true
                } label: {
                    Label("Commencer (\(TypingBenchPhrases.french.count) phrases)", systemImage: "keyboard")
                }
                .accessibilityIdentifier("typingBench.start")
            } footer: {
                Text("Choisissez ce clavier avec le globe une fois la première phrase affichée. Tapez normalement : corrigez ce que vous corrigeriez dans un vrai message, puis validez avec la touche Retour du clavier. Pour comparer équitablement, alternez : Apple, Ouispr, Ouispr, Apple.")
            }

            if !sessions.isEmpty {
                Section("Résultats par clavier") {
                    ForEach(Self.keyboards, id: \.self) { name in
                        if let score = TypingBenchScoring.score(keyboard: name, in: sessions) {
                            TypingBenchScoreRow(title: name, score: score)
                        }
                    }
                }

                Section("Sessions") {
                    ForEach(sessions.reversed()) { session in
                        if let score = TypingBenchScoring.score(session.trials) {
                            TypingBenchScoreRow(
                                title: "\(session.keyboard) · \(session.date.formatted(.dateTime.day().month().hour().minute()))",
                                score: score
                            )
                        }
                    }
                    .onDelete { offsets in
                        let shown = Array(sessions.reversed())
                        for index in offsets { store.delete(id: shown[index].id) }
                        reload()
                    }
                }

                Section {
                    ShareLink(item: TypingBenchReport.text(sessions: sessions, keyboards: Self.keyboards)) {
                        Label("Partager les résultats", systemImage: "square.and.arrow.up")
                    }
                    Button("Tout supprimer", role: .destructive) { showDeleteAll = true }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.ouisprBackground.ignoresSafeArea())
        .navigationTitle("Banc de frappe")
        .onAppear(perform: reload)
        .fullScreenCover(isPresented: $isRunning, onDismiss: reload) {
            TypingBenchRunView(keyboard: keyboard) { session in
                store.append(session)
            }
        }
        .confirmationDialog("Supprimer toutes les sessions ?", isPresented: $showDeleteAll, titleVisibility: .visible) {
            Button("Tout supprimer", role: .destructive) {
                store.deleteAll()
                reload()
            }
        }
    }

    private func reload() {
        sessions = store.all()
    }
}

/// Speed on the left, accuracy and character errors under it.
private struct TypingBenchScoreRow: View {
    let title: String
    let score: TypingBenchScore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(String(format: "%.1f mots/min", score.wordsPerMinute))
                    .monospacedDigit()
            }
            Text(String(
                format: "%.1f %% de mots justes · %.1f %% d'erreurs de caractères · %d phrases",
                score.wordAccuracy * 100, score.characterErrorRate * 100, score.trialCount
            ))
            .font(.caption)
            .foregroundColor(.secondary)
            .monospacedDigit()
        }
    }
}

/// The run itself: one phrase at a time, the field under it, Return for the next one.
struct TypingBenchRunView: View {

    let keyboard: String
    let onFinish: (TypingBenchSession) -> Void

    @Environment(\.dismiss) private var dismiss

    // A new order each run, so the same phrase does not always come when the
    // user is warmed up (or tired).
    @State private var phrases = TypingBenchPhrases.french.shuffled()
    @State private var index = 0
    @State private var text = ""
    @State private var firstEdit: Date?
    @State private var lastEdit: Date?
    @State private var trials: [TypingBenchTrial] = []
    @State private var result: TypingBenchScore?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                if let result {
                    finished(result)
                } else {
                    Text("Phrase \(index + 1) sur \(phrases.count) · clavier \(keyboard)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(phrases[index])
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("typingBench.target")
                    TypingBenchTextField(text: $text, onEdit: recordEdit, onReturn: next)
                        .frame(height: 44)
                        .padding(.horizontal, 12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.15)))
                        .accessibilityIdentifier("typingBench.field")
                    Text("Validez avec la touche Retour du clavier.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color.ouisprBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(result == nil ? "Arrêter" : "Fermer") { stop() }
                }
            }
        }
    }

    private func finished(_ score: TypingBenchScore) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Terminé avec le clavier \(keyboard)")
                .font(.title2.weight(.semibold))
            Text(String(format: "%.1f mots par minute", score.wordsPerMinute))
            Text(String(format: "%.1f %% de mots justes", score.wordAccuracy * 100))
            Text(String(format: "%.1f %% d'erreurs de caractères", score.characterErrorRate * 100))
        }
        .accessibilityIdentifier("typingBench.result")
    }

    private func recordEdit(_ newText: String) {
        let now = Date()
        if firstEdit == nil, !newText.isEmpty { firstEdit = now }
        lastEdit = now
    }

    private func next() {
        guard result == nil, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let seconds = firstEdit.flatMap { first in lastEdit.map { $0.timeIntervalSince(first) } } ?? 0
        trials.append(TypingBenchTrial(target: phrases[index], typed: text, seconds: seconds))
        text = ""
        firstEdit = nil
        lastEdit = nil
        if index + 1 < phrases.count {
            index += 1
        } else {
            finish()
        }
    }

    private func finish() {
        let session = TypingBenchSession(keyboard: keyboard, trials: trials)
        onFinish(session)
        result = TypingBenchScoring.score(trials)
    }

    /// Stopping early keeps the phrases already typed: they are as valid as a full run.
    private func stop() {
        if result == nil, !trials.isEmpty {
            onFinish(TypingBenchSession(keyboard: keyboard, trials: trials))
        }
        dismiss()
    }
}

/// A UITextField rather than a SwiftUI TextField, for two reasons:
/// - Return must not close the keyboard between phrases (a SwiftUI field loses focus
///   on submit, and the keyboard would bounce 20 times);
/// - autocorrection, spell checking and auto-capitalisation are left at the system
///   defaults on purpose: they are what is being measured.
private struct TypingBenchTextField: UIViewRepresentable {
    @Binding var text: String
    let onEdit: (String) -> Void
    let onReturn: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.returnKeyType = .next
        field.font = .preferredFont(forTextStyle: .title3)
        field.autocorrectionType = .default
        field.spellCheckingType = .default
        field.autocapitalizationType = .sentences
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        // After the view is in a window, or becomeFirstResponder does nothing.
        DispatchQueue.main.async { field.becomeFirstResponder() }
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: TypingBenchTextField

        init(parent: TypingBenchTextField) {
            self.parent = parent
        }

        @objc func changed(_ field: UITextField) {
            let newText = field.text ?? ""
            parent.text = newText
            parent.onEdit(newText)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.text = textField.text ?? ""
            parent.onReturn()
            // false: the field keeps focus and the keyboard stays up for the next phrase.
            return false
        }
    }
}
