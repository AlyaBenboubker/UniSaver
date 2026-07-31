import SwiftUI

struct CourseIcon: Identifiable, Hashable {
    let symbolName: String
    let title: String
    let category: String
    let keywords: [String]

    var id: String { symbolName }
}

enum CourseIconCatalog {
    static let defaultSymbolName = "book.closed.fill"

    static let icons: [CourseIcon] = [
        icon("book.closed.fill", "Closed book", "Recommended", ["book", "course", "study"]),
        icon("book.closed", "Book outline", "Recommended", ["book", "course", "study"]),
        icon("books.vertical.fill", "Books", "Recommended", ["library", "course", "study"]),
        icon("graduationcap.fill", "Graduation cap", "Recommended", ["school", "university"]),
        icon("studentdesk", "Study desk", "Recommended", ["desk", "study"]),
        icon("pencil.and.list.clipboard", "Syllabus", "Recommended", ["syllabus", "tasks"]),
        icon("calendar", "Calendar", "Recommended", ["schedule", "planner"]),
        icon("calendar.badge.plus", "Add session", "Recommended", ["schedule", "planner", "session"]),
        icon("list.number", "Numbered list", "Recommended", ["chapters", "outline"]),
        icon("doc.text.magnifyingglass", "Research", "Recommended", ["research", "reading"]),
        icon("note.text", "Notes", "Recommended", ["notes", "writing"]),
        icon("rectangle.stack.badge.play.fill", "Practice stack", "Recommended", ["study", "practice"]),
        icon("timer", "Timer", "Recommended", ["focus", "study"]),
        icon("star.circle.fill", "Priority", "Recommended", ["favorite", "important"]),
        icon("pin.fill", "Pinned", "Recommended", ["important", "course"]),
        icon("tray.full", "Desk tray", "Recommended", ["study", "resources"]),
        icon("chart.line.uptrend.xyaxis", "Trend chart", "Business & Economics", ["economics", "business", "finance"]),
        icon("chart.xyaxis.line", "Line chart", "Business & Economics", ["economics", "chart"]),
        icon("chart.bar.fill", "Bar chart", "Business & Economics", ["statistics", "business"]),
        icon("dollarsign.circle.fill", "Dollar", "Business & Economics", ["money", "economics"]),
        icon("eurosign.circle.fill", "Euro", "Business & Economics", ["money", "economics"]),
        icon("creditcard.fill", "Credit card", "Business & Economics", ["finance", "business"]),
        icon("briefcase.fill", "Briefcase", "Business & Economics", ["business", "management"]),
        icon("building.2.fill", "Company", "Business & Economics", ["organization", "business"]),
        icon("person.3.fill", "Organization", "Business & Economics", ["management", "teams"]),
        icon("person.3", "Team", "Business & Economics", ["management", "teams"]),
        icon("banknote.fill", "Banknote", "Business & Economics", ["money", "finance"]),
        icon("case.fill", "Case", "Business & Economics", ["business", "management"]),
        icon("shippingbox.fill", "Operations", "Business & Economics", ["business", "operations"]),
        icon("cart.fill", "Market", "Business & Economics", ["economics", "commerce"]),
        icon("arrow.up.arrow.down.circle.fill", "Exchange", "Business & Economics", ["economics", "markets"]),
        icon("arrow.up.right.circle.fill", "Growth", "Business & Economics", ["economics", "growth"]),
        icon("chart.pie.fill", "Pie chart", "Business & Economics", ["business", "statistics"]),
        icon("person.crop.rectangle.stack.fill", "Customers", "Business & Economics", ["marketing", "business"]),
        icon("storefront.fill", "Storefront", "Business & Economics", ["market", "commerce"]),
        icon("function", "Function", "Mathematics", ["math", "mathematics", "calculus"]),
        icon("sum", "Sum", "Mathematics", ["math", "algebra"]),
        icon("percent", "Percent", "Mathematics", ["math", "statistics"]),
        icon("plus.forwardslash.minus", "Plus minus", "Mathematics", ["math"]),
        icon("x.squareroot", "Square root", "Mathematics", ["math", "algebra"]),
        icon("divide", "Divide", "Mathematics", ["math"]),
        icon("number", "Number", "Mathematics", ["math"]),
        icon("angle", "Angle", "Mathematics", ["geometry", "math"]),
        icon("circle.grid.cross.fill", "Coordinate grid", "Mathematics", ["math", "geometry"]),
        icon("ruler", "Measure", "Mathematics", ["math", "geometry"]),
        icon("compass.drawing", "Compass", "Mathematics", ["math", "geometry"]),
        icon("chart.dots.scatter", "Scatter plot", "Mathematics", ["math", "statistics"]),
        icon("equal.circle.fill", "Equation", "Mathematics", ["math", "algebra"]),
        icon("greaterthan.circle.fill", "Comparison", "Mathematics", ["math", "algebra"]),
        icon("lessthan.circle.fill", "Inequality", "Mathematics", ["math", "algebra"]),
        icon("infinity.circle.fill", "Infinity", "Mathematics", ["math", "calculus"]),
        icon("point.3.connected.trianglepath.dotted", "Graph", "Mathematics", ["math", "graph"]),
        icon("terminal.fill", "Terminal", "Computing", ["code", "computer", "programming"]),
        icon("terminal", "Terminal outline", "Computing", ["code", "computer", "programming"]),
        icon("chevron.left.forwardslash.chevron.right", "Code", "Computing", ["code", "programming"]),
        icon("desktopcomputer", "Desktop", "Computing", ["computer", "technology"]),
        icon("cpu.fill", "CPU", "Computing", ["hardware", "computer"]),
        icon("network", "Network", "Computing", ["systems", "internet"]),
        icon("server.rack", "Server", "Computing", ["backend", "systems"]),
        icon("curlybraces", "Curly braces", "Computing", ["code"]),
        icon("apple.terminal.fill", "Command line", "Computing", ["terminal", "code"]),
        icon("laptopcomputer", "Laptop", "Computing", ["computer", "technology"]),
        icon("memorychip.fill", "Memory chip", "Computing", ["hardware", "computer"]),
        icon("wifi", "Wi-Fi", "Computing", ["network", "internet"]),
        icon("lock.shield.fill", "Security", "Computing", ["cybersecurity", "security"]),
        icon("key.fill", "Key", "Computing", ["security", "systems"]),
        icon("externaldrive.fill", "Storage", "Computing", ["storage", "data"]),
        icon("keyboard.fill", "Keyboard", "Computing", ["code", "computer"]),
        icon("display", "Display", "Computing", ["computer"]),
        icon("icloud.fill", "Cloud", "Computing", ["cloud", "network"]),
        icon("link", "Link", "Computing", ["network", "web"]),
        icon("atom", "Atom", "Science", ["science", "physics"]),
        icon("flask.fill", "Flask", "Science", ["chemistry", "science"]),
        icon("testtube.2", "Test tubes", "Science", ["chemistry", "lab"]),
        icon("leaf.fill", "Leaf", "Science", ["biology", "environment"]),
        icon("hare.fill", "Biology", "Science", ["biology"]),
        icon("waveform.path.ecg", "Signal", "Science", ["science", "signal"]),
        icon("globe.europe.africa.fill", "World", "Science", ["geography", "global"]),
        icon("mountain.2.fill", "Earth science", "Science", ["geology", "science"]),
        icon("drop.fill", "Water", "Science", ["chemistry", "environment"]),
        icon("thermometer.medium", "Temperature", "Science", ["physics", "science"]),
        icon("sparkles", "Discovery", "Science", ["science"]),
        icon("microbe.fill", "Microbe", "Science", ["biology", "science"]),
        icon("fossil.shell.fill", "Fossil", "Science", ["biology", "geology"]),
        icon("sun.max.fill", "Astronomy", "Science", ["science", "space"]),
        icon("moon.stars.fill", "Night sky", "Science", ["science", "space"]),
        icon("tornado", "Weather", "Science", ["science", "climate"]),
        icon("scalemass.fill", "Scales", "Law & Politics", ["law", "justice"]),
        icon("building.columns.fill", "Institution", "Law & Politics", ["law", "politics"]),
        icon("scroll.fill", "Scroll", "Law & Politics", ["law", "history"]),
        icon("signature", "Signature", "Law & Politics", ["law", "contract"]),
        icon("hand.raised.fill", "Debate", "Law & Politics", ["politics", "law"]),
        icon("checkmark.seal.fill", "Policy", "Law & Politics", ["law", "politics"]),
        icon("person.badge.shield.checkmark.fill", "Public service", "Law & Politics", ["law", "politics"]),
        icon("megaphone.fill", "Campaign", "Law & Politics", ["politics"]),
        icon("doc.plaintext.fill", "Legal text", "Law & Politics", ["law", "document"]),
        icon("person.text.rectangle.fill", "Civic identity", "Law & Politics", ["law", "politics"]),
        icon("shield.lefthalf.filled", "Rights", "Law & Politics", ["law", "policy"]),
        icon("rectangle.and.pencil.and.ellipsis", "Legislation", "Law & Politics", ["law", "policy"]),
        icon("globe", "Globe", "Languages", ["language", "international"]),
        icon("character.book.closed.fill", "Language book", "Languages", ["language", "book"]),
        icon("textformat.abc", "Alphabet", "Languages", ["language", "writing"]),
        icon("bubble.left.and.bubble.right.fill", "Conversation", "Languages", ["speaking", "language"]),
        icon("translate", "Translate", "Languages", ["language"]),
        icon("text.book.closed.fill", "Textbook", "Languages", ["language", "reading"]),
        icon("text.book.closed", "Textbook outline", "Languages", ["language", "reading"]),
        icon("captions.bubble.fill", "Captions", "Languages", ["language", "speaking"]),
        icon("speaker.wave.2.fill", "Listening", "Languages", ["language", "audio"]),
        icon("character.cursor.ibeam", "Writing", "Languages", ["language", "writing"]),
        icon("text.bubble.fill", "Dialogue", "Languages", ["language", "speaking"]),
        icon("mic.fill", "Speaking", "Languages", ["language", "speaking"]),
        icon("ear.fill", "Listening", "Languages", ["language", "audio"]),
        icon("highlighter", "Vocabulary", "Languages", ["language", "writing"]),
        icon("person.2.fill", "People", "Humanities", ["society", "humanities"]),
        icon("brain.head.profile", "Psychology", "Humanities", ["psychology", "brain"]),
        icon("theatermasks.fill", "Theater", "Humanities", ["culture", "arts"]),
        icon("newspaper.fill", "Journalism", "Humanities", ["media", "writing"]),
        icon("quote.bubble.fill", "Discussion", "Humanities", ["debate", "writing"]),
        icon("building.columns", "History", "Humanities", ["history", "culture"]),
        icon("map.fill", "Geography", "Humanities", ["geography", "society"]),
        icon("figure.mind.and.body", "Philosophy", "Humanities", ["philosophy"]),
        icon("person.fill.questionmark", "Sociology", "Humanities", ["society", "people"]),
        icon("book.pages.fill", "Literature", "Humanities", ["reading", "culture"]),
        icon("bubble.middle.bottom.fill", "Argument", "Humanities", ["debate", "writing"]),
        icon("photo.artframe", "Culture", "Humanities", ["culture", "history"]),
        icon("paintpalette.fill", "Palette", "Arts & Design", ["art", "design"]),
        icon("music.note", "Music", "Arts & Design", ["music", "arts"]),
        icon("camera.fill", "Camera", "Arts & Design", ["photo", "media"]),
        icon("film.fill", "Film", "Arts & Design", ["media", "cinema"]),
        icon("paintbrush.fill", "Brush", "Arts & Design", ["design", "art"]),
        icon("wand.and.stars", "Creative tools", "Arts & Design", ["design", "art"]),
        icon("rectangle.3.group.fill", "Layout", "Arts & Design", ["design", "layout"]),
        icon("eyedropper.full", "Color", "Arts & Design", ["design", "color"]),
        icon("camera.aperture", "Aperture", "Arts & Design", ["photo", "media"]),
        icon("waveform", "Audio", "Arts & Design", ["music", "media"]),
        icon("scribble.variable", "Sketching", "Arts & Design", ["art", "design"]),
        icon("lasso", "Selection", "Arts & Design", ["design"]),
        icon("stethoscope", "Stethoscope", "Health", ["medicine", "health"]),
        icon("cross.case.fill", "Medical case", "Health", ["medicine", "health"]),
        icon("heart.text.square.fill", "Care", "Health", ["health"]),
        icon("pills.fill", "Pharmacy", "Health", ["medicine"]),
        icon("lungs.fill", "Respiration", "Health", ["medicine", "health"]),
        icon("brain.fill", "Neuroscience", "Health", ["medicine", "brain"]),
        icon("bandage.fill", "Clinical care", "Health", ["medicine", "health"]),
        icon("syringe.fill", "Injection", "Health", ["medicine", "health"]),
        icon("facemask.fill", "Public health", "Health", ["medicine", "health"]),
        icon("heart.fill", "Heart", "Health", ["medicine", "health"]),
        icon("figure.walk", "Movement", "Health", ["health"]),
        icon("wrench.and.screwdriver.fill", "Tools", "Engineering", ["engineering"]),
        icon("gearshape.2.fill", "Gears", "Engineering", ["engineering", "mechanics"]),
        icon("hammer.fill", "Build", "Engineering", ["engineering"]),
        icon("ruler.fill", "Ruler", "Engineering", ["design", "engineering"]),
        icon("bolt.fill", "Electrical", "Engineering", ["engineering", "electricity"]),
        icon("antenna.radiowaves.left.and.right", "Signals", "Engineering", ["engineering", "signals"]),
        icon("car.fill", "Mechanical systems", "Engineering", ["engineering", "mechanical"]),
        icon("fuelpump.fill", "Energy systems", "Engineering", ["engineering", "energy"]),
        icon("powerplug.fill", "Power", "Engineering", ["engineering", "electricity"]),
        icon("fan.fill", "Mechanical", "Engineering", ["engineering", "mechanical"]),
        icon("pipe.and.drop.fill", "Fluids", "Engineering", ["engineering"]),
        icon("rotate.3d.fill", "3D systems", "Engineering", ["engineering", "design"]),
        icon("lightbulb.fill", "Idea", "General Study", ["idea", "study"]),
        icon("bookmark.fill", "Bookmark", "General Study", ["reading", "study"]),
        icon("doc.text.fill", "Document", "General Study", ["document", "study"]),
        icon("folder.fill", "Folder", "General Study", ["files", "resources"]),
        icon("tray.full.fill", "Archive", "General Study", ["resources"]),
        icon("checklist", "Checklist", "General Study", ["tasks"]),
        icon("clock.fill", "Clock", "General Study", ["time", "schedule"]),
        icon("target", "Target", "General Study", ["goals"]),
        icon("flag.fill", "Flag", "General Study", ["priority"]),
        icon("paperclip", "Attachment", "General Study", ["resources"]),
        icon("tray.and.arrow.down.fill", "Import", "General Study", ["resources", "files"]),
        icon("rectangle.stack.fill", "Flashcards", "General Study", ["study", "flashcards"]),
        icon("questionmark.circle.fill", "Quiz", "General Study", ["study", "quiz"])
    ]

    static let categories: [String] = icons.reduce(into: []) { categories, icon in
        if !categories.contains(icon.category) {
            categories.append(icon.category)
        }
    }

    static func sanitizedSymbolName(_ symbolName: String?) -> String {
        let trimmed = symbolName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return defaultSymbolName }
        if icons.contains(where: { $0.symbolName == trimmed }) {
            return trimmed
        }
        return defaultSymbolName
    }

    static func icon(for symbolName: String) -> CourseIcon? {
        icons.first { $0.symbolName == symbolName }
    }

    static func matches(_ icon: CourseIcon, query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        guard !normalized.isEmpty else { return true }
        return icon.symbolName.localizedCaseInsensitiveContains(normalized)
            || icon.title.localizedCaseInsensitiveContains(normalized)
            || icon.category.localizedCaseInsensitiveContains(normalized)
            || icon.keywords.contains { $0.localizedCaseInsensitiveContains(normalized) }
    }

    private static func icon(_ symbolName: String, _ title: String, _ category: String, _ keywords: [String]) -> CourseIcon {
        CourseIcon(symbolName: symbolName, title: title, category: category, keywords: keywords)
    }
}

struct CourseIconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("recentCourseIconSymbols") private var recentSymbols = ""
    @Binding var selectedSymbolName: String
    let colorIdentifier: String
    @State private var draftSymbolName: String
    @State private var searchText = ""
    @State private var selectedCategory = "All"

    init(selectedSymbolName: Binding<String>, colorIdentifier: String) {
        _selectedSymbolName = selectedSymbolName
        self.colorIdentifier = colorIdentifier
        _draftSymbolName = State(initialValue: CourseIconCatalog.sanitizedSymbolName(selectedSymbolName.wrappedValue))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let contentMaxWidth = proxy.size.width >= 900 ? 1040.0 : 760.0
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        pickerPreview
                        searchField
                        categoryChips
                        if !recentIcons.isEmpty && searchText.isEmpty {
                            recentIconsSection
                        }
                        iconSection(sectionTitle, icons: visibleIcons, width: proxy.size.width)
                    }
                    .padding(20)
                    .frame(maxWidth: contentMaxWidth)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(StudyDeskTheme.backgroundPrimary)
            .navigationTitle("Choose an icon")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        selectedSymbolName = draftSymbolName
                        remember(draftSymbolName)
                        dismiss()
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search icons", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chipCategories, id: \.self) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        Text(displayName(for: category))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedCategory == category ? CourseColor.color(for: colorIdentifier).opacity(0.16) : StudyDeskTheme.surfacePrimary, in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(selectedCategory == category ? CourseColor.color(for: colorIdentifier) : StudyDeskTheme.borderSubtle, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(selectedCategory == category ? "Selected" : "Not selected")
                }
            }
            .padding(.vertical, 2)
            .padding(.trailing, 20)
        }
    }

    private var pickerPreview: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(CourseColor.color(for: colorIdentifier).opacity(0.14))
                Image(systemName: draftSymbolName)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(CourseColor.color(for: colorIdentifier))
            }
            .frame(width: 68, height: 68)
            VStack(alignment: .leading, spacing: 4) {
                Text(CourseIconCatalog.icon(for: draftSymbolName)?.title ?? "Course icon")
                    .font(.headline.weight(.bold))
                Text(CourseIconCatalog.icon(for: draftSymbolName)?.category ?? "General Study")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .deskCard()
    }

    private var filteredCategories: [String] {
        CourseIconCatalog.categories.filter { !filteredIcons(in: $0).isEmpty }
    }

    private var chipCategories: [String] {
        ["All"] + CourseIconCatalog.categories
    }

    private var visibleIcons: [CourseIcon] {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return CourseIconCatalog.icons.filter { CourseIconCatalog.matches($0, query: searchText) }
        }
        if selectedCategory == "All" {
            return CourseIconCatalog.icons
        }
        return CourseIconCatalog.icons.filter { $0.category == selectedCategory }
    }

    private var sectionTitle: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedCategory : "Search results"
    }

    private var recentIcons: [CourseIcon] {
        recentSymbols
            .split(separator: "|")
            .compactMap { CourseIconCatalog.icon(for: String($0)) }
            .filter { CourseIconCatalog.matches($0, query: searchText) }
    }

    private var recentIconsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recently used")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(recentIcons.prefix(8))) { icon in
                        CourseIconCell(
                            icon: icon,
                            colorIdentifier: colorIdentifier,
                            isSelected: draftSymbolName == icon.symbolName
                        ) {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                                draftSymbolName = icon.symbolName
                            }
                        }
                    }
                }
                .padding(.trailing, 20)
            }
        }
    }

    private func filteredIcons(in category: String) -> [CourseIcon] {
        CourseIconCatalog.icons.filter { $0.category == category && CourseIconCatalog.matches($0, query: searchText) }
    }

    private func iconSection(_ title: String, icons: [CourseIcon], width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: width > 900 ? 62 : 58), spacing: 10)], spacing: 10) {
                ForEach(icons) { icon in
                    CourseIconCell(
                        icon: icon,
                        colorIdentifier: colorIdentifier,
                        isSelected: draftSymbolName == icon.symbolName
                    ) {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                            draftSymbolName = icon.symbolName
                        }
                    }
                }
            }
        }
    }

    private func displayName(for category: String) -> String {
        switch category {
        case "Business & Economics": "Business"
        case "Law & Politics": "Law"
        case "Arts & Design": "Arts"
        case "General Study": "Study"
        default: category
        }
    }

    private func remember(_ symbolName: String) {
        var symbols = recentSymbols.split(separator: "|").map(String.init)
        symbols.removeAll { $0 == symbolName }
        symbols.insert(symbolName, at: 0)
        recentSymbols = symbols.prefix(12).joined(separator: "|")
    }
}

private struct CourseIconCell: View {
    let icon: CourseIcon
    let colorIdentifier: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CourseColor.color(for: colorIdentifier).opacity(isSelected ? 0.18 : 0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? CourseColor.color(for: colorIdentifier) : StudyDeskTheme.borderSubtle, lineWidth: isSelected ? 2 : 1)
                    }
                Image(systemName: icon.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(CourseColor.color(for: colorIdentifier))
                if isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(CourseColor.color(for: colorIdentifier))
                                .background(.background, in: Circle())
                                .offset(x: 3, y: -3)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: 56, height: 56)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(icon.category), \(icon.title)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}
