import Foundation

protocol SpacedRepetitionScheduling {
    func schedule(state: FlashcardReviewState, rating: FlashcardRating, reviewedAt: Date, calendar: Calendar) -> FlashcardReviewState
}

struct SimpleSpacedRepetitionScheduler: SpacedRepetitionScheduling {
    func schedule(
        state: FlashcardReviewState,
        rating: FlashcardRating,
        reviewedAt: Date = .now,
        calendar: Calendar = .current
    ) -> FlashcardReviewState {
        let oneDay: TimeInterval = 86_400
        var next = state
        next.lastReviewedAt = reviewedAt
        next.lastRating = rating

        switch rating {
        case .again:
            next.lapses += 1
            next.repetitions = 0
            next.ease = max(1.3, state.ease - 0.2)
            next.interval = 10 * 60
        case .hard:
            next.repetitions += 1
            next.ease = max(1.4, state.ease - 0.1)
            next.interval = max(oneDay, max(state.interval, oneDay) * 1.25)
        case .good:
            next.repetitions += 1
            next.ease = state.ease
            next.interval = state.repetitions == 0 ? oneDay : max(oneDay, state.interval * state.ease)
        case .easy:
            next.repetitions += 1
            next.ease = min(3.0, state.ease + 0.15)
            next.interval = state.repetitions == 0 ? 4 * oneDay : max(4 * oneDay, state.interval * (state.ease + 0.35))
        }

        let rawDue = reviewedAt.addingTimeInterval(max(next.interval, 60))
        next.dueDate = max(rawDue, reviewedAt)
        return next
    }
}

enum StudyIntervalFormatter {
    static func label(for interval: TimeInterval) -> String {
        if interval < 3_600 { return "Today" }
        let days = max(1, Int((interval / 86_400).rounded()))
        return days == 1 ? "1 day" : "\(days) days"
    }
}
