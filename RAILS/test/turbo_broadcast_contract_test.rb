# frozen_string_literal: true

require "minitest/autorun"

# A Turbo broadcast that names a partial which does not exist does not raise where
# anyone sees it. `broadcast_*_later_to` enqueues a job; the job raises
# ActionView::MissingTemplate inside Solid Queue; the page simply never updates.
# OPENBSD/data/debt.yml called this out as "several Turbo broadcasts use implicit
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
#   2. The Shared::* social models broadcast implicitly. Three were cut 2026-08-02
#      (Post, Follow, ChatMessage) — no usable table in any schema and zero references,
#      so they were the genuinely dead layer. Three remain and are tolerated here rather
#      than exempted: Shared::ReviewCase backs amber reports and Shared::Reaction/
#      Notification are `defined?`-guarded fallbacks. Their real tables (reactions/
#      notifications/review_cases) do exist in brgen/amber, so unlike the cut trio their
#      broadcasts CAN fire — giving them partials or making the callbacks explicit is the
#      open follow-up this list is documenting, not resolving.
class TurboBroadcastContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  APPS = %w[brgen amber bsdports].freeze
  BROADCAST = /broadcast_\w*(?:append|prepend|replace|update|remove|before|after)\w*_(?:later_)?to\b/

  # Shared::* social models still tolerated here. Post, Follow, and ChatMessage were
  # cut 2026-08-02 — shared_posts/shared_chat_messages exist in no schema, Shared::Follow
  # had zero references, and none could be instantiated. The three that remain are NOT
  # dead: Shared::ReviewCase backs amber's reports, and Shared::Reaction/Notification are
  # fallbacks behind `defined?(::Reaction/::Notification)`. NOTE their real table_names are
  # reactions/notifications/review_cases (generic, present in brgen/amber) — the shared_*
  # names below never exist, so this tolerance is honest for the shared_ ones only;
  # whether these three should broadcast implicitly at all is the open follow-up.
  TABLELESS_SHARED = {
    "shared/reaction.rb" => "shared_reactions",
    "shared/notification.rb" => "shared_notifications",
    "shared/review_case.rb" => "shared_review_cases",
  }.freeze

  def schema(app) = File.read(File.join(ROOT, app, "db/schema.rb"))

  def table?(app, name) = schema(app).include?(%(create_table "#{name}"))

  # app/models/tv/stream_chat.rb -> tv/stream_chats/_stream_chat.html.erb
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
        next if TABLELESS_SHARED.key?(row[:file])

        wanted = partial_for(row[:file])
        found = [File.join(ROOT, app, "app/views", wanted), File.join(ROOT, "shared/app/views", wanted)]
        next if found.any? { |candidate| File.file?(candidate) }

        missing << "#{app}: #{row[:file]}:#{row[:line]} broadcasts with no partial: and no #{wanted}"
      end
    end

    assert_empty missing, missing.join("\n")
  end

  def test_the_tolerated_shared_models_still_have_no_table_anywhere
    TABLELESS_SHARED.each do |file, table|
      APPS.each do |app|
        refute table?(app, table),
               "#{app} now has #{table}, so #{file}'s broadcast can fire — give it a partial " \
               "(#{partial_for(file)}) and remove it from TABLELESS_SHARED"
      end
    end
  end

  # The two that were wired: both keywords, because target: matters as much as
  # partial: — the default target is derived from the model, not from the container
  # the page actually renders.
  def test_the_tv_broadcasts_name_both_partial_and_target
    {
      "brgen/app/models/tv/stream_chat.rb" => %w[tv/stream_chats/stream_chat tv-live-stream-],
      "brgen/app/models/tv/video_note.rb" => %w[tv/video_notes/video_note video_notes_],
    }.each do |file, (partial, target)|
      body = File.read(File.join(ROOT, file))

      assert_includes body, "partial: \"#{partial}\""
      assert_includes body, "target: \"#{target}"
    end
  end

  def test_the_wired_partials_exist
    %w[
      brgen/app/views/tv/stream_chats/_stream_chat.html.erb
      brgen/app/views/tv/video_notes/_video_note.html.erb
    ].each { |path| assert File.file?(File.join(ROOT, path)), "missing #{path}" }
  end

  # A broadcast needs a listener as much as a partial. These two streams are the ones
  # this pass wired end to end.
  def test_the_tv_streams_have_subscribers
    {
      "brgen/app/views/tv/live_streams/show.html.erb" => "tv:live_stream:",
      "brgen/app/views/tv/videos/show.html.erb" => "tv:video:",
    }.each do |view, stream|
      body = File.read(File.join(ROOT, view))

      assert_match(/turbo_stream_from "#{Regexp.escape(stream)}/, body, "#{view} must subscribe to #{stream}")
    end
  end

  # Each removal is a claim that nothing subscribes to that stream. If someone adds
  # the subscriber later, this fails and points at the callback to restore.
  def test_the_removed_streams_still_have_no_subscribers
    views = APPS.flat_map { |app| Dir.glob(File.join(ROOT, app, "app/views/**/*.erb")) } +
            Dir.glob(File.join(ROOT, "shared/app/views/**/*.erb"))
    subscriptions = views.map { |path| File.read(path) }.join("\n")

    ["brgen:reactions", "playlist:track:", "bsdports:security_advisories"].each do |stream|
      refute_match(/turbo_stream_from[^\n]*#{Regexp.escape(stream)}/, subscriptions,
                   "#{stream} has a subscriber now — restore the broadcast it lost, with an explicit partial")
    end
  end
end
