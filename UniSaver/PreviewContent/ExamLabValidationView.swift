#if DEBUG
import SwiftUI
import SwiftData

/// A disposable, in-memory workspace for exercising the real Exam Lab UI.
/// PersistenceController selects an in-memory store for this explicit flag.
struct ExamLabValidationView: View {
    @Environment(\.modelContext) private var context
    @State private var quickAdd: QuickAddTarget?
    @State private var seeded = false
    var body: some View {
        VStack(spacing: 0) {
            Text("Exam Lab verification · isolated sample data").font(.caption).padding(8)
            if seeded { ExamLabView(quickAddTarget: $quickAdd) }
        }.frame(minWidth: 1100, minHeight: 800).onAppear(perform: seed)
    }
    private func seed() {
        guard !seeded else { return }
        let course = Course(name: "Biology", code: "LAB")
        let chapter = Chapter(number: 1, title: "Cells and transport", order: 0, course: course)
        let paper = Quiz(title: "Teacher mock · Cells", quizDescription: "UniSaverQuestionBankV1: teacher paper", mode: .exam, course: course, chapter: chapter)
        context.insert(course); context.insert(chapter); context.insert(paper)
        context.insert(QuizQuestion(prompt: "Which structure regulates transport into a cell?", choices: ["A: Membrane", "B: Nucleus", "C: Ribosome"], correctAnswers: ["A"], explanation: "The selectively permeable cell membrane controls movement into and out of cells.", hint: "Think of the cell boundary.", points: 2, tags: ["Transport"], quiz: paper))
        context.insert(QuizQuestion(prompt: "Select both organelles involved in protein production.", type: .multipleSelect, choices: ["A: Ribosome", "B: Rough ER", "C: Lysosome"], correctAnswers: ["A", "B"], explanation: "Ribosomes make proteins; rough ER processes proteins for transport.", points: 3, position: 1, tags: ["Organelles"], quiz: paper))
        context.insert(QuizQuestion(prompt: "All diffusion requires ATP. True or false?", type: .trueFalse, choices: ["True", "False"], correctAnswers: ["False"], explanation: "Diffusion is passive movement down a concentration gradient.", points: 1, position: 2, tags: ["Transport"], quiz: paper))
        let written = QuizQuestion(prompt: "Explain how a membrane controls transport, using an example.", type: .shortAnswer, correctAnswers: ["A selectively permeable membrane allows some molecules to diffuse while transport proteins move others."], explanation: "Relate membrane structure to passive or active transport and give an example.", points: 6, position: 3, tags: ["Transport"], quiz: paper)
        context.insert(written)
        context.insert(QuizQuestion(prompt: "A cell contains 12 units and loses 3. How many remain?", type: .shortAnswer, correctAnswers: ["9"], explanation: "12 minus 3 equals 9.", points: 2, position: 4, tags: ["Calculation"], quiz: paper))
        let generated = Quiz(title: "AI practice · Cell boundaries", quizDescription: "AI-generated practice reviewed by student", course: course, chapter: chapter)
        context.insert(generated)
        context.insert(QuizQuestion(prompt: "Name the cell boundary.", type: .shortAnswer, correctAnswers: ["Membrane"], explanation: "The plasma membrane is the cell boundary.", tags: ["AI-generated"], quiz: generated))
        do {
            try ExamLabService.stage(ExamLabPaperMetadata(quizID: paper.id, rubrics: [written.id: "Describe selective permeability (2); explain a transport mechanism (2); apply an example (2)."], writtenQuestionIDs: [written.id]), context: context)
            try context.save(); seeded = true
        } catch { assertionFailure(error.localizedDescription) }
    }
}
#endif
