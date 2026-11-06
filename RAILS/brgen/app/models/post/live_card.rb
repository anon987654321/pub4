# frozen_string_literal: true

class Post
  # Everything a post tells the pages that show it, as it happens: the new card
  # on the city's front pages, its score and comment count, an edit, a resolved
  # link embed, and its removal.
  #
  # Synchronous throughout: the _later_ broadcast variants enqueue a job, and
  # nothing on vm23 runs the queue.
  module LiveCard
    extend ActiveSupport::Concern

    included do
      # In-request refresh, not broadcasts_refreshes: that macro enqueues
      # Turbo::Streams::BroadcastStreamJob, and nothing on vm23 runs the queue.
      # The city's posts stream is posts#index; self is posts#show.
      after_commit :broadcast_live_refresh
      # BRGEN-105. The front page is its own stream, and it gets an append rather
      # than a refresh: a refresh replaces the feed under whoever is reading it,
      # which is the behaviour the roadmap names first. The append lands in a hidden
      # staging list and a chip offers it, so nothing moves until the reader says so.
      after_create_commit :broadcast_to_city_feed
      # The card once it is on a page: its score on a vote (a vote touches the
      # post), its text on an edit, and the card itself when it is deleted or a
      # moderator takes it down. Comments send the count from their own side.
      after_update_commit :broadcast_card_changes
      after_destroy_commit :broadcast_removal
    end

    class_methods do
      # Per city, because posts are city-tenanted and one shared stream would put
      # Bergen's feed on Oslo's front page.
      def city_feed_stream(city_id) = "brgen:feed:#{city_id}"

      # posts#index, per city for the same reason.
      def city_posts_stream(city_id) = "brgen:posts:#{city_id}"
    end

    # Takes the card off every front page in the city: out of the pending chip if
    # it is still waiting there, and its row out of the feed. Public because
    # ModerationWorkflow removes with update_columns, which runs no callback.
    def broadcast_removal
      return unless city_feed_public?

      card = "##{ActionView::RecordIdentifier.dom_id(self)}"
      Turbo::StreamsChannel.broadcast_remove_to(
        self.class.city_feed_stream(city_id), targets: "#feed-pending > #{card}, li:has(> #{card})"
      )
    rescue StandardError => e
      Rails.logger.warn("broadcast_removal #{id}: #{e.class}: #{e.message}")
    end

    # Counts, not cards. A card carries the viewer's own vote, repost and quote,
    # so one rendered for the stream would show every reader somebody else's — or
    # nobody's, which takes the vote buttons away from everyone signed in. The
    # score and the comment count are the same for every reader, so only they are
    # sent, into the elements that carry them. Public because Comment calls it:
    # the counter cache moves the count with SQL and runs no callback here.
    def broadcast_live_counts
      content = live_counts_content
      live_streams.each { |stream| Turbo::StreamsChannel.broadcast_stream_to(stream, content:) }
    rescue StandardError => e
      Rails.logger.warn("broadcast_live_counts #{id}: #{e.class}: #{e.message}")
    end

    # Shared::LinkEmbedJob stores the player with update_columns, so no callback
    # tells the card; the job calls this instead.
    def link_embed_resolved = broadcast_card_replacement

    private

    def broadcast_card_changes
      if removed_at.present?
        broadcast_removal if saved_change_to_removed_at?
        return
      end

      broadcast_live_counts
      broadcast_card_replacement if saved_change_to_title? || saved_change_to_content?
    end

    # Read from the table: Vote moves the score with update_all and the comment
    # count is a counter cache, so neither is on this instance.
    def live_counts_content
      rows = Post.unscoped.where(id:)
      score, comments = rows.pick(:score, :comments_count)
      key = ActionView::RecordIdentifier.dom_id(self)
      [
        live_count_update(%([data-post-score="#{key}"]), score.to_i.to_s),
        live_count_update(%([data-post-comment-count="#{key}"]), comments.to_i.positive? ? comments.to_s : "")
      ].join
    end

    def live_count_update(targets, text)
      Turbo::StreamsChannel.turbo_stream_action_tag(:update, targets:, template: text)
    end

    # An edit or a resolved link embed changes what the card says, so the card is
    # sent whole — rendered for nobody, and marked so. feed_updates_controller
    # puts each reader's own vote rail, repost button and quote form back into it
    # (the elements marked data-viewer-state), so nobody's state is lost.
    # Rendered from a fresh read: the instance here may be a job's, with nothing
    # loaded, and the card reads the author, the community and the attachments.
    def broadcast_card_replacement
      return unless city_feed_public?

      rows = Post.unscoped.strict_loading(false)
      card = rows.find_by(id:)
      return unless card

      Current.set(user: nil, session: nil) do
        card.broadcast_replace_to(
          self.class.city_feed_stream(city_id),
          target: card, partial: "posts/post", locals: { post: card },
          attributes: { "data-viewer-neutral": "" }
        )
      end
    rescue StandardError => e
      Rails.logger.warn("broadcast_card_replacement #{id}: #{e.class}: #{e.message}")
    end

    # The city stream reaches every front page open in the city, members or not,
    # so a post in a private community stays off it; its members see it in the
    # community. Asked of the table rather than the association, which strict
    # loading would refuse here.
    def city_feed_public?
      city_id.present? && !(community_id && Community.exists?(id: community_id, privacy: "private"))
    end

    # The post's own page reads every change; the city's front pages only those
    # every reader there may see.
    def live_streams = [ (self.class.city_feed_stream(city_id) if city_feed_public?), self ].compact

    # A refresh re-renders the page under its reader, so it is kept for what
    # only a re-render can show: a post created, deleted, or rewritten. A vote
    # or a comment touches the post too, and refreshing for those closed every
    # open reply box on the page; the counts and the comment arrive on their
    # own (broadcast_live_counts, Comment#broadcast_to_thread).
    def broadcast_live_refresh
      return unless refresh_worthy_commit?

      broadcast_refresh_to self.class.city_posts_stream(city_id) if city_id && city_feed_public?
      broadcast_refresh_to self
    end

    TOUCH_COLUMNS = %w[updated_at score comments_count reposts_count crossposts_count].freeze
    private_constant :TOUCH_COLUMNS

    def refresh_worthy_commit?
      return true if destroyed? || previously_new_record?

      saved_changes.keys.any? { |column| TOUCH_COLUMNS.exclude?(column) }
    end

    # Rendered with no Current.user, so the card carries nobody's vote, repost or
    # quote state — on the creating request Current.user is the author, and the
    # vote rail would otherwise hand every reader the author's buttons. A post
    # created a moment ago has none of the three from anyone, so this is the card
    # every reader should see at that instant.
    def broadcast_to_city_feed
      return if removed_at.present? || !city_feed_public?

      Current.set(user: nil, session: nil) do
        broadcast_prepend_to(
          self.class.city_feed_stream(city_id),
          target: "feed-pending", partial: "posts/post", locals: { post: self, staged: true }
        )
      end
    rescue StandardError => e
      Rails.logger.warn("broadcast_to_city_feed #{id}: #{e.class}: #{e.message}")
    end
  end
end
