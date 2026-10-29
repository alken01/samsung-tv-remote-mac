import Foundation

// Personal build: credentials remain in a private Application Support directory.
// Nothing is synced or included in the application bundle.
struct RemoteStorage {
    let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SamsungMenuRemote", isDirectory: true)
    }
    private func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
    func loadTV() -> Television? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("television.json")) else { return nil }
        return try? JSONDecoder().decode(Television.self, from: data)
    }
    func saveTV(_ tv: Television) throws { try write(JSONEncoder().encode(tv), name: "television.json") }
    func token(for tv: Television) -> String? { tokens()[tv.id] }
    func saveToken(_ token: String, for tv: Television) throws {
        var values = tokens(); values[tv.id] = token
        try write(JSONEncoder().encode(values), name: "credentials.json")
    }
    func forget(_ tv: Television) throws {
        var values = tokens(); values[tv.id] = nil
        try write(JSONEncoder().encode(values), name: "credentials.json")
        let url = directory.appendingPathComponent("television.json")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    private func tokens() -> [String: String] {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("credentials.json")) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }
    private func write(_ data: Data, name: String) throws {
        try prepare()
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
