import Foundation

@main
struct RecentsTest {
    @MainActor
    static func main() async {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-recents-\(UUID().uuidString).json")
        var failures = 0
        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() { print("PASS  \(description)") } else { print("FAIL  \(description)"); failures += 1 }
        }

        let store = LauncherRecentsStore(fileURL: fileURL)
        check("starts empty", store.isEmpty)
        store.record(itemKey: "a")
        store.record(itemKey: "b")
        store.record(itemKey: "a")
        check("newest first, never repeated", store.keys == ["a", "b"])
        check("a blank key is ignored", { store.record(itemKey: ""); return store.keys == ["a", "b"] }())
        let revision = store.revision
        store.remove(itemKey: "zzz")
        check("removing an absent key changes nothing", store.revision == revision)
        store.remove(itemKey: "b")
        check("removal drops the key", store.keys == ["a"] && store.revision == revision + 1)

        for index in 0..<40 { store.record(itemKey: "k\(index)") }
        check("capped at thirty", store.keys.count == 30 && store.keys.first == "k39" && !store.keys.contains("a"))

        await store.flush()
        let reloaded = LauncherRecentsStore(fileURL: fileURL)
        check("persists across a relaunch", reloaded.keys == store.keys)

        store.clear()
        await store.flush()
        check("clear empties the list", store.isEmpty && LauncherRecentsStore(fileURL: fileURL).isEmpty)

        try? FileManager.default.removeItem(at: fileURL)
        if failures > 0 { print("\(failures) checks failed"); exit(1) }
        print("all checks passed")
    }
}
