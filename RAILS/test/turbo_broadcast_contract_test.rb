# frozen_string_literal: true

require "minitest/autorun"

# A Turbo broadcast that names a partial which does not exist does not raise where
# anyone sees it. `broadcast_*_later_to` enqueues a job; the job raises
# ActionView::MissingTemplate inside Solid Queue; the page simply never updates.
# TODO.md called this out as "several Turbo broadcasts use implicit
# to_partial_path with no matching partial" — there were more than several, and the
# reasons split into two very different groups.
#
# This test pins both:
#
#   1. Every implicit broadcast from a model whose table exists must have the
#      partial its to_partial_path resolves to. Two did not (Tv::StreamChat,
#      Tv::VideoNote) and are now explicit; three more (Reaction,
#      Playlist::TimestampedComment, SecurityAdvisory) broadcast into streams with no
#      subscriber and no container at all and were removed rather than wired.
#
#   2. The Shared::* social models used to broadcast implicitly. Post, Follow, and
#      ChatMessage were cut 2026-08-02 (no usable table in any schema, zero references).
#      The three that remained — Reaction, Notification, ReviewCase — kept implicit
#      broadcasts into shared:reactions/notifications/review_cases, streams with no
#      subscriber and no partial anywhere. Their tables DO exist (amber even creates
#      ReviewCase rows), so unlike the cut trio the callbacks could actually fire and
#      raise MissingTemplate in Solid Queue. Those three callbacks were removed 2026-08-02
#      — the same treatment the Tv/Playlist dead broadcasts got. There is now no implicit
#      Shared::* broadcast left to tolerate; the streams are guarded below with the other
#      removed ones, so re-adding a subscriber without a partial fails this test.
class TurboBroadcastContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  APPS = %w[brgen amber bsdports].freeze
  BROADCAST = /broadcast_\w*(?:append|prepend|replace|update|remove|before|after)\w*_(?:later_)?to\b/

  # engines/tv/app/models/tv/stream_chat.rb -> tv/stream_chats/_stream_chat.html.erb
  def partial_for(relative)
    parts = relative.sub(/\.rb\z/, "").split("/")
    base = parts.pop
    plural = base.end_with?("y") ? "#{base[0..-2]}ies" : "#{base}s"
    (parts + [plural, "_#{base}.html.erb"]).join("/")
  end

  # Broadcast calls that pass no partial:. Read as whole statements — these calls
  # routinely span several lines, and looking at one line at a time reports every
  # multi-line call as implicit.
  def implicit_broadcasts(app)
    roots = { File.join(ROOT, app, "app/models") => nil, File.join(ROOT, "shared/app/models") => "shared engine" }
    # Verticals extracted to mountable engines (engines/*/app/models) carry their
    # own models now — scan them too, or a broadcast that moves with tv/playlist
    # would slip the net. See ENGINES.md.
    Dir.glob(File.join(ROOT, app, "engines/*/app/models")).each { |dir| roots[dir] = "engine" }
    roots.flat_map do |root, _label|
      Dir.glob(File.join(root, "**", "*.rb")).flat_map do |path|
        lines = File.readlines(path)
        lines.each_index.filter_map do |index|
          line = lines[index]
          next unless line.match?(BROADCAST)
          next if line.strip.start_with?("#") # a comment about a broadcast is not one
          next if line.include?("Turbo::StreamsChannel") # explicit target form
          next if lines[index, 5].join.include?("partial:")

          { file: path.sub("#{root}/", ""), line: index + 1 }
        end
      end
    end
  end

  def test_every_reachable_implicit_broadcast_has_its_partial
    missing = []

    APPS.each do |app|
      implicit_broadcasts(app).each do |row|
        wanted = partial_for(row[:file])
        found = [File.join(ROOT, app, "app/views", wanted), File.join(ROOT, "shared/app/views", wanted)]
        found += Dir.glob(File.join(ROOT, app, "engines/*/app/views", wanted))
        next if found.any? { |candidate| File.file?(candidate) }

        missing << "#{app}: #{row[:file]}:#{row[:line]} broadcasts with no partial: and no #{wanted}"
      end
    end

    assert_empty missing, missing.join("\n")
  end

  # The three Shared::* callbacks removed 2026-08-02 must stay removed. If someone
  # reintroduces `broadcast_*_later_to "shared:..."` without a partial, the scan
  # above catches the missing partial; this pins the models themselves clean so the
  # intent (explicit-or-nothing) is legible at the source, not just the view side.
  def test_the_shared_social_models_do_not_broadcast_implicitly
    %w[reaction notification review_case].each do |name|
      body = File.read(File.join(ROOT, "shared/app/models/shared/#{name}.rb"))
      broadcasts = body.lines.reject { |l| l.strip.start_with?("#") }.select { |l| l.match?(BROADCAST) }

      assert_empty broadcasts,
                   "shared/#{name}.rb broadcasts again — make it explicit (partial: + target:) " \
                   "and add its stream a subscriber, or leave the callback out"
    end
  end

  # The two that were wired: both keywords, because target: matters as much as
  # partial: — the default target is derived from the model, not from the container
  # the page actually renders.
  def test_the_tv_broadcasts_name_both_partial_and_target
    {
      "brgen/engines/tv/app/models/tv/stream_chat.rb" => %w[tv/stream_chats/stream_chat tv-live-stream-],
      "brgen/engines/tv/app/models/tv/video_note.rb" => %w[tv/video_notes/video_note video_notes_],
    }.each do |file, (partial, target)|
      body = File.read(File.join(ROOT, file))

      assert_includes body, "partial: \"#{partial}\""
      assert_includes body, "target: \"#{target}"
    end
  end

  def test_the_wired_partials_exist
    %w[
      brgen/engines/tv/app/views/tv/stream_chats/_stream_chat.html.erb
      brgen/engines/tv/app/views/tv/video_notes/_video_note.html.erb
    ].each { |path| assert File.file?(File.join(ROOT, path)), "missing #{path}" }
  end

  # A broadcast needs a listener as much as a partial. These two streams are the ones
  # this pass wired end to end.
  def test_the_tv_streams_have_subscribers
    {
      "brgen/engines/tv/app/views/tv/live_streams/show.html.erb" => "tv:live_stream:",
      "brgen/engines/tv/app/views/tv/videos/show.html.erb" => "tv:video:",
    }.each do |view, stream|
      body = File.read(File.join(ROOT, view))

      assert_match(/turbo_stream_from "#{Regexp.escape(stream)}/, body, "#{view} must subscribe to #{stream}")
    end
  end

  # Each removal is a claim that nothing subscribes to that stream. If someone adds
  # the subscriber later, this fails and points at the callback to restore.
  def test_the_removed_streams_still_have_no_subscribers
    views = APPS.flat_map { |app| Dir.glob(File.join(ROOT, app, "app/views/**/*.erb")) } +
            APPS.flat_map { |app| Dir.glob(File.join(ROOT, app, "engines/*/app/views/**/*.erb")) } +
            Dir.glob(File.join(ROOT, "shared/app/views/**/*.erb"))
    subscriptions = views.map { |path| File.read(path) }.join("\n")

    [
      "brgen:reactions", "playlist:track:", "bsdports:security_advisories",
      "shared:reactions", "shared:notifications", "shared:review_cases"
    ].each do |stream|
      refute_match(/turbo_stream_from[^\n]*#{Regexp.escape(stream)}/, subscriptions,
                   "#{stream} has a subscriber now — restore the broadcast it lost, with an explicit partial")
    end
  end

  # `_later` and `broadcasts_refreshes` enqueue Turbo::Streams::BroadcastStreamJob.
  # vm23 has no Solid Queue worker, so those writes never happen. In-request
  # `broadcast_refresh_to` / `broadcast_append_to` write Solid Cable now.
  def test_models_do_not_enqueue_turbo_broadcast_jobs
    later = /broadcast_\w+_later_to\b|^\s*broadcasts_refreshes\b/
    hits = []

    roots = APPS.flat_map { |app|
      [ File.join(ROOT, app, "app/models"), File.join(ROOT, app, "engines/*/app/models") ]
    } + [ File.join(ROOT, "shared/app/models"), File.join(ROOT, "shared/app/reflexes") ]

    roots.each do |glob|
      Dir.glob(File.join(glob, "**", "*.rb")).each do |path|
        File.readlines(path).each_with_index do |line, index|
          next if line.strip.start_with?("#")
          next unless line.match?(later)

          hits << "#{path.sub("#{ROOT}/", "")}:#{index + 1}: #{line.strip}"
        end
      end
    end

    assert_empty hits, "enqueueing a broadcast while no worker runs:\n#{hits.join("\n")}"
  end

  # Every named stream, read from both ends.
  #
  # The tests above ask whether a broadcast has a partial, and whether three
  # named streams stayed unsubscribed. Neither asks the general question, and
  # two pairs had never matched — invisible from either end alone, because one
  # end is a model and the other a view:
  #
  #   brgen:notifications:*  written on every notification create, read nowhere
  #   items                  subscribed by amber's busiest page, written nowhere
  #
  # Literal streams only, and that is the whole of the instrument's honesty.
  # `broadcast_refresh_to self` and `broadcast_append_to conversation` name their
  # stream at runtime; guessing which view subscribes to `@conversation` is how a
  # census reports the shape of the tree and calls it a defect. Interpolation
  # collapses to `*`, so "brgen:matches:#{user.id}" written in a model and
  # "brgen:matches:#{Current.user.id}" read in a layout are one name.
  #
  # Ruby is scanned across app/ rather than app/models: nearby_alerts_* is
  # written by LocationsController through Turbo::StreamsChannel, and a
  # models-only scan called the layout's subscription dead.
  # Wider than BROADCAST above, which names the DOM verbs. broadcast_refresh_to
  # carries a stream name too, and leaving it out made the census report amber's
  # outfits and planned_outfits subscriptions as orphans — the instrument
  # answering for three quarters of the fleet's named streams.
  # The line names the call; the stream name may be on the next one.
  # `Turbo::StreamsChannel.broadcast_append_to(` puts its literal a line down,
  # and requiring the two together read LocationsController as silent and the
  # layout's nearby_alerts subscription as an orphan.
  ANY_BROADCAST_LINE = /broadcast_\w*to\b/
  ANY_BROADCAST = /broadcast_\w*to\s*\(?\s*"([^"]*)"/m

  # A stream written with no reader, tolerated with the reason. Each entry is a
  # claim; an entry that stops matching is a hole in the gate and fails below.
  UNREAD_STREAMS = {
    "brgen:notifications:*" =>
      "NotificationDeliveryJob is enqueued by nothing and kept only until vm23 confirms no " \
      "queued row names it — see the job's header. Its broadcast goes when the class does.",
  }.freeze

  def normalise(stream) = stream.gsub(/\#\{[^}]*\}/, "*")

  def ruby_sources
    @ruby_sources ||= APPS.flat_map { |app| Dir.glob(File.join(ROOT, app, "app/**/*.rb")) } +
                      APPS.flat_map { |app| Dir.glob(File.join(ROOT, app, "engines/*/app/**/*.rb")) } +
                      Dir.glob(File.join(ROOT, "shared/app/**/*.rb"))
  end

  def view_sources
    @view_sources ||= APPS.flat_map { |app| Dir.glob(File.join(ROOT, app, "app/views/**/*.erb")) } +
                      APPS.flat_map { |app| Dir.glob(File.join(ROOT, app, "engines/*/app/views/**/*.erb")) } +
                      Dir.glob(File.join(ROOT, "shared/app/views/**/*.erb"))
  end

  def named_broadcasts
    ruby_sources.flat_map do |path|
      lines = File.readlines(path)
      lines.each_index.filter_map do |index|
        next if lines[index].strip.start_with?("#")
        next unless lines[index].match?(ANY_BROADCAST_LINE)

        stream = lines[index, 4].join[ANY_BROADCAST, 1]
        { stream: normalise(stream), at: "#{path.sub("#{ROOT}/", '')}:#{index + 1}" } if stream
      end
    end
  end

  # ERB comments blanked first, and length-preserving so line numbers still land.
  # The note explaining why a subscription was dropped names the call it dropped,
  # so a raw scan read the explanation as the thing — the failure mode this repo
  # has recorded four times, and it fired here on the first run.
  def without_erb_comments(source)
    source.gsub(/<%#.*?%>/m) { |match| match.gsub(/[^\n]/, " ") }
  end

  def named_subscriptions
    view_sources.flat_map do |path|
      without_erb_comments(File.read(path)).each_line.with_index.filter_map do |line, index|
        stream = line[/turbo_stream_from\s+"([^"]*)"/, 1]
        { stream: normalise(stream), at: "#{path.sub("#{ROOT}/", '')}:#{index + 1}" } if stream
      end
    end
  end

  def test_the_census_still_sees_both_ends
    assert_operator named_broadcasts.size, :>=, 8, "the broadcast scan stopped matching"
    assert_operator named_subscriptions.size, :>=, 8, "the subscription scan stopped matching"
  end

  def test_every_named_broadcast_has_a_subscriber
    read = named_subscriptions.map { |row| row[:stream] }.uniq
    unread = named_broadcasts.reject { |row| read.include?(row[:stream]) }
    surprises = unread.reject { |row| UNREAD_STREAMS.key?(row[:stream]) }

    assert_empty surprises.map { |row| "#{row[:at]} writes #{row[:stream]}, nothing subscribes" },
                 "wire the reader, or record the stream in UNREAD_STREAMS with the reason"

    stale = UNREAD_STREAMS.keys - unread.map { |row| row[:stream] }
    assert_empty stale, "these are no longer written or now have a reader — drop them from UNREAD_STREAMS"
  end

  def test_every_subscription_has_a_broadcaster
    written = named_broadcasts.map { |row| row[:stream] }.uniq
    orphans = named_subscriptions.reject { |row| written.include?(row[:stream]) }

    assert_empty orphans.map { |row| "#{row[:at]} subscribes to #{row[:stream]}, nothing writes it" },
                 "a subscription to a stream nothing writes opens a connection per viewer and " \
                 "delivers nothing — drop it, or write the stream"
  end
end
