# frozen_string_literal: true

require "minitest/autorun"

# The 21 infinite-scroll reflexes share one spine: paginate a scope, render one
# partial per row, join. Only the scope differs. That spine now lives in
# Shared::InfiniteScrollReflex and each subclass declares two facts --
# `renders "<partial>", as: :<local>` and a private `scope`.
#
# Written before the unification, not after. There are no reflex tests at all,
# so a 21-file refactor had nothing watching it, and the two things that went
# wrong earlier today -- a deleted class whose subclasses my grep hid, and 164
# locale keys silently dropped -- were both "no check was looking" rather than
# hard problems. This is the check.
#
# Static: nothing here boots Rails. It reads the reflexes as text and asserts the
# declarations are present and point at partials that exist on disk, which is
# exactly what a typo in the refactor would break.
class InfiniteScrollReflexContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def reflexes
    @reflexes ||= Dir.glob(File.join(ROOT, "{amber,brgen,bsdports}", "app", "reflexes", "*infinite_scroll*.rb")).sort
  end

  # Source with comment lines dropped.
  #
  # A source-scanning assertion that reads comments matches the prose explaining
  # a thing as readily as the thing. That trap fired four times across this
  # backlog -- twice on peer sessions' checks, once on an &nbsp; rule that caught
  # the comment saying why the &nbsp; had gone, and once on a pagy-helper rule.
  # The parent already carries `# renders "posts/post", as: :post` as its usage
  # example; the day someone pastes that into a subclass to explain something,
  # test_every_declared_partial_exists_on_disk would go looking for a partial
  # that was never declared.
  def code(path)
    File.readlines(path).reject { |line| line.lstrip.start_with?("#") }.join
  end

  def test_every_reflex_is_found
    # 21 on 2026-08-10. A glob that quietly stops matching reads as a clean run,
    # which is the failure mode this whole file exists to avoid.
    assert_operator reflexes.size, :>=, 21,
                    "expected at least 21 infinite-scroll reflexes, found #{reflexes.size} — check the glob"
  end

  # Every reflex above declares a partial and a scope and passes all four checks
  # while being reachable by nobody. A reflex runs when a view hands its class
  # name to shared/_infinite_scroll_sentinel as `reflex:`; without that mount it
  # is a scope, a partial and a comment that no scroll can ever call.
  #
  # ConversationsInfiniteScrollReflex was in exactly that state and read as a
  # product question in the backlog — the messenger inbox is a rail capped at 30
  # with no sentinel anywhere, so there was no page for it to append to. Deleted.
  def test_every_reflex_is_mounted_by_a_view
    views = Dir.glob(File.join(ROOT, "{amber,brgen,bsdports,shared}", "app", "views", "**", "*.erb")) +
            Dir.glob(File.join(ROOT, "brgen", "engines", "*", "app", "views", "**", "*.erb"))
    mounted = views.flat_map { |v| File.read(v).scan(/reflex:\s*"([^"#]+)/).flatten }.to_set

    # The class name a reflex file defines, derived the way Zeitwerk does.
    declared = reflexes.to_h { |p| [File.basename(p, ".rb").split("_").map(&:capitalize).join, p] }

    unmounted = (declared.keys - mounted.to_a).sort.map { |c| declared[c].delete_prefix("#{ROOT}/") }

    assert_empty unmounted,
                 "no view passes these to shared/_infinite_scroll_sentinel as reflex:, so nothing can call them"
  end

  def test_every_reflex_declares_a_partial_and_a_local
    undeclared = reflexes.reject { |path| code(path).match?(/^\s*renders\s+"[^"]+",\s*as:\s*:\w+/) }

    assert_empty undeclared.map { |p| p.delete_prefix("#{ROOT}/") }.sort,
                 "each reflex must declare `renders \"<partial>\", as: :<local>` so the shared spine can build page_html"
  end

  def test_every_reflex_defines_its_own_scope
    scopeless = reflexes.reject { |path| code(path).match?(/^\s*def scope\b/) }

    assert_empty scopeless.map { |p| p.delete_prefix("#{ROOT}/") }.sort,
                 "the scope is the only thing that differs between these — each must define #scope"
  end

  # The check that would actually catch a botched refactor: a declared partial
  # that does not exist renders nothing and raises only when a user scrolls.
  def test_every_declared_partial_exists_on_disk
    missing = reflexes.flat_map do |path|
      app = path.delete_prefix("#{ROOT}/").split("/").first
      roots = [File.join(ROOT, app, "app", "views"), File.join(ROOT, "shared", "app", "views")] +
              Dir.glob(File.join(ROOT, "brgen", "engines", "*", "app", "views"))

      code(path).scan(/partial:\s*"([^"]+)"|renders\s+"([^"]+)"/).flatten.compact.uniq.filter_map do |partial|
        dir, base = File.split(partial)
        next if roots.any? { |r| Dir.glob(File.join(r, dir, "_#{base}.*")).any? }

        "#{path.delete_prefix("#{ROOT}/")} renders #{partial.inspect}, which resolves to no partial"
      end
    end

    assert_empty missing.sort, "a partial that does not exist fails only when someone scrolls"
  end

  # The spine itself: if these move back into the subclasses the duplication is
  # back, and nothing else would say so.
  def test_the_shared_parent_owns_the_spine
    parent = File.read(File.join(ROOT, "shared", "app", "reflexes", "shared", "infinite_scroll_reflex.rb"))

    # Either spelling — the parent declares it inside `class << self`.
    assert_match(/def (self\.)?renders\(/, parent, "the parent must provide the `renders` declaration")
    assert_match(/def page_html/, parent, "the parent must build page_html from the declaration")
    assert_match(/pagy\(/, parent, "the parent must paginate — that was the line copied into all 21")

    redefiners = reflexes.select { |path| code(path).match?(/^\s*def (load_more|page_html)\b/) }
    assert_empty redefiners.map { |p| p.delete_prefix("#{ROOT}/") }.sort,
                 "these re-implement the shared spine; override after_paginate if a reflex needs extra work"
  end
end
