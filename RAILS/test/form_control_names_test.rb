# frozen_string_literal: true

require "minitest/autorun"
require "set"

# Every form control needs an accessible name. The recorded `form_no_label` rule
# asked a different question -- "does this file contain a <label> element" -- and
# that is neither necessary nor sufficient.
#
# Not necessary: aria-label names a control perfectly well, and this tree uses it
# widely for icon-sized controls where a visible label would redesign the row.
# Ten of the eighteen recorded findings were already named that way.
#
# Not sufficient, which is the more interesting half. amber's AI forms had
# <label>Duration</label> sitting *beside* the select rather than wrapping it or
# carrying for=, so the label named nothing: the select read as unlabelled and
# clicking the word did not focus it. brgen's compose bar wraps three file inputs
# in labels whose only content is an aria-hidden icon, so the name computes to
# "" -- three consecutive "unlabelled file upload" announcements with nothing to
# tell them apart. title= is a tooltip, not a name.
#
# So this checks what the platform actually computes a name from: a <label for>,
# a wrapping <label> with text in it, aria-label, aria-labelledby, or -- for the
# Rails helpers this tree writes in -- f.label :attr / label_tag :name.
class FormControlNamesTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  SKIP_INPUT_TYPES = %w[hidden submit button image reset].freeze

  FORM_HELPERS = %w[
    text_field text_area email_field password_field number_field search_field
    telephone_field phone_field url_field date_field time_field datetime_field
    datetime_local_field month_field week_field color_field range_field
    file_field select collection_select grouped_collection_select
    time_zone_select collection_check_boxes collection_radio_buttons check_box
    radio_button rich_text_area
  ].freeze

  TAG_HELPERS = FORM_HELPERS.map { |h| "#{h}_tag" }.freeze

  # Two controls this checker cannot read, both named in the markup, both cases
  # where a regex over ERB source is the wrong tool rather than the view being
  # wrong. Kept explicit so the list cannot quietly grow.
  #
  #   playlist/playlists/show.html.erb:42 — the input's value= holds an escaped
  #     <iframe …> whose `>` ends the tag match early, before its aria-label.
  #   takeaway/orders/new.html.erb:41 — label_tag and the field's id: are both
  #     "takeaway_order_items_#{item.id}", and the interpolation only resolves
  #     at render time.
  KNOWN_UNREADABLE = [
    "brgen/engines/playlist/app/views/playlist/playlists/show.html.erb",
    "brgen/engines/takeaway/app/views/takeaway/orders/new.html.erb",
  ].freeze

  def views
    @views ||= %w[amber brgen bsdports shared].flat_map do |app|
      Dir.glob(File.join(ROOT, app, "app/views/**/*.erb")) +
        Dir.glob(File.join(ROOT, app, "engines/*/app/views/**/*.erb"))
    end.reject { |f| f.include?("/vendor/") }.sort
  end

  # ERB blanked so a `>` inside <%= %> cannot terminate an HTML tag early. The
  # first version of this scan reported aria-labelled inputs as unnamed because
  # value="<%= params[:q] %>" closed the tag before aria-label was reached.
  def strip_erb(src)
    src.gsub(/<%.*?%>/m) { |m| " " * m.length }
  end

  def unnamed_controls(path)
    src = File.read(path)
    stripped = strip_erb(src)
    label_for = stripped.scan(/<label[^>]*\bfor=["']([^"']+)/).flatten.to_set
    helper_labels = src.scan(/\.label\s+:([a-z_0-9]+)/).flatten.to_set +
                    src.scan(/label_tag\s+[:"']([a-z_0-9]+)/).flatten.to_set

    spans = []
    stripped.to_enum(:scan, %r{<label\b[^>]*>(.*?)</label>}m).each do
      md = Regexp.last_match
      inner = src[md.begin(1), md[1].length].to_s
      text = inner.gsub(/<%.*?%>/m, " ").gsub(/<[^>]*>/m, " ")
      erb_text = inner.scan(/<%=\s*(?:t\(|.*?\.capitalize|.*?\.humanize)/m)
      spans << { from: md.begin(0), to: md.end(0), named: text.strip.length.positive? || erb_text.any? }
    end
    in_named_label = ->(pos) { spans.any? { |s| pos > s[:from] && pos < s[:to] && s[:named] } }

    found = []

    stripped.to_enum(:scan, /<(input|textarea|select)\b([^>]*)>/mi).each do
      md = Regexp.last_match # snapshot: the probes below reset Regexp.last_match
      tag = md[1].downcase
      at = md.begin(0)
      attrs = src[at, md[0].length].to_s
      type = attrs[/\btype=["']?([a-z]+)/i, 1]&.downcase
      next if tag == "input" && SKIP_INPUT_TYPES.include?(type.to_s)
      next if attrs =~ /aria-label\s*=/ || attrs =~ /aria-labelledby\s*=/
      next if in_named_label.call(at)

      id = attrs[/\bid=["']([^"']+)/, 1]
      next if id && label_for.include?(id)

      found << "#{src[0...at].count("\n") + 1}: <#{tag}#{type ? " type=#{type}" : ""}>"
    end

    src.to_enum(:scan, /<%=?-?(.*?)-?%>/m).each do
      md = Regexp.last_match
      body = md[1]
      hit = body.match(/\b\w+\.(#{FORM_HELPERS.join("|")})\b\s*:([a-z_0-9]+)/) ||
            body.match(/\b(#{TAG_HELPERS.join("|")})\s*\(?\s*[:"']([a-z_0-9\[\]]+)/)
      next unless hit

      helper, attr = hit[1], hit[2]
      next if helper.start_with?("hidden")
      next if body =~ /aria:\s*\{[^}]*label/m || body =~ /aria-label/
      next if in_named_label.call(md.begin(0))
      next if helper_labels.include?(attr) || label_for.include?(attr)

      explicit_id = body[/\bid:\s*["']([^"']+)["']/, 1]
      next if explicit_id && label_for.include?(explicit_id)

      found << "#{src[0...md.begin(0)].count("\n") + 1}: #{helper} :#{attr}"
    end

    found
  end

  def test_the_scan_reaches_engine_views
    refute_empty views, "no views found — the glob is wrong, not the tree"
    assert views.any? { |v| v.include?("/engines/") },
           "engine views are missing, which is the blind spot that hid 57 views " \
           "when the brgen verticals moved"
  end

  def test_a_control_without_an_accessible_name_is_caught
    # Proves the check can fail: a select with no label of any kind.
    Dir.mktmpdir do |dir|
      path = File.join(dir, "probe.html.erb")
      File.write(path, "<div><%= f.select :season, Item::SEASONS %></div>\n")
      assert_equal ["1: select :season"], unnamed_controls(path)
    end
  end

  def test_a_label_beside_a_field_does_not_count_as_naming_it
    Dir.mktmpdir do |dir|
      beside = File.join(dir, "beside.html.erb")
      File.write(beside, "<label>Duration</label>\n<%= f.select :duration, [] %>\n")
      refute_empty unnamed_controls(beside),
                   "a <label> that neither wraps the field nor carries for= names nothing"

      wired = File.join(dir, "wired.html.erb")
      File.write(wired, "<%= f.label :duration, \"Duration\" %>\n<%= f.select :duration, [] %>\n")
      assert_empty unnamed_controls(wired)
    end
  end

  def test_every_form_control_has_an_accessible_name
    offenders = views.filter_map do |path|
      rel = path.delete_prefix("#{ROOT}/")
      next if KNOWN_UNREADABLE.include?(rel)

      found = unnamed_controls(path)
      "#{rel}\n    #{found.join("\n    ")}" if found.any?
    end

    assert_empty offenders, <<~MSG.strip
      form controls with no accessible name:

        #{offenders.join("\n  ")}

      Give each one a <label for>, a wrapping <label> with text, an aria-label,
      or f.label :attr. A placeholder is not a name (it disappears on input) and
      neither is title=.
    MSG
  end
end

require "tmpdir"
