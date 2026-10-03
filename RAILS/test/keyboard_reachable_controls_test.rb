# frozen_string_literal: true

require "minitest/autorun"

# A control a keyboard cannot reach, and a role that promises one.
#
# This exists because a hand-counted audit row read "3 div/span elements
# carrying a click action — not focusable, not keyboard-activatable, not
# announced as a control", and no committed tool reproduced it. The first move
# on a row like that is to name the instrument rather than fix the count: an
# unfalsifiable number is how a register row outlives its subject.
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
#
# The pointer-gesture surfaces this file counts have a second contract, and it
# lives here because the census does: a drag the browser can also claim as a
# scroll or a back-swipe needs a touch-action that settles which of the two owns
# it. Without one, a slightly diagonal swipe scrolls the page and the browser
# sends pointercancel halfway through the gesture.
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
  #
  # 10, not the 8 this read before each_tag blanked ERB: the mobile sheet and the
  # search palette backdrop were always there, behind attributes whose ERB nests
  # quotes. The tree did not grow; the matcher learned to read it.
  GESTURE_SURFACE_CEILING = 10

  # A drag is a start event and a move event bound on one element. A move with
  # no start is a hover effect — parallax-tilt on the affiliate unit — and the
  # browser taking the pan there is the right outcome.
  MOVE_EVENTS = %w[pointermove touchmove mousemove].freeze
  START_EVENTS = %w[pointerdown touchstart mousedown].freeze
  MOVE_LISTENER = /(\w+(?:\.\w+)*)\.addEventListener\(\s*["'](?:pointermove|touchmove|mousemove)["']/
  START_LISTENER = /this\.element\.addEventListener\(\s*["'](?:pointerdown|touchstart|mousedown)["']/

  # Values that leave the browser both pans, so they settle nothing between a
  # scroll and a drag. manipulation is pan-x pan-y pinch-zoom: it drops the
  # double-tap delay and keeps every pan, which is why .app-shell declaring it
  # covers none of the surfaces inside the shell.
  PANNING_TOUCH_ACTION = %w[auto manipulation inherit initial unset revert].freeze

  VOID_TAGS = %w[area base br col embed hr img input link meta source track wbr].freeze
  MARKUP = Regexp.new("</[a-z][a-z0-9]*\\s*>|#{TAG.source}", Regexp::IGNORECASE | Regexp::MULTILINE)

  # Surfaces that drag without a touch-action, each with the reason it is still
  # so. The value is CSS on a surface whose feel in the hand is the operator's,
  # so a row here is a finding waiting on a decision, not a pass. Delete the row
  # when the surface declares one; test_gesture_debt_names_live_surfaces fails
  # until you do.
  GESTURES_WITHOUT_TOUCH_ACTION = {
    "brgen/app/views/layouts/application.html.erb pull-to-refresh" =>
      "The pull is vertical on the page's own scroller, and every value that keeps " \
      "the page scrolling also leaves the browser the vertical pan. The controller " \
      "owns the conflict instead, cancelling a downward touchmove at scroll top from " \
      "a non-passive listener.",
    "brgen/app/views/shared/_mobile_chrome.html.erb bottom-sheet" =>
      ".mobile-sheet is dragged vertically and declares nothing, so a touch drag can " \
      "become a page scroll and pointercancel snaps the sheet back through pointerUp. " \
      "none on the sheet, or on its handle alone so the link list still scrolls, is " \
      "a choice about how the sheet feels.",
    "brgen/engines/dating/app/views/dating/home/index.html.erb swipe" =>
      "Cards swipe horizontally and neither .dating-discover, #swipe-stack nor " \
      ".swipe-card declares touch-action, so a diagonal drag can scroll the page " \
      "and cancel the swipe. pan-y is the usual value.",
    "brgen/engines/playlist/app/views/playlist/sets/show.html.erb swipe" =>
      "Each .track-row swipes horizontally inside a vertically scrolling list, and " \
      "without pan-y a swipe that starts off-axis scrolls the page instead.",
  }.freeze

  Surface = Struct.new(:path, :tag, :attrs, :controller, :match)

  def views
    @views ||= Dir.glob(File.join(ROOT, "{brgen,amber,bsdports,shared}/**/app/views/**/*.erb")).uniq
  end

  # ERB is blanked to spaces first, offsets kept. An attribute like
  # aria-label="<%= t("nav.main") %>" nests quotes, and TAG, reading the first
  # inner quote as the value's end, skipped the whole tag: brgen's <main>, the
  # mobile sheet and the search palette backdrop were invisible to every census
  # in this file.
  def each_tag
    views.each do |path|
      File.read(path).gsub(/<%.*?%>/m) { |erb| " " * erb.length }.scan(TAG) do
        match = Regexp.last_match
        yield match[1].downcase, match[2].to_s, path.sub("#{ROOT}/", ""), match
      end
    end
  end

  # Stimulus actions bound to the element itself; a @window or @document
  # listener closes a dropdown or reads a key, and is not a control here.
  def local_actions(attrs)
    attrs[/data-action\s*=\s*"([^"]*)"/, 1].to_s.split.reject { |a| a.include?("@window") || a.include?("@document") }
  end

  def event_of(action) = action[/\A[a-z]+/]

  def action_surfaces
    found = []
    each_tag do |tag, attrs, path, match|
      actions = local_actions(attrs)
      events = actions.map { |a| event_of(a) }
      next unless events.intersect?(MOVE_EVENTS) && events.intersect?(START_EVENTS)

      move = actions.find { |a| MOVE_EVENTS.include?(event_of(a)) }
      found << Surface.new(path, tag, attrs, move[/->([\w-]+)#/, 1], match)
    end
    found
  end

  def controller_sources
    Dir.glob(File.join(ROOT, "{brgen,amber,bsdports,shared}/**/*_controller.js"))
       .reject { |p| p.match?(%r{/(vendor|node_modules|public|builds)/}) }
       .to_h { |p| [File.basename(p, "_controller.js").tr("_", "-"), File.read(p)] }
  end

  # Controllers that drag their own element from addEventListener, with no
  # data-action in the markup to find them by.
  def listener_controllers
    controller_sources.select do |_, source|
      source.scan(MOVE_LISTENER).flatten.include?("this.element") && source.match?(START_LISTENER)
    end.keys
  end

  def listener_surfaces
    names = listener_controllers
    found = []
    each_tag do |tag, attrs, path, match|
      mounted = attrs[/data-controller\s*=\s*"([^"]*)"/, 1].to_s.split & names
      mounted.each { |name| found << Surface.new(path, tag, attrs, name, match) }
    end
    found
  end

  def gesture_surfaces = @gesture_surfaces ||= action_surfaces + listener_surfaces

  def surface_id(surface) = "#{surface.path} #{surface.controller}"

  def undeclared_gestures
    gesture_surfaces.reject { |surface| touch_action_declared?(surface) }.map { |s| surface_id(s) }.uniq
  end

  # The surface's own class or id, or its only child's: a carousel whose one
  # child is the scroller is covered by the scroller, since touch-action is
  # read from where the touch lands up through its ancestors. A child among
  # several covers only the part of the surface it occupies.
  def touch_action_declared?(surface)
    tokens = element_tokens(surface.attrs)
    children = direct_children(surface.match.string, surface.match.end(0))
    tokens |= element_tokens(children.first) if children.size == 1
    tokens.intersect?(restricting_tokens)
  end

  # Anchored against a hyphen as well as a word character, because \bid also
  # matches the tail of data-track-id.
  def element_tokens(attrs)
    classes = attrs[/(?<![\w-])class\s*=\s*"([^"]*)"/, 1].to_s.gsub(/<%.*?%>/, " ").split.map { |name| ".#{name}" }
    ids = attrs[/(?<![\w-])id\s*=\s*"([^"]*)"/, 1].to_s.gsub(/<%.*?%>/, " ").split.map { |name| "##{name}" }
    classes + ids
  end

  # Attributes of each element one level inside the tag that ends at `from`.
  def direct_children(body, from)
    depth = 0
    children = []
    body[from..].gsub(/<%#.*?%>/m, "").scan(MARKUP) do
      markup = Regexp.last_match
      if markup[0].start_with?("</")
        break if depth.zero?

        depth -= 1
        next
      end
      children << markup[2].to_s if depth.zero?
      depth += 1 unless VOID_TAGS.include?(markup[1].downcase) || markup[0].end_with?("/>")
    end
    children
  end

  def restricting_tokens
    @restricting_tokens ||= Dir.glob(File.join(ROOT, "{brgen,amber,bsdports,shared}/**/app/assets/stylesheets/**/*.scss"))
                               .flat_map { |path| touch_action_selectors(File.read(path)) }
                               .flat_map { |selector| selector.split(/[\s>+~]+/).last.to_s.scan(/[.#][\w-]+/) }
                               .uniq
  end

  # Every selector, nesting resolved, whose block declares a touch-action that
  # takes a pan away from the browser.
  def touch_action_selectors(scss)
    stack = []
    found = []
    uncommented(scss).scan(/([^{};]*)([{};])/) do |text, mark|
      value = text[/(?:\A|\s)touch-action\s*:\s*([^;}]+)/, 1]&.strip
      found.concat(resolve_nesting(stack)) if value && restricts_pan?(value)
      stack.push(text.strip) if mark == "{"
      stack.pop if mark == "}"
    end
    found
  end

  def restricts_pan?(value) = !PANNING_TOUCH_ACTION.include?(value) && !(value.include?("pan-x") && value.include?("pan-y"))

  # Interpolation is blanked before braces are counted: `.swipe-card--stack-#{$i}`
  # carries a brace pair that opens no block.
  def uncommented(scss)
    scss.gsub(%r{/\*.*?\*/}m, "").gsub(%r{(?<![:"'])//[^\n]*}, "").gsub(/#\{[^}]*\}/, "i")
  end

  def resolve_nesting(stack)
    stack.reject { |level| level.start_with?("@") }.reduce([""]) do |parents, level|
      parents.product(level.split(",")).map do |parent, part|
        part.include?("&") ? part.strip.gsub("&", parent) : "#{parent} #{part.strip}".strip
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

      local = local_actions(attrs)
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

  def test_the_touch_action_reader_resolves_nesting_and_skips_panning_values
    scss = <<~SCSS
      /* touch-action: none; in a comment declares nothing */
      .deck { .card-#{"\#{$i}"} { color: red; } &.live { touch-action: pan-y; } }
      .shell { touch-action: manipulation; }
      .rail, .strip { > .row { touch-action: pan-x pan-y; } }
      .sheet { touch-action: none }
    SCSS

    assert_equal [".deck.live", ".sheet"], touch_action_selectors(scss)
  end

  def test_a_sole_child_is_read_and_a_child_among_several_is_not
    body = %(<section data-action="x"><div class="scroller"><a href="/">a</a><img src="x"></div></section><p class="after">)
    assert_equal [%( class="scroller")], direct_children(body, body.index(">") + 1)

    body = %(<main><%# <h1> in a comment %><nav class="tabs"></nav><div></div></main>)
    assert_equal [%( class="tabs"), ""], direct_children(body, body.index(">") + 1)
  end

  # Every view that binds a move event in a data-action, found by plain text,
  # has to be one the tag matcher read. A helper hash — data: { action: … } — is
  # the shape it cannot see, and that file would pass here by being invisible.
  def test_the_gesture_census_sees_every_bound_move
    bound = []
    each_tag { |_, attrs, path| bound << path if local_actions(attrs).any? { |a| MOVE_EVENTS.include?(event_of(a)) } }
    texts = views.select { |path| File.read(path).match?(/(?:pointer|touch|mouse)move->/) }.map { |p| p.sub("#{ROOT}/", "") }

    assert_empty texts - bound, "these views bind a move the tag matcher did not read"
    # Five known drags: the media gallery, the bottom sheet, the dating deck,
    # playlist track rows and pull-to-refresh. Fewer means the matcher went blind.
    assert_operator gesture_surfaces.size, :>=, 5, "the census found #{gesture_surfaces.map { |s| surface_id(s) }}"
  end

  # A move listener on a target or a child is a surface this census cannot place,
  # and a listener controller mounted from a helper hash is one it cannot find.
  def test_every_move_listener_is_placed_and_mounted
    unplaced = controller_sources.flat_map do |name, source|
      (source.scan(MOVE_LISTENER).flatten - %w[this.element window document]).map { |target| "#{name}: #{target}" }
    end
    unmounted = listener_controllers - listener_surfaces.map(&:controller)

    assert_empty unplaced, "move listeners on something other than the controller's element"
    assert_empty unmounted, "listener controllers no view mounts through a literal data-controller"
  end

  def test_every_gesture_surface_declares_touch_action
    unexplained = undeclared_gestures - GESTURES_WITHOUT_TOUCH_ACTION.keys

    assert_empty unexplained, <<~MSG.strip
      #{unexplained.size} drag surface(s) declare no touch-action that takes a pan from the browser:

        #{unexplained.join("\n  ")}

      A drag the page can also scroll is decided by whichever of the two moves
      first. Declare pan-y for a horizontal swipe, pan-x for a vertical one, or
      none, on the element or its only child. auto and manipulation leave both pans.
    MSG
  end

  def test_gesture_debt_names_live_surfaces
    stale = GESTURES_WITHOUT_TOUCH_ACTION.keys - undeclared_gestures

    assert_empty stale, "these rows excuse a surface that is gone or now declares touch-action — delete them"
  end
end
