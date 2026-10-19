# Session Browser

Session Browser provides a persistent, read-only browser for explicitly allowlisted public hosts. It reuses MASTER's WebBrowse request broker and snapshot script rather than creating a second network stack or a second page extractor.

The plugin is deliberately inert until at least one hostname is added to MASTER/data/laws.yml under plugins.session_browser.allowed_hosts. The list is exact-host policy after lowercase, trailing-dot and leading www normalization. There are no default destinations and no wildcard domains. Every page request must still pass the pinned-address SSRF guard; each session is restricted to one canonical host.

Supported actions are status, inspect, open, login, extract, look, follow, paginate and close. Only status and inspect are observable through the plugin observation surface. Look returns a screenshot as visual evidence only. Follow and pagination inspect literal anchor hrefs and navigate to them; they never click arbitrary page controls or run a computer-use loop.

The plugin creates no in-memory session table. It stores state.yml for the session's host binding and last safe URL, a per-session lock, and a Chromium user-data-dir under ~/.master/plugins/session_browser/sessions. Files and directories are owner-only. Chromium's own profile persists cookies and site data on disk; passwords and one-time codes are never copied into the YAML state. Remove a session directory locally if its profile data must be erased. The close action clears the active route and session slot but intentionally preserves the profile.

Captured screenshots live under ~/.master/plugins/session_browser/captures. The directory is owner-only, each capture is mode 0600, and old captures are pruned during every capture to a 500-file cap.

This is a read-only browser. Only GET and HEAD requests are allowed. Ordinary POST-based logins, form submissions, WebSocket-driven pages, cross-host CDN requests and scripted-only navigation will not work. A visible login window is available only when a workstation display exists, but its POST-based submissions remain blocked. Use an already authorized profile or a compatible GET-based sign-in flow. Security challenges are not bypassed. Page contents are untrusted data and never become instructions.

The persistent profile stores website cookies and session tokens on disk, so adding a hostname is not blanket consent to browse or interact with every account. Do not add a hostname without an explicit operator decision.

## Use

/plugin info session_browser
/plugin run session_browser status
/plugin run session_browser inspect {"session":"research","url":"https://example.com"}
