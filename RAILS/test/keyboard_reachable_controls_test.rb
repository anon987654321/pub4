# frozen_string_literal: true

require "minitest/autorun"

# A control a keyboard cannot reach, and a role that promises one.
#
# This exists because OPENBSD/data/debt.yml's rails_audit_backlog_2026_08_10 says,
# of its own twelve rows, that "the first move on any of these is to name the
# instrument, not to fix a count: an unfalsifiable number is how a register row
# outlives its subject". Its a11y row read "3 div/span elements carrying a click
# action — not focusable, not keyboard-activatable, not announced as a control",
# and no committed tool reproduced it.
#
# Written 2026-08-13. The first two attempts at it were wrong in ways worth
# recording, because both produced a confident number:
#
#   1. `<div[^>]*>` stops at the first ">" — and Stimulus data-action values are
#      full of them ("click->playlist-player#scrub"). The playlist scrubber, the
#      one real finding, was invisible to it.
#   2. Counting every data-action on a div reported five, of which two were
#      `click@window` — a global listener closing a dropdown, not a control. The
#      hand audit had made that exclusion silently.
#
# So the matcher below respects quoted attribute values, and global listeners are
# excluded explicitly rather than by luck.
class KeyboardReachableControlsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  TAG = /<([a-z][a-z0-9]*)((?:\s+[^\s=>]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+))?)*)\s*\/?>/mi

  # ARIA roles whose contract includes keyboard operation.
  WIDGET_ROLES = %w[
    slider button link tab option menuitem switch checkbox radio
    combobox spinbutton textbox searchbox treeitem
  ].freeze

  # Elements the browser makes focusable without help.
  NATIVE = %w[button a input select textarea].freeze

  # Judged, not swept — which is what the register entry asks for.
  #
  # bsdports' dependency tree is a static nested listing with role="tree" and
  # role="treeitem", added deliberately (apps.yml records "WCAG AAA compliance
  # pass — ARIA tree/list roles on port surfaces" as done). Nothing about it is
  # interactive: no expand, no collapse, no selection, and no CSS or JS anywhere
  # in the tree hooks those roles. Full APG tree navigation — roving tabindex,
  # arrow keys, type-ahead — is a large amount of behaviour to add to a thing that
  # displays labels, and dropping the roles for a plain nested list would undo
  # someone's deliberate pass. Left alone, on purpose, and named here so the next
  # reader inherits the reasoning rather than the count.
  ALLOWED_ROLE_WITHOUT_TABINDEX = [
    "bsdports/app/views/ports/_dependency_tree.html.erb"
  ].freeze

  # Pointer-only gestures on a container. A swipe is not made keyboard-operable by
  # focusing its container; it needs a separate control, which these surfaces have
  # (prev/next buttons in the gallery, the dating action row, the playlist
  # transport). Counted so the number cannot grow unnoticed, not asserted at zero.
  GESTURE_SURFACE_CEILING = 8

  def views
    @views ||= Dir.glob(File.join(ROOT, "{brgen,amber,bsdports,shared}/**/app/views/**/*.erb")).uniq
  end

  def each_tag
    views.each do |path|
      File.read(path).scan(TAG) do
        yield Regexp.last_match(1).downcase, Regexp.last_match(2).to_s, path.sub("#{ROOT}/", "")
      end
    end
  end

  def test_the_matcher_survives_a_stimulus_action_value
    tag = %(<div class="x" data-action="click->player#scrub" role="slider" tabindex="0">)
    match = tag.match(TAG)

    assert match, "the tag matcher failed on a data-action containing ->"
    assert_match(/role="slider"/, match[2], "attributes were truncated at the > inside data-action")
  end

  def test_the_glob_finds_views
    assert_operator views.size, :>=, 300, "expected the family's views; found #{views.size}"
  end

  def test_every_widget_role_is_focusable
    offenders = []
    each_tag do |tag, attrs, path|
      role = attrs[/role\s*=\s*"([a-z]+)"/, 1]
      next unless role && WIDGET_ROLES.include?(role)
      next if NATIVE.include?(tag) || attrs =~ /tabindex\s*=/
      next if ALLOWED_ROLE_WITHOUT_TABINDEX.include?(path)

      offenders << "#{path}: <#{tag} role=#{role}> has no tabindex"
    end

    assert_empty offenders, <<~MSG.strip
      #{offenders.size} element(s) announce a keyboard control and cannot be reached by one:

        #{offenders.join("\n  ")}

      A role a screen reader reads as "slider" or "menuitem" is a promise. Give it
      tabindex and the key handling its role implies, or drop the role.
    MSG
  end

  def test_pointer_gesture_surfaces_do_not_multiply
    surfaces = []
    each_tag do |tag, attrs, path|
      next if NATIVE.include?(tag)

      actions = attrs[/data-action\s*=\s*"([^"]*)"/, 1].to_s
      local = actions.split(/\s+/).reject { |a| a.include?("@window") || a.include?("@document") }
      next unless local.any? { |a| a.start_with?("click", "mousedown", "pointerdown") }

      role = attrs[/role\s*=\s*"([a-z]+)"/, 1]
      next if role && WIDGET_ROLES.include?(role)

      surfaces << "#{path}: <#{tag}> #{local.first}"
    end

    assert_operator surfaces.size, :<=, GESTURE_SURFACE_CEILING, <<~MSG.strip
      #{surfaces.size} pointer-driven elements with no widget role, ceiling #{GESTURE_SURFACE_CEILING}:

        #{surfaces.join("\n  ")}

      Each new one needs a keyboard path of its own — a button, not a tabindex on
      the container. Lower the ceiling when one goes.
    MSG
  end
end
