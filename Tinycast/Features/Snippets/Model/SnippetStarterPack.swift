import Foundation

/// Starter AI prompts, written into the library only when the user asks for them.
enum SnippetStarterPack {
    static let group = "AI prompts"

    private static let claude = "com.anthropic.claudefordesktop"
    private static let cursor = "com.todesktop.230313mzl4w4u92"

    static let prompts: [Snippet] = [
        prompt(
            "Explain This Code", apps: [claude, cursor],
            """
            Explain what this code does, step by step. Call out anything surprising or risky.

            ```
            {clipboard}
            ```
            """),
        prompt(
            "Review This Diff", apps: [claude, cursor],
            """
            Review this diff like a senior engineer. List real bugs first, then missing tests, \
            then style nits. Skip the praise.

            ```diff
            {clipboard}
            ```
            """),
        prompt(
            "Write Tests", apps: [claude, cursor],
            """
            Write tests for the code below, using the project's existing test setup. Cover edge \
            cases and failure paths, not just the happy path.

            ```
            {clipboard}
            ```
            """),
        prompt(
            "Debug This Error", apps: [claude, cursor],
            """
            I'm getting this error:

            ```
            {clipboard}
            ```

            What's the most likely cause, and how do I confirm it? Give me the smallest fix first.
            """),
        prompt(
            "Plan Before Coding", apps: [claude, cursor],
            """
            Before writing any code, read the relevant files and give me a short plan: which files \
            change, what could break, and how you'll test it. Wait for my go-ahead.

            Task: {argument name="Task"}
            """),
        prompt(
            "Summarize",
            """
            Summarize this in {argument name="Length" options="3 bullets, one paragraph, one sentence"}. \
            Keep names, numbers and decisions.

            {clipboard}
            """),
        prompt(
            "Rewrite Shorter",
            """
            Rewrite this to be shorter and plainer. Keep the meaning and my tone.

            {clipboard}
            """),
        prompt(
            "Turn Into a Ticket",
            """
            Turn these notes into a ticket: a title, a short problem statement, acceptance criteria \
            as a checklist, and open questions.

            {clipboard}
            """)
    ]

    /// Names are how the user tells prompts apart, so an existing one is never added twice.
    static func missing(from existing: [Snippet]) -> [Snippet] {
        let taken = Set(existing.map { $0.name.lowercased() })
        return prompts.filter { !taken.contains($0.name.lowercased()) }
    }

    private static func prompt(_ name: String, apps: [String] = [], _ text: String) -> Snippet {
        Snippet(name: name, text: text, apps: apps, group: group)
    }
}
