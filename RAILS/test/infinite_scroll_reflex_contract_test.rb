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

  def test_every_reflex_is_found
    # 21 on 2026-08-10. A glob that quietly stops matching reads as a clean run,
    # which is the failure mode this whole file exists to avoid.
    assert_operator reflexes.size, :>=, 21,
                    "expected at least 21 infinite-scroll reflexes, found #{reflexes.size} — check the glob"
  end

  def test_every_reflex_declares_a_partial_and_a_local
    undeclared = reflexes.reject { |path| File.read(path).match?(/^\s*renders\s+"[^"]+",\s*as:\s*:\w+/) }

    assert_empty undeclared.map { |p| p.delete_prefix("#{ROOT}/") }.sort,
                 "each reflex must declare `renders \"<partial>\", as: :<local>` so the shared spine can build page_html"
  end

  def test_every_reflex_defines_its_own_scope
    scopeless = reflexes.reject { |path| File.read(path).match?(/^\s*def scope\b/) }

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

      File.read(path).scan(/partial:\s*"([^"]+)"|renders\s+"([^"]+)"/).flatten.compact.uniq.filter_map do |partial|
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

    redefiners = reflexes.select { |path| File.read(path).match?(/^\s*def (load_more|page_html)\b/) }
    assert_empty redefiners.map { |p| p.delete_prefix("#{ROOT}/") }.sort,
                 "these re-implement the shared spine; override after_paginate if a reflex needs extra work"
  end
end
