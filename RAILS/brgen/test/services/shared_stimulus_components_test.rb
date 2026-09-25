# frozen_string_literal: true

require "minitest/autorun"
require "set"
require_relative "../source_reader"

# The shared Stimulus components, as a wiring contract: what stimulus_boot.js
# registers and keeps out, the views that use the components, and the snippet
# library held to the registry.
#
# Reads source as text: this asserts the wiring exists, not that it works.
class SharedStimulusComponentsTest < Minitest::Test
  include SourceReader

  # stimulus_boot.js holds what every app registers; stimulus_boot_social.js,
  # _brgen.js and _amber.js hold what only some apps mount, split out so an
  # app that doesn't use a controller never imports its module. Together
  # they are the registry these tests hold the snippet library and views to.
  BOOT_FILES = %w[stimulus_boot.js stimulus_boot_social.js stimulus_boot_brgen.js stimulus_boot_amber.js].freeze

  def registry_source
    BOOT_FILES.map { |f| read_source(File.join(ROOT, "shared/frontend", f)) }.join("\n")
  end

  def test_shared_stimulus_components_are_registered
    source = registry_source
    %w[
      Clipboard
      Dropdown
      Hotkey
      Notification
      Reveal
      Sortable
      toast
      TextareaAutogrow
      PasswordVisibility
      RailsNestedForm
      CharacterCounter
      CheckboxSelectAll
      ReadMore
    ].each do |component|
      assert_includes source, component
    end

    # timeago read data-timeago-datetime-value, which no view ever set, so its
    # only possible effect was to replace localised Norwegian with date-fns
    # English. carousel's one element left amber's wardrobe showcase, which is a
    # CSS marquee, and it pulled swiper from cdn.jsdelivr.net. Matched on the
    # registration form, not the bare word, so prose naming either passes.
    %w[timeago carousel].each do |name|
      refute_match(/\["#{name}",/, source, "#{name} has no consumer in any app")
    end

    # Dialog, ScrollTo, Sound and SpeechRecognition were imported, registered,
    # pinned and vendored with no data-controller for them in any of the four
    # apps. Kept out.
    %w[Dialog ScrollTo Sound SpeechRecognition].each do |dead|
      refute_includes source, dead, "#{dead} has no consumer in any app"
    end
  end

  def test_shared_components_are_wired_into_the_views_that_use_them
    assert_includes read_source(File.join(ROOT, "shared/app/views/shared/_toast.html.erb")), 'data-controller="toast"'
    # shared/frontend/examples.html.erb is not asserted here. Its first line says
    # "Copy selected examples into each app": it is a snippet library, so its
    # containing data-controller="toast" proves the documentation documents the
    # thing it documents. The line above already asserts the partial that is the
    # real artifact. What it does owe the reader is below.

    wardrobe_form = read_source(File.join(ROOT, "amber/app/views/wardrobe_items/_form.html.erb"))
    assert wardrobe_form.include?("textarea-autogrow") || wardrobe_form.include?("character-counter")
    assert_includes read_source(File.join(ROOT, "shared/app/views/comments/_form_fields.html.erb")), "textarea-autogrow"
    # What matters here is that the post partial is fragment-cached at all. The
    # exact key was pinned as a literal, which froze an implementation detail:
    # keying on Current.user&.id meant a per-guest key, and brgen mints a fresh
    # guest for every cookieless request, so the cache scored zero hits on
    # crawler traffic. Assert the caching, not the key it happens to use.
    fragment = /<% cache \[[^\]]*\bpost\b/
    assert_match fragment, read_source(File.join(ROOT, "brgen/app/views/posts/_post.html.erb"))
    assert_match fragment, read_source(File.join(ROOT, "amber/app/views/posts/_post.html.erb"))
    # The share button uses the shared clipboard component. This pinned the
    # literal PAIR "clipboard popover", which is the same frozen-detail mistake
    # the comment above records for the cache key, six lines up in this test:
    # the popover was a tooltip duplicating the button's own aria-label, it
    # could not fire on a touch viewport at all, and removing it from all four
    # buttons cost 100 of the page's 270 controller instances. Assert the
    # component that does the work, not the company it keeps.
    post_partial = read_source(File.join(ROOT, "brgen/app/views/posts/_post.html.erb"))
    assert_includes post_partial, 'data-controller="clipboard"'
    # ERB comments stripped before the refutation. This fired on 2026-08-10
    # against a partial containing no popover at all: the comment recording *why*
    # the popover was removed says the word, and a refute_includes over raw source
    # cannot tell markup from the note explaining its absence. Third time that
    # shape bit in one session -- see front_page_weight_test.rb.
    refute_includes post_partial.gsub(/<%#.*?%>/m, ""), "popover",
                    "popover was removed as dead weight -- do not reintroduce it as a tooltip"
    assert_includes read_source(File.join(ROOT, "brgen/app/views/posts/_post.html.erb")), "shared/post_card"
    assert_includes read_source(File.join(ROOT, "amber/app/views/posts/_post.html.erb")), "shared/post_card"
    assert_includes read_source(File.join(ROOT, "shared/app/views/shared/_post_card.html.erb")), "shared/feed_card"
    assert_includes read_source(File.join(ROOT, "shared/app/views/shared/_copyable.html.erb")),
                    'data-controller="clipboard"'
  end

  # A snippet library is copied by hand, so a snippet naming a controller that
  # stimulus_boot.js no longer registers hands someone a dead element and no
  # error. content-loader was retired 2026-08-21 and examples.html.erb kept
  # offering it for three weeks. The registry is the authority; this asks only
  # that the documentation stay inside it.
  def test_every_controller_the_snippet_library_offers_is_registered
    registered = registry_source.scan(/\["([a-z-]+)",/).flatten.to_set

    refute_empty registered, "no registrations parsed — the scan broke, not the tree"

    snippets = read_source(File.join(ROOT, "shared/frontend/examples.html.erb"))
    offered = snippets.scan(/data-controller="([^"]+)"/).flatten.flat_map(&:split).to_set

    refute_empty offered, "no snippets parsed — the scan broke, not the tree"
    assert_empty(offered - registered,
                 "examples.html.erb offers a controller stimulus_boot.js does not register")
  end
end
