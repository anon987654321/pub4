# frozen_string_literal: true

# Laws recovered from the deleted master.json/master.yml design layer and the
# Rails/UI archaeology in pub/__OLD_BACKUPS. Keep the invariant, not the old
# framework or token values.

require "yaml"

Law.define(:README_VISION) do
  source "pub3 master.json documentation.readme_structure.vision — project vision leads README"
  severity :info
  mode :opportunity
  languages %i[markdown]
  path "MASTER/README.md"
  scope :file
  detect do |text|
    prose = text.lines.reject { |line| line.strip.empty? || line.lstrip.start_with?("#") }
    first = prose.take(3).join(" ").strip
    first.empty? || first.scan(/(?:^|[.!?])\s+(?=[A-ZÅØÆ0-9])/).length > 2
  end
  fix "Put a concise 1–3 sentence project vision in the README's first prose paragraph."
  bad <<~X
    # pub4

    Setup details first.
    Run the command below.
    Then read the architecture.
    Finally you will discover what the project is for.
  X
  good <<~X
    # pub4

    MASTER governs the repository as an OpenBSD-like, self-cleaning system. It
    preserves working behavior while continuously reducing unnecessary
    complexity.
  X
end

Law.define(:INTERACTION_SEMANTICS) do
  source "pub3 master.json HTML semantics + WAI-ARIA — navigation is a link, an action is a button"
  severity :warning
  mode :opportunity
  languages %i[html]
  ask "For interactive controls, is the native element honest about the action? Use an anchor for navigation, a button for an in-page action, and a form control for form input. Reject clickable div/span substitutes, href=# used as an action, and ARIA used to repair a native-element choice. Return CLEAN when native interaction semantics are already correct."
  fix "Use the native interactive element that matches the user's action, then add ARIA only for state or additional semantics."
  bad <<~X
    <div class="save" data-action="click->editor#save">Save</div>
    <a href="#" data-action="click->menu#open">Open menu</a>
  X
  good <<~X
    <button type="button" class="save" data-action="click->editor#save">Save</button>
    <%= link_to "Read the article", article_path(@article) %>
  X
end

Law.define(:CONFIGURATION_SHAPE) do
  source "pub2 master.json anti_sectionitis — consolidate related configuration; keep nesting shallow"
  severity :warn
  mode :opportunity
  languages %i[json yaml]
  scope :file
  detect do |text|
    value = YAML.safe_load(text)
    next false unless value.is_a?(Hash)

    max_depth = lambda do |node, depth|
      case node
      when Hash
        [depth, *node.values.map { |child| max_depth.call(child, depth + 1) }].max
      when Array
        [depth, *node.map { |child| max_depth.call(child, depth + 1) }].max
      else
        depth
      end
    end

    max_depth.call(value, 0) > 4 || value.size > 18
  rescue Psych::Exception
    false
  end
  fix "Flatten incidental nesting and consolidate related top-level sections; keep configuration shallow and grouped by purpose."
  bad <<~X
    {
      "a": {
        "b": {
          "c": {
            "d": {
              "e": true
            }
          }
        }
      }
    }
  X
  good <<~X
    {
      "retries": 3,
      "timeout": 30,
      "logging": {
        "level": "info"
      }
    }
  X
end

Law.define(:STYLE_FOLLOWS_STRUCTURE) do
  source "pub3 anti_divitis + anti_sectionitis — structure before decoration"
  severity :info
  mode :opportunity
  languages %i[html css scss]
  ask "Before adding CSS selectors, wrappers, spacing hacks, or decorative rules, is the HTML structure itself semantic, minimal, and ordered for the content? Prefer changing the structural source over painting around a malformed hierarchy. Return CLEAN when semantic structure already carries the hierarchy and styling follows it."
  fix "Fix semantic structure and content hierarchy first; then simplify selectors and tokens to style that structure."
  bad <<~X
    <div class="content-wrapper">
      <div class="content-title">Orders</div>
      <div class="content-copy">No orders yet.</div>
    </div>

    .content-wrapper .content-title { margin-bottom: 13px; }
    .content-wrapper .content-copy { margin-top: 7px; }
  X
  good <<~X
    <section aria-labelledby="orders-title">
      <h2 id="orders-title">Orders</h2>
      <p>No orders yet.</p>
    </section>

    section { padding-block: 16px; }
    h2 { margin-block-end: 8px; }
  X
end
