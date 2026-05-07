import SwiftUI

struct WordPressSiteSearchPicker: View {
    let sites: [WPCOMSite]
    @Binding var selectedSiteID: Int?
    var maxVisibleRows = 6

    @State private var searchText = ""

    private let rowLimit = 80
    private let rowHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField

            if visibleSites.isEmpty {
                Text("No matching workspaces")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(visibleSites) { site in
                            Button {
                                selectedSiteID = site.id
                                searchText = site.primarySearchText
                            } label: {
                                siteRow(site)
                            }
                            .buttonStyle(.plain)
                        }

                        if hiddenMatchCount > 0 {
                            Text("\(hiddenMatchCount) more matches")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                    }
                }
                .frame(maxHeight: listHeight)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search workspaces", text: $searchText)
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private var visibleSites: [WPCOMSite] {
        Array(matchingSites.prefix(rowLimit))
    }

    private var hiddenMatchCount: Int {
        max(0, matchingSites.count - rowLimit)
    }

    private var listHeight: CGFloat {
        let visibleRows = min(maxVisibleRows, max(1, visibleSites.count))
        return CGFloat(visibleRows) * rowHeight
    }

    private var selectedSite: WPCOMSite? {
        guard let selectedSiteID else { return nil }
        return sites.first { $0.id == selectedSiteID }
    }

    private var matchingSites: [WPCOMSite] {
        let tokens = normalizedTokens(searchText)
        guard !tokens.isEmpty else {
            if let selectedSite {
                return [selectedSite] + sites.filter { $0.id != selectedSite.id }
            }
            return sites
        }

        return sites
            .compactMap { site -> (site: WPCOMSite, score: Int)? in
                guard let score = score(site, tokens: tokens) else { return nil }
                return (site, score)
            }
            .sorted {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }
                return $0.site.displayName.localizedCaseInsensitiveCompare($1.site.displayName) == .orderedAscending
            }
            .map(\.site)
    }

    private func siteRow(_ site: WPCOMSite) -> some View {
        let isSelected = site.id == selectedSiteID
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(site.displayName)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(site.secondaryDisplayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        )
    }

    private func score(_ site: WPCOMSite, tokens: [String]) -> Int? {
        let fields = site.searchFields
        guard tokens.allSatisfy({ token in fields.contains { $0.contains(token) } }) else {
            return nil
        }

        var score = site.id == selectedSiteID ? 1_000 : 0
        for token in tokens {
            if "\(site.id)".hasPrefix(token) {
                score += 120
            }
            if normalized(site.slug ?? "").hasPrefix(token) {
                score += 90
            }
            if normalized(site.displayName).hasPrefix(token) {
                score += 80
            }
            if normalized(site.domainDisplayText).hasPrefix(token) {
                score += 70
            }
            if fields.contains(where: { $0.contains(token) }) {
                score += 10
            }
        }
        return score
    }

    private func normalizedTokens(_ value: String) -> [String] {
        normalized(value)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}

private extension WPCOMSite {
    var primarySearchText: String {
        if let slug, !slug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return slug
        }
        return displayName
    }

    var domainDisplayText: String {
        slug ?? url?.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "\(id)"
    }

    var secondaryDisplayText: String {
        "\(domainDisplayText) · \(id)"
    }

    var searchFields: [String] {
        [displayName, slug, url, "\(id)"]
            .compactMap { $0 }
            .map {
                $0
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    .lowercased()
            }
    }
}
