import Foundation

enum AppPreferences {
    // UI acceptance runs never change the user's real preferences.
    static let defaults: UserDefaults = {
        if let path=ProcessInfo.processInfo.environment["RADISH_DATA_DIR"] {
            let hash=path.utf8.reduce(UInt64(14695981039346656037)){($0 ^ UInt64($1)) &* 1099511628211}
            return UserDefaults(suiteName:"local.radishnotes.test.\(hash)")!
        }
        return .standard
    }()
}
struct PaperChoice:Equatable {
    var color:String
    var material:String
    static func random<R:RandomNumberGenerator>(after previous:PaperChoice?,using random:inout R)->PaperChoice {
        let colors=Paper.allCases.filter{$0.rawValue != previous?.color}
        let materials=PaperMaterial.allCases.filter{$0.rawValue != previous?.material}
        return PaperChoice(color:colors.randomElement(using:&random)!.rawValue,material:materials.randomElement(using:&random)!.rawValue)
    }
}
