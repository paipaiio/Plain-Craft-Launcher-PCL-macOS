import Foundation

struct JavaVersionSelector: Sendable {
    func select(
        from installations: [JavaInstallation],
        requiredMajorVersion: Int?,
        fallback: JavaInstallation?
    ) -> JavaInstallation? {
        guard let requiredMajorVersion else {
            return fallback ?? installations.first
        }

        let candidates = installations.compactMap { installation -> (JavaInstallation, Int)? in
            guard let major = Self.majorVersion(from: installation.versionSummary) else { return nil }
            return (installation, major)
        }
        guard !candidates.isEmpty else {
            return fallback ?? installations.first
        }

        if let compatible = candidates
            .filter({ $0.1 >= requiredMajorVersion })
            .min(by: { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.versionSummary.localizedStandardCompare(rhs.0.versionSummary) == .orderedAscending
                }
                return lhs.1 < rhs.1
            }) {
            return compatible.0
        }

        return candidates.max { lhs, rhs in
            if lhs.1 == rhs.1 {
                return lhs.0.versionSummary.localizedStandardCompare(rhs.0.versionSummary) == .orderedAscending
            }
            return lhs.1 < rhs.1
        }?.0 ?? fallback ?? installations.first
    }

    static func majorVersion(from summary: String) -> Int? {
        let pattern = #"(?:version\s*)?([0-9]+)(?:\.([0-9]+))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(summary.startIndex..<summary.endIndex, in: summary)
        guard let match = regex.firstMatch(in: summary, range: range),
              let firstRange = Range(match.range(at: 1), in: summary),
              let first = Int(summary[firstRange]) else {
            return nil
        }
        if first == 1,
           match.numberOfRanges > 2,
           let secondRange = Range(match.range(at: 2), in: summary),
           let legacyMajor = Int(summary[secondRange]) {
            return legacyMajor
        }
        return first
    }
}
