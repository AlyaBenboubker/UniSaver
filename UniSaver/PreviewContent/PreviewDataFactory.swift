import Foundation
import SwiftData

enum PreviewDataFactory {
    static func seed(_ context: ModelContext, includeDashboardDemo: Bool = false) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let yearStart = calendar.date(byAdding: .month, value: -1, to: today) ?? today
        let yearEnd = calendar.date(byAdding: .month, value: 10, to: yearStart) ?? today
        let semesterEnd = calendar.date(byAdding: .month, value: 4, to: today) ?? yearEnd

        let year = AcademicYear(name: "Academic Year 2026-2027", startDate: yearStart, endDate: yearEnd)
        let semester = Semester(name: "Semester 1", order: 1, startDate: today, endDate: semesterEnd, academicYear: year)
        let workspace = AppWorkspace(
            firstName: "Alya",
            isDemoWorkspace: includeDashboardDemo,
            flashcardsDue: includeDashboardDemo ? 42 : 0,
            flashcardCourseCount: includeDashboardDemo ? 4 : 0,
            lastStudyActivity: includeDashboardDemo ? calendar.date(byAdding: .hour, value: -6, to: .now) : nil
        )
        context.insert(workspace)
        context.insert(year)
        context.insert(semester)

        let courses = [
            Course(name: "Microeconomics", code: "ECO101", courseDescription: "Markets, incentives, and consumer behavior.", professorName: "Dr. Martin Weber", defaultRoom: "B204", colorIdentifier: "blueViolet", symbolName: "chart.xyaxis.line", credits: 6, status: .inProgress, semester: semester),
            Course(name: "Mathematics", code: "MAT110", professorName: "Prof. Nadia Stein", defaultRoom: "A112", colorIdentifier: "teal", symbolName: "function", credits: 6, status: .inProgress, semester: semester),
            Course(name: "Computing Foundations", code: "CS100", professorName: "Dr. Elise Carter", defaultRoom: "Lab 3", colorIdentifier: "green", symbolName: "terminal", credits: 5, status: .needsReview, semester: semester),
            Course(name: "Organizational Behavior", code: "MGT140", professorName: "Prof. Sofia Keller", defaultRoom: "C301", colorIdentifier: "coral", symbolName: "person.3", credits: 4, status: .notStarted, semester: semester),
            Course(name: "German", code: "GERA2", professorName: "Frau Schneider", defaultRoom: "D018", colorIdentifier: "amber", symbolName: "text.book.closed", credits: 3, status: .inProgress, semester: semester)
        ]

        courses.forEach(context.insert)

        addChapters(["Supply and Demand", "Price Elasticity", "Consumer Choice", "Market Failure"], to: courses[0], statuses: [.mastered, .inProgress, .needsReview, .notStarted], context: context)
        addChapters(["Linear Algebra", "Optimization", "Differential Calculus"], to: courses[1], statuses: [.completed, .inProgress, .notStarted], context: context)
        addChapters(["Python Foundations", "Control Flow", "Data Structures"], to: courses[2], statuses: [.mastered, .completed, .inProgress], context: context)
        addChapters(["Teams and Motivation", "Decision Making", "Leadership Cases"], to: courses[3], statuses: [.inProgress, .notStarted, .notStarted], context: context)
        addChapters(["Campus Life", "Academic Vocabulary", "Presentation Practice"], to: courses[4], statuses: [.completed, .inProgress, .needsReview], context: context)

        addSession("Demand Curves", course: courses[0], chapter: courses[0].chapters.first, dayOffset: 0, hour: 10, room: "B204", type: .lecture, progress: .captured, context: context)
        addSession("Elasticity Workshop", course: courses[0], chapter: courses[0].chapters.first { $0.title == "Price Elasticity" }, dayOffset: 2, hour: 13, room: "B204", type: .tutorial, progress: .captured, context: context)
        addSession("Linear Systems", course: courses[1], chapter: courses[1].chapters.first, dayOffset: 0, hour: 9, room: "A112", type: .lecture, progress: .captured, context: context)
        addSession("Optimization Problem Set", course: courses[1], chapter: courses[1].chapters.first { $0.title == "Optimization" }, dayOffset: 1, hour: 15, room: "A112", type: .tutorial, progress: .captured, context: context)
        addSession("Motivation Theories", course: courses[3], chapter: courses[3].chapters.first, dayOffset: 0, hour: 14, room: "C301", type: .seminar, progress: .captured, context: context)
        addSession("Python Control Flow", course: courses[2], chapter: courses[2].chapters.first { $0.title == "Control Flow" }, dayOffset: 1, hour: 11, room: "Lab 3", type: .lab, progress: .organized, context: context)
        addSession("Data Structures Lab", course: courses[2], chapter: courses[2].chapters.first { $0.title == "Data Structures" }, dayOffset: 4, hour: 11, room: "Lab 3", type: .lab, progress: .captured, context: context)
        addSession("Conversation Practice", course: courses[4], chapter: courses[4].chapters.first, dayOffset: -1, hour: 15, room: "D018", type: .seminar, progress: .reviewed, context: context)

        if includeDashboardDemo {
            addDashboardDemoData(context: context, courses: courses, calendar: calendar, today: today)
            addStudyDemoData(context: context, courses: courses, calendar: calendar, today: today)
        }

        try? context.save()
    }

    private static func addChapters(_ titles: [String], to course: Course, statuses: [AcademicItemStatus], context: ModelContext) {
        for (index, title) in titles.enumerated() {
            let chapter = Chapter(
                number: index + 1,
                title: title,
                chapterDescription: "Core chapter for \(course.name).",
                learningObjectives: ["Understand \(title)", "Prepare practice questions"],
                order: index + 1,
                status: statuses.indices.contains(index) ? statuses[index] : .notStarted,
                course: course
            )
            course.chapters.append(chapter)
            context.insert(chapter)
        }
    }

    private static func addSession(_ title: String, course: Course, chapter: Chapter?, dayOffset: Int, hour: Int, room: String, type: ClassSessionType, progress: SessionProgressStatus, context: ModelContext) {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: .now)) ?? .now
        let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        let end = calendar.date(byAdding: .minute, value: 90, to: start) ?? start.addingTimeInterval(5400)
        let session = ClassSession(number: course.sessions.count + 1, title: title, date: day, startTime: start, endTime: end, room: room, professorName: course.professorName, sessionType: type, progressStatus: progress, course: course, chapter: chapter)
        course.sessions.append(session)
        context.insert(session)
    }

    private static func addDashboardDemoData(context: ModelContext, courses: [Course], calendar: Calendar, today: Date) {
        let micro = courses[0]
        let math = courses[1]
        let computing = courses[2]
        let organization = courses[3]

        let studyStart = calendar.date(bySettingHour: 16, minute: 0, second: 0, of: today) ?? today
        let studyEnd = calendar.date(byAdding: .minute, value: 75, to: studyStart) ?? studyStart.addingTimeInterval(4500)
        context.insert(StudyBlock(title: "Elasticity problem set", startDate: studyStart, endDate: studyEnd, status: .planned, course: micro))

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let inTwoDays = calendar.date(byAdding: .day, value: 2, to: today) ?? today
        let examDay = calendar.date(byAdding: .day, value: 12, to: today) ?? today

        context.insert(AcademicTask(title: "Submit Optimization Sheet", taskDescription: "Finish questions 4-8 and attach derivations.", dueDate: tomorrow, priority: .urgent, estimatedDuration: 5400, course: math))
        context.insert(AcademicTask(title: "Review elasticity notes", taskDescription: "Prepare a clean concept summary before the next class.", dueDate: tomorrow, priority: .high, estimatedDuration: 2700, course: micro, chapter: micro.chapters.first { $0.title == "Price Elasticity" }))
        context.insert(AcademicTask(title: "Python exercises", taskDescription: "Complete loops and functions practice.", dueDate: inTwoDays, priority: .medium, estimatedDuration: 3600, course: computing))
        context.insert(AcademicTask(title: "Case reading", taskDescription: "Read the leadership case and mark two discussion points.", dueDate: inTwoDays, priority: .medium, estimatedDuration: 3000, course: organization))

        let examStart = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: examDay)
        let examEnd = examStart.flatMap { calendar.date(byAdding: .minute, value: 120, to: $0) }
        context.insert(Exam(title: "Microeconomics Midterm", date: examDay, startTime: examStart, endTime: examEnd, room: "B204", examType: .midterm, notes: "Covers supply, demand, and elasticity.", course: micro, chapters: micro.chapters))

        context.insert(ReadingProgress(resourceTitle: "Price Elasticity Reader", currentPage: 38, totalPages: 96, lastOpenedAt: calendar.date(byAdding: .hour, value: -3, to: .now) ?? .now, course: micro, chapter: micro.chapters.first { $0.title == "Price Elasticity" }, coverColorIdentifier: micro.colorIdentifier))
        addContentDemoData(context: context, courses: courses, calendar: calendar)
    }

    private static func addContentDemoData(context: ModelContext, courses: [Course], calendar: Calendar) {
        let fileStore = AcademicFileStore()
        let micro = courses[0]
        let math = courses[1]
        let chapter = micro.chapters.first { $0.title == "Price Elasticity" }
        let session = micro.sessions.first { $0.chapter?.id == chapter?.id } ?? micro.sessions.first

        if let stored = try? fileStore.writeDemoFile(named: "unisaver-demo-price-elasticity.pdf", data: demoPDFData()) {
            let resource = AcademicResource(
                title: "Price Elasticity Reader",
                resourceKind: .pdf,
                originalFileName: stored.originalFileName,
                storedRelativePath: stored.storedRelativePath,
                mimeType: stored.mimeType,
                fileExtension: stored.fileExtension,
                fileSize: stored.fileSize,
                lastOpenedAt: calendar.date(byAdding: .hour, value: -3, to: .now),
                readingProgress: 0.4,
                lastPage: 2,
                pageCount: 5,
                isFavorite: true,
                tags: ["demo", "elasticity"],
                course: micro,
                chapter: chapter,
                session: session
            )
            context.insert(resource)
            context.insert(StudyNote(title: "Elasticity review notes", body: "## Key points\n- Elastic demand responds strongly to price changes.\n- Compare percentage changes in quantity and price.", isPinned: true, course: micro, chapter: chapter, session: session, resource: resource))
        }

        context.insert(StudyNote(title: "Optimization checklist", body: "- [ ] Review constraints\n- [ ] Check derivatives\n- [ ] Submit clean solution", course: math, chapter: math.chapters.first))

        if let storedAudio = try? fileStore.writeDemoFile(named: "unisaver-demo-recording.m4a", data: Data("Demo recording placeholder created by UniSaver.\n".utf8)) {
            context.insert(CourseRecording(title: "Demand Curves lecture recording", storedRelativePath: storedAudio.storedRelativePath, duration: 540, course: micro, chapter: micro.chapters.first, session: micro.sessions.first, notes: "Demo metadata. Replace with a real recording from the recorder."))
        }
    }

    private static func addStudyDemoData(context: ModelContext, courses: [Course], calendar: Calendar, today: Date) {
        let deckSpecs: [(Course, String, [String])] = [
            (courses[0], "Elasticity Core Concepts", ["Price elasticity definition", "Elastic demand", "Inelastic demand", "Unit elastic", "Total revenue test", "Cross elasticity", "Income elasticity", "Demand determinants", "Supply elasticity", "Midpoint method", "Perfectly elastic", "Perfectly inelastic", "Luxury goods", "Necessities", "Substitutes", "Complements"]),
            (courses[1], "Optimization Practice", ["Gradient", "Constraint", "Lagrange multiplier", "Objective function", "Feasible set", "Convexity", "Local optimum", "Global optimum", "Derivative test", "Matrix rank", "Linear independence", "Eigenvalue", "System solution", "Boundary condition", "Partial derivative"]),
            (courses[2], "Python Foundations", ["Variable", "Function", "Loop", "Conditional", "List", "Dictionary", "Tuple", "Set", "Module", "Exception", "Class", "Method", "Parameter", "Return value", "Debugging", "Complexity"]),
            (courses[4], "German Academic Vocabulary", ["Vorlesung", "Seminar", "Prüfung", "Hausarbeit", "Bibliothek", "Sprechstunde", "Abgabe", "Kapitel", "Zusammenfassung", "Übung", "Forschung", "Quelle", "Beispiel", "Frage", "Antwort"])
        ]

        for (course, title, terms) in deckSpecs {
            let deck = StudyDeck(
                title: title,
                deckDescription: "Demo deck for \(course.name).",
                colorIdentifier: course.colorIdentifier,
                symbolName: course.symbolName ?? "rectangle.stack.fill",
                course: course,
                chapter: course.chapters.first
            )
            context.insert(deck)
            for (index, term) in terms.enumerated() {
                let dueOffset = index % 4 == 0 ? -1 : index % 4
                let dueDate = calendar.date(byAdding: .day, value: dueOffset, to: today) ?? today
                let card = Flashcard(
                    front: "Explain \(term)",
                    back: "A concise academic explanation of \(term) in \(course.name).",
                    hint: "Connect it to \(course.chapters.first?.title ?? course.name).",
                    explanation: "Demo content. Replace with your own course-specific explanation after review.",
                    tags: [course.code.lowercased(), "demo"],
                    position: index,
                    reviewState: FlashcardReviewState(dueDate: dueDate, interval: Double(max(index, 1)) * 86_400, repetitions: index % 3, lastReviewedAt: calendar.date(byAdding: .day, value: -index, to: today)),
                    deck: deck
                )
                deck.cards.append(card)
                context.insert(card)
            }
        }

        let microQuiz = Quiz(title: "Elasticity Practice Quiz", quizDescription: "Demo QCM for price elasticity.", mode: .practice, course: courses[0], chapter: courses[0].chapters.first { $0.title == "Price Elasticity" })
        let mathQuiz = Quiz(title: "Optimization Check", quizDescription: "Short exam-mode practice.", mode: .exam, course: courses[1], chapter: courses[1].chapters.first { $0.title == "Optimization" })
        context.insert(microQuiz)
        context.insert(mathQuiz)

        let questions = [
            QuizQuestion(prompt: "If demand is elastic, what happens to total revenue when price decreases?", type: .multipleChoice, choices: ["A: It decreases", "B: It increases", "C: It stays constant", "D: Quantity stays constant"], correctAnswers: ["B"], explanation: "Quantity rises proportionally more than price falls.", position: 0, tags: ["elasticity"], quiz: microQuiz),
            QuizQuestion(prompt: "True or false: A binding constraint affects the feasible solution.", type: .trueFalse, choices: ["True", "False"], correctAnswers: ["True"], explanation: "A binding constraint is active at the optimum.", position: 0, tags: ["optimization"], quiz: mathQuiz),
            QuizQuestion(prompt: "Name one condition checked in constrained optimization.", type: .shortAnswer, choices: [], correctAnswers: ["constraint"], explanation: "Constraints define feasible solutions.", position: 1, tags: ["optimization"], quiz: mathQuiz)
        ]
        questions.forEach { question in
            context.insert(question)
            question.quiz?.questions.append(question)
        }
        let attempt = QuizAttempt(startedAt: calendar.date(byAdding: .day, value: -1, to: today) ?? today, completedAt: today, score: 1, maximumScore: 1, answers: ["B"], duration: 180, isCompleted: true, quiz: microQuiz)
        microQuiz.attempts.append(attempt)
        context.insert(attempt)
        let continuing = QuizAttempt(startedAt: calendar.date(byAdding: .hour, value: -2, to: .now) ?? .now, answers: ["True"], duration: 90, isCompleted: false, quiz: mathQuiz)
        mathQuiz.attempts.append(continuing)
        context.insert(continuing)
    }

    private static func demoPDFData() -> Data {
        let text = """
        %PDF-1.4
        1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
        2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
        3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >> endobj
        4 0 obj << /Length 145 >> stream
        BT
        /F1 24 Tf
        72 720 Td
        (UniSaver Demo Reader) Tj
        /F1 14 Tf
        0 -40 Td
        (Original demo PDF for testing the integrated reader.) Tj
        0 -24 Td
        (Topic: Price Elasticity) Tj
        ET
        endstream endobj
        5 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj
        xref
        0 6
        0000000000 65535 f 
        0000000009 00000 n 
        0000000058 00000 n 
        0000000115 00000 n 
        0000000241 00000 n 
        0000000440 00000 n 
        trailer << /Root 1 0 R /Size 6 >>
        startxref
        510
        %%EOF
        """
        return Data(text.utf8)
    }
}
