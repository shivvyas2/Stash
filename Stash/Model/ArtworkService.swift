//
//  ArtworkService.swift
//  Stash
//
//  Cover art from SteamGridDB (https://www.steamgriddb.com). Needs a free
//  personal API key, kept in the Keychain.
//

import AppKit
import Foundation
import Security

struct ArtworkGame: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let release_date: Int?

    var year: String? {
        release_date.map { String(Calendar.current.component(.year, from: Date(timeIntervalSince1970: TimeInterval($0)))) }
    }
}

struct Artwork: Decodable, Identifiable, Hashable {
    let id: Int
    let url: URL
    let thumb: URL
    let width: Int
    let height: Int
}

enum ArtworkService {
    private static let base = URL(string: "https://www.steamgriddb.com/api/v2")!
    static let keyPage = URL(string: "https://www.steamgriddb.com/profile/preferences/api")!

    // MARK: API key (Keychain)

    private static let keychainService = "app.stash.Stash.steamgriddb"

    static var apiKey: String? {
        get {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                        kSecAttrService as String: keychainService,
                                        kSecReturnData as String: true]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                        kSecAttrService as String: keychainService]
            SecItemDelete(query as CFDictionary)
            guard let newValue, !newValue.isEmpty else { return }
            var add = query
            add[kSecValueData as String] = Data(newValue.utf8)
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static var isConfigured: Bool { apiKey != nil }

    // MARK: Requests

    private struct Response<T: Decodable>: Decodable {
        let success: Bool
        let data: T?
        let errors: [String]?
    }

    private static func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], key: String? = nil) async throws -> T {
        guard let key = key ?? apiKey else { throw StashError("Add your SteamGridDB API key in Settings to fetch artwork.") }
        var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw StashError("SteamGridDB didn't accept the API key. Check it in Settings.") }
        let decoded = try JSONDecoder().decode(Response<T>.self, from: data)
        guard decoded.success, let value = decoded.data else {
            throw StashError(decoded.errors?.joined(separator: ", ") ?? "SteamGridDB request failed (HTTP \(status)).")
        }
        return value
    }

    /// Checks a key before saving it
    static func validate(key: String) async -> Bool {
        let result: [ArtworkGame]? = try? await get("search/autocomplete/zelda", key: key)
        return result != nil
    }

    static func search(_ term: String) async throws -> [ArtworkGame] {
        let cleaned = term.replacingOccurrences(of: "/", with: " ").trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return [] }
        return try await get("search/autocomplete/\(cleaned)")
    }

    /// Portrait covers (600×900 and similar), static images only
    static func covers(for gameID: Int) async throws -> [Artwork] {
        try await get("grids/game/\(gameID)", query: [
            URLQueryItem(name: "dimensions", value: "600x900,342x482,660x930"),
            URLQueryItem(name: "types", value: "static"),
            URLQueryItem(name: "nsfw", value: "false"),
            URLQueryItem(name: "humor", value: "false")
        ])
    }

    static func image(at url: URL) async throws -> NSImage {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = NSImage(data: data) else { throw StashError("The artwork couldn't be read.") }
        return image
    }

    /// Best-guess cover for a game name: top search hit, top-rated cover
    static func bestCover(for name: String) async throws -> NSImage? {
        guard let match = try await search(name).first,
              let cover = try await covers(for: match.id).first else { return nil }
        return try await image(at: cover.url)
    }
}
