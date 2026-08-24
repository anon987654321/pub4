# frozen_string_literal: true

module Shared
  # Cross-app x.com UI rendering helpers (icons, nav items, feed tabs).
  module UiHelper
    NavItem = Data.define(:label, :path, :icon, :active, :aria, :data)

    # Where the ambient chat widget loads its room from, or nil if this app has
    # no room to load.
    #
    # brgen's five verticals are MOUNTABLE ENGINES, and an engine's url_helpers
    # do not carry the host application's routes. `_nearby_chat_widget` gated on
    # a bare `respond_to?(:nearby_widget_path)`, which is false inside
    # marketplace, dating, tv, playlist and takeaway — so on those surfaces the
    # shared widget fell through to its "no chat on this app" branch and offered
    # a link to another domain, on the same application, with the same
    # Conversation model and the same room that works on the front page. maps
    # and messenger are not engines, which is exactly why only those two worked.
    #
    # Checking main_app as well makes the widget resolve identically on every
    # brgen surface, and still return nil on amber/bsdports, which genuinely
    # have no Conversation model and should keep the handoff.
    def ambient_chat_frame_path
      return nearby_widget_path if respond_to?(:nearby_widget_path)
      if respond_to?(:main_app) && main_app.respond_to?(:nearby_widget_path)
        return main_app.nearby_widget_path
      end

      nil
    end

    # The room this visitor will land in, known at layout time.
    #
    # The tab used to render t("chat.title") — "chat" — and
    # nearby_chat_controller#syncLabelsFromFrame then rewrote it to the room name
    # once the turbo-frame arrived. That is a visible relabel a beat after the
    # page settles, and it also made the chat tab's own width unstable: measured
    # 2026-08-08, four identical loads gave chat/92px, brgen/102px, brgen/102px,
    # chat/92px depending on whether the frame had landed. layout_snapshot had
    # been drifting on that pair for many runs and re-baselining never converged,
    # because it was re-recording whichever side of the race it caught.
    #
    # Nothing has to be fetched to know the answer: NearbyController#widget picks
    # the geo room when the visitor has coordinates and the city lobby otherwise,
    # from exactly the values available here. Returning nil on an app with no
    # room keeps amber and bsdports on the generic title.
    LOBBY_CHANNEL = "brgen"

    def ambient_chat_room_label
      return nil unless ambient_chat_frame_path

      user = defined?(Current) ? Current.user : nil
      located = user&.latitude.present? && user&.longitude.present?
      located ? "nearby" : LOBBY_CHANNEL
    end

    REACTION_GLYPHS = {
      "like" => :like,
      "love" => :like,
      "laugh" => "😂",
      "wow" => "😮",
      "sad" => "😢",
      "angry" => "😠",
      "local" => "📍",
    }.freeze

    # Every icon partial in the shared engine, by name. Read once at load; the
    # sprite partial and the unknown-name guard below both work off this list, so
    # dropping a file in shared/app/views/shared/icons/ is all it takes to add one.
    ICONS = Dir.children(Engine.root.join("app/views/shared/icons"))
               .filter_map { |f| f[/\A_(.+)\.html\.erb\z/, 1] }
               .sort.freeze

    # Opt-in per app via config.x.icon_sprite. It cannot be "has the sprite
    # partial run yet?", which is what this was first written as: Rails renders
    # the template before the layout, so a flag the layout sets arrives after
    # every content icon has already rendered — the page inlined its feed and
    # only the chrome below the sprite used it. One config value, read here and
    # by the layout, so both agree.
    def icon_sprite?
      Rails.application.config.x.icon_sprite.present?
    end

    def icon(name, size: 18, css_class: nil)
      key = name.to_sym
      # Inlining the paths made an unknown name raise at render (missing partial).
      # A <use href="#icon-nope"> would instead draw nothing, silently — the
      # failure shape this repo keeps finding. Keep it loud.
      unless ICONS.include?(key.to_s)
        raise ArgumentError, "unknown icon #{key.inspect} — known: #{ICONS.join(', ')}"
      end

      render(partial: "shared/icon", locals: { name: key, size: size, css_class: css_class })
    end

    def reaction_glyph(kind)
      glyph = REACTION_GLYPHS.fetch(kind.to_s, kind.to_s)
      return icon(glyph, size: 18) if glyph.is_a?(Symbol)

      tag.span(glyph, class: "reaction-glyph", aria: { hidden: true })
    end

    # autosave_controller.js falls back to English labels, so a form that omits these announces "Saving…" to nb readers.
    def autosave_data(key:, url:)
      {
        "autosave-key-value": key,
        "autosave-url-value": url,
        "autosave-saving-value": t("status.saving"),
        "autosave-saved-value": t("status.saved"),
        "autosave-saved-locally-value": t("status.saved_locally"),
        "autosave-restored-value": t("status.restored"),
      }
    end

    def feed_tab(label:, path:, active: false)
      link_to label, path, class: "feed-tab#{" active" if active}"
    end

    def render_sidebar_nav(items)
      safe_join(Array(items).map { |item| sidebar_nav_link(item) })
    end

    def render_tab_bar(items)
      safe_join(Array(items).map { |item| tab_bar_link(item) })
    end

    # Display name for a comment author (works across guest/anon/username shapes).
    def comment_author_name(comment)
      user = comment.try(:user)
      return t("chat.anon", default: "anon") if user.blank?

      user.try(:username).presence ||
        user.try(:display_name).presence ||
        user.try(:channel_handle).presence ||
        user.try(:email_address).to_s.split("@").first.presence ||
        t("chat.anon", default: "anon")
    end

    # Polymorphic destroy target: nested [commentable, comment] where the app
    # nests both actions, bare comment where :destroy is shallow.
    #
    # The comment above this said exactly that and the code below it did not: it
    # returned the nested pair whenever the parent was persisted, unconditionally.
    # amber nests (`resources :posts { resources :comments }`) and has a
    # post_comment_path; brgen routes them `shallow: true`, so :destroy is a
    # member action at /comments/:id and post_comment_path does not exist. Every
    # delete button brgen rendered raised NoMethodError, and it renders only when
    # comment.user == Current.user — so the page 500'd for the one person entitled
    # to use the button, on posts#show, while comments#destroy itself worked fine.
    #
    # Asked of the route set rather than inferred from the models, because the
    # difference is a routing decision and the apps are entitled to disagree:
    # amber has post_comment and no comment, brgen has comment and no post_comment.
    #
    # named_routes, not respond_to?. A view does not answer respond_to? for its
    # route helpers — it is false for post_comment_path and comment_path alike, in
    # both apps — so a respond_to? test reads as "not nested" everywhere and is
    # right about brgen only by luck, while sending amber to a comment_path it
    # does not have.
    def comment_destroy_arg(comment)
      parent = comment.try(:commentable)
      return comment unless parent.present? && parent.persisted?

      nested = :"#{parent.model_name.singular_route_key}_#{comment.model_name.singular_route_key}"
      Rails.application.routes.named_routes.key?(nested) ? [ parent, comment ] : comment
    end

    # Root post for reply forms when comments nest under comments.
    def comment_root_post(comment)
      parent = comment.try(:commentable)
      return parent if parent.is_a?(Post)
      return parent.commentable if parent.respond_to?(:commentable)

      parent
    end

    def comment_children(comment)
      klass = comment.class
      if klass.respond_to?(:best)
        klass.where(parent_id: comment.id).best
      elsif comment.respond_to?(:replies)
        comment.replies.order(:created_at)
      else
        klass.none
      end
    end

    # Cross-app post author (brgen author_name / amber author_name / fallback).
    def post_display_name(post)
      return t("chat.anon", default: "anon") if post.try(:anonymous?) || post.try(:user)&.try(:guest?)

      post.try(:author_name).presence ||
        post.try(:user)&.try(:display_name).presence ||
        post.try(:user)&.try(:username).presence ||
        t("chat.anon", default: "anon")
    end

    def post_body_text(post)
      post.try(:body).presence || post.try(:content).presence || post.try(:title).to_s
    end

    def post_title_text(post)
      post.try(:title).presence
    end

    def post_avatar_url(post)
      return nil if post.try(:anonymous?) || post.try(:user)&.try(:guest?) || post.try(:live?)

      post.try(:author_avatar_url).presence || post.try(:user)&.try(:avatar_url)
    end

    # Intrinsic dimensions from the analyzed blob, so the browser reserves the
    # box before the bytes arrive (aspect-ratio is derived from the pair even
    # under width:100% CSS). Nothing to reserve is an empty hash, not a guess —
    # unanalyzed blobs and non-attachment sources stay dimensionless.
    def image_dimensions(source)
      meta = source.try(:metadata).presence || source.try(:blob).try(:metadata) || {}
      width, height = meta["width"], meta["height"]
      width && height ? { width: width, height: height } : {}
    end

    # A localised relative time, whole. Fourteen views wrote
    # `<%= time_ago_in_words(x) %> ago`, which prints the Rails-localised span
    # and then an English word: every brgen post page read "rundt 2 måneder
    # ago". Norwegian circumfixes the phrase ("for … siden"), so there is no
    # suffix that fixes it — the whole string has to come from the locale.
    #
    # The five i18n contract tests all passed through this. They measure page
    # titles, aria-labels, search placeholders and controller flashes; nothing
    # looked at body text, and nothing at all could have seen a bare word typed
    # after a helper call. RAILS/test/view_body_copy_i18n_test.rb does now.
    def time_ago(time)
      return nil if time.blank?

      t("shared.time_ago", time: time_ago_in_words(time))
    end

    private

    def sidebar_nav_link(item)
      attrs = nav_item_attrs(item)
      link_options = { class: attrs[:class], aria: attrs[:aria] }
      link_options[:data] = attrs[:data] if attrs[:data].present?
      link_to(attrs[:path], **link_options) do
        safe_join([icon(attrs[:icon], size: 26), tag.span(attrs[:label])])
      end
    end

    def tab_bar_link(item)
      attrs = nav_item_attrs(item)
      link_to(attrs[:path], class: "tab-item", aria: tab_aria(item, attrs)) do
        icon(attrs[:icon], size: 26)
      end
    end

    def nav_item_attrs(item)
      if item.is_a?(NavItem)
        {
          label: item.label,
          path: item.path,
          icon: item.icon,
          class: "nav-item#{" active" if item.active}",
          aria: item.aria || { label: item.label },
          data: item.data
        }
      else
        {
          label: item.fetch(:label),
          path: item.fetch(:path),
          icon: item.fetch(:icon),
          class: "nav-item#{" active" if item[:active]}",
          aria: item[:aria] || { label: item[:label] },
          data: item[:data]
        }
      end
    end

    def tab_aria(item, attrs)
      active = item.is_a?(NavItem) ? item.active : item[:active]
      aria = (attrs[:aria] || {}).dup
      aria[:label] ||= attrs[:label]
      aria[:current] = "page" if active
      aria
    end

    def legal_app_key
      Rails.application.class.module_parent_name.to_s.downcase
    end

    def legal_contact_email
      ENV["SITE_CONTACT_EMAIL"].to_s.strip.presence || "personvern@brgen.no"
    end

    def legal_social_network?
      %w[brgen amber].include?(legal_app_key)
    end
  end
end
