import Foundation

/// The icons a folder can wear, under the same names and categories as the web frontend's picker
/// (`tpstore/frontend/src/folderIcons.js`, Lucide names). The backend stores only the name, so an
/// icon picked on the web shows up here and the other way round; each name maps to the closest
/// SF Symbol.
enum FolderIconCatalog {
    struct Category: Identifiable {
        let label: String
        let icons: [String]
        var id: String { label }
    }

    static let categories: [Category] = [
        Category(label: "General", icons: ["Box", "Package", "Archive", "Inbox", "Layers", "BookOpen", "Book", "Globe", "Map", "Compass"]),
        Category(label: "Education", icons: ["GraduationCap", "School", "Library", "BookCopy", "Notebook", "NotebookPen", "Pencil", "Ruler", "Calculator", "Microscope", "Atom", "Brain", "Sigma", "Pi", "FlaskConical", "PenLine"]),
        Category(label: "Calendar & Time", icons: ["Calendar", "CalendarDays", "CalendarCheck", "CalendarClock", "CalendarRange", "Clock", "Timer", "AlarmClock"]),
        Category(label: "Media", icons: ["Camera", "Image", "Film", "Music", "Headphones", "Mic", "Radio", "Tv", "Monitor", "Video", "Speaker", "Gamepad2"]),
        Category(label: "Documents", icons: ["File", "FileText", "FileCode", "Newspaper", "BookMarked", "Bookmark", "ClipboardList", "ScrollText"]),
        Category(label: "Tech", icons: ["Code", "Code2", "Terminal", "Server", "Database", "Cpu", "HardDrive", "Laptop", "Wifi", "Cloud", "Braces", "Bug"]),
        Category(label: "Work", icons: ["Briefcase", "Building", "Building2", "LayoutDashboard", "BarChart", "PieChart", "TrendingUp", "Kanban"]),
        Category(label: "Personal", icons: ["Home", "Heart", "Star", "User", "Users", "Smile", "Baby", "Glasses", "Dumbbell", "Trophy", "Award"]),
        Category(label: "Nature & Travel", icons: ["Sun", "Moon", "Leaf", "Mountain", "Plane", "Car", "Train", "Ship", "Bike", "Flower", "Zap", "Umbrella", "Anchor", "Flame", "Snowflake"]),
        Category(label: "Misc", icons: ["Shield", "Lock", "Key", "Settings", "Wrench", "Gift", "Palette", "Lightbulb", "Coffee", "ShoppingCart", "TestTube"]),
    ]

    /// The SF Symbol drawn on the folder for a stored icon name, or nil for a name this app
    /// doesn't know (the folder then falls back to its default look).
    static func symbol(for iconName: String) -> String? {
        symbols[iconName]
    }

    /// "GraduationCap" → "Graduation Cap", the way the web picker labels its icons.
    static func label(for iconName: String) -> String {
        var label = ""
        var previous: Character?
        for character in iconName {
            if let previous, previous.isLowercase, character.isUppercase || character.isNumber {
                label.append(" ")
            }
            label.append(character)
            previous = character
        }
        return label
    }

    private static let symbols: [String: String] = [
        // General
        "Box": "shippingbox", "Package": "cube.box", "Archive": "archivebox", "Inbox": "tray",
        "Layers": "square.3.layers.3d", "BookOpen": "book", "Book": "book.closed", "Globe": "globe",
        "Map": "map", "Compass": "safari",
        // Education
        "GraduationCap": "graduationcap", "School": "building.columns", "Library": "books.vertical",
        "BookCopy": "book.pages", "Notebook": "text.book.closed", "NotebookPen": "square.and.pencil",
        "Pencil": "pencil", "Ruler": "ruler", "Calculator": "plus.forwardslash.minus",
        "Microscope": "microbe", "Atom": "atom", "Brain": "brain", "Sigma": "sum", "Pi": "function",
        "FlaskConical": "flask", "PenLine": "pencil.line",
        // Calendar & Time
        "Calendar": "calendar", "CalendarDays": "calendar.circle", "CalendarCheck": "calendar.badge.checkmark",
        "CalendarClock": "calendar.badge.clock", "CalendarRange": "calendar.day.timeline.left",
        "Clock": "clock", "Timer": "timer", "AlarmClock": "alarm",
        // Media
        "Camera": "camera", "Image": "photo", "Film": "film", "Music": "music.note",
        "Headphones": "headphones", "Mic": "mic", "Radio": "radio", "Tv": "tv", "Monitor": "display",
        "Video": "video", "Speaker": "hifispeaker", "Gamepad2": "gamecontroller",
        // Documents
        "File": "doc", "FileText": "doc.text", "FileCode": "doc.badge.gearshape", "Newspaper": "newspaper",
        "BookMarked": "book.closed.fill", "Bookmark": "bookmark", "ClipboardList": "list.clipboard",
        "ScrollText": "scroll",
        // Tech
        "Code": "chevron.left.forwardslash.chevron.right", "Code2": "curlybraces", "Terminal": "terminal",
        "Server": "server.rack", "Database": "cylinder.split.1x2", "Cpu": "cpu", "HardDrive": "internaldrive",
        "Laptop": "laptopcomputer", "Wifi": "wifi", "Cloud": "cloud", "Braces": "curlybraces.square",
        "Bug": "ant",
        // Work
        "Briefcase": "briefcase", "Building": "building", "Building2": "building.2",
        "LayoutDashboard": "square.grid.2x2", "BarChart": "chart.bar", "PieChart": "chart.pie",
        "TrendingUp": "chart.line.uptrend.xyaxis", "Kanban": "rectangle.split.3x1",
        // Personal
        "Home": "house", "Heart": "heart", "Star": "star", "User": "person", "Users": "person.2",
        "Smile": "face.smiling", "Baby": "figure.and.child.holdinghands", "Glasses": "eyeglasses",
        "Dumbbell": "dumbbell", "Trophy": "trophy", "Award": "rosette",
        // Nature & Travel
        "Sun": "sun.max", "Moon": "moon", "Leaf": "leaf", "Mountain": "mountain.2", "Plane": "airplane",
        "Car": "car", "Train": "tram", "Ship": "ferry", "Bike": "bicycle", "Flower": "camera.macro",
        "Zap": "bolt", "Umbrella": "umbrella", "Anchor": "sailboat", "Flame": "flame", "Snowflake": "snowflake",
        // Misc
        "Shield": "shield", "Lock": "lock", "Key": "key", "Settings": "gearshape", "Wrench": "wrench.adjustable",
        "Gift": "gift", "Palette": "paintpalette", "Lightbulb": "lightbulb", "Coffee": "cup.and.saucer",
        "ShoppingCart": "cart", "TestTube": "testtube.2",
    ]
}
