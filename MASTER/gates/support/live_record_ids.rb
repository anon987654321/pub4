# frozen_string_literal: true

require "sqlite3"

module Deploy
  # Resolves a real seeded record's id, slug or token out of the app's own
  # development sqlite3 file -- no Rails boot, because gates run under bare
  # ruby -- so page_simulation can fill in the :id/:slug/:channel_slug segment
  # a guest_needing_id page names and probe it live instead of only naming it.
  #
  # Every host page_inventory ever builds for brgen (the apex or a
  # markedsplass./tv./radio.-style subdomain) resolves to Bergen under
  # Brgen::DomainRegistry, so every CityTenantable table here is scoped to
  # Bergen's row: ActsAsTenant's default_scope filters strictly on city_id
  # once a tenant is set (acts_as_tenant :city, optional: true means the
  # column may be null on write, not that the read scope also matches null),
  # and a record from another city 404s under that scope.
  #
  # Not every guest_needing_id route is here. A route stays unresolved, and
  # page_simulation keeps naming it, when:
  #   - no seed script in this repo writes that table at all (events, stories,
  #     hashtags, partner programs/memberships, marketplace deals, community
  #     wiki pages, tv shows/episodes/live_streams/sounds) -- adding that
  #     coverage is seed-data work, not wiring;
  #   - the table's only local rows come from the package-index import
  #     fallback, which OpenBSD's mirror does not publish maintainer data
  #     into (bsdports maintainers) -- only a full tree/tarball import would;
  #   - the record is a single-use, expiring credential a guest can only ever
  #     hold one of at a time (passwords/:token/edit) -- there is no seeded
  #     token that is still both unused and unexpired to point at;
  #   - the record is scoped to whichever identity is asking rather than to
  #     the app: Shared::Authentication#resume_session mints a fresh guest
  #     user on every unauthenticated request, and ConversationsController
  #     scopes #show through `Conversation.for_user(Current.user)` -- that new
  #     guest is never a participant of a conversation seeded ahead of time,
  #     so any id 404s (conversations/:id). The same is true one level down:
  #     ListeningPartiesController#show requires @set.listening_party to
  #     already exist, and no seed script creates one, so
  #     sets/:set_id/listening_party has nothing to resolve to yet either.
  module LiveRecordIds
    ROOT = File.expand_path("../../..", __dir__)

    DB_PATH = {
      "brgen" => File.join(ROOT, "RAILS", "brgen", "storage", "development.sqlite3"),
      "amber" => File.join(ROOT, "RAILS", "amber", "storage", "development.sqlite3"),
      "bsdports" => File.join(ROOT, "RAILS", "bsdports", "storage", "development.sqlite3"),
    }.freeze

    # brgen.no itself -- the only city page_inventory ever points a host at.
    BERGEN_CITY_ID = 1

    RESOLVERS = {
      "brgen/channels/show" => :irc_channel,
      "brgen/communities/show" => :community,
      "brgen/communities/bans/index" => :community_id,
      "brgen/communities/moderation/index" => :community_id,
      "brgen/communities/moderators/index" => :community_id,
      "brgen/communities/wiki/index" => :community_id,
      "brgen/posts/show" => :post,
      "brgen/users/show" => :user,
      "brgen/maps/places/show" => :place,
      "brgen/marketplace/categories/show" => :marketplace_category,
      "brgen/marketplace/listings/show" => :marketplace_listing,
      "brgen/marketplace/variants/index" => :marketplace_listing_id,
      "brgen/marketplace/stores/show" => :marketplace_store,
      "brgen/playlist/hosted_tracks/show" => :hosted_track,
      "brgen/playlist/sets/show" => :playlist_set,
      "brgen/playlist/playlists/show" => :playlist,
      "brgen/playlist/playlists/embed" => :playlist,
      "brgen/takeaway/delivery_drivers/show" => :delivery_driver,
      "brgen/takeaway/restaurants/show" => :restaurant,
      "brgen/tv/channels/show" => :tv_channel,
      "brgen/tv/shows/index" => :tv_channel_slug,
      "brgen/tv/videos/show" => :tv_video,
      "amber/demo_wardrobe/show" => :amber_demo_item,
      "bsdports/categories/show" => :bsdports_category,
      "bsdports/ports/show" => :bsdports_port,
    }.freeze

    module_function

    # page[:path] with every :segment filled in from a real row, or nil when
    # this route has no resolver or the table it needs has no seeded row yet.
    def resolve(page)
      method = RESOLVERS[page[:id]]
      return nil unless method

      params = send(method, page[:app])
      params && substitute(page[:path], params)
    end

    def substitute(path, params)
      path.split("/").map do |segment|
        next segment unless segment.start_with?(":")

        key = segment.delete_prefix(":").to_sym
        return nil unless params.key?(key)

        params[key].to_s
      end.join("/")
    end

    # -- brgen -----------------------------------------------------------

    # Conversation::Channels#find_or_create_channel seeds "brgen" (the
    # city-wide lobby) on first visit, so the room does not need to exist
    # before this probe -- it is one of Conversation::Channels::CHANNELS,
    # not a row.
    def irc_channel(_app) = { slug: "brgen" }

    def community(app)
      id = scalar(app, "SELECT id FROM communities WHERE city_id = ? ORDER BY id LIMIT 1", BERGEN_CITY_ID)
      id && { id: id }
    end

    def community_id(app)
      id = scalar(app, "SELECT id FROM communities WHERE city_id = ? ORDER BY id LIMIT 1", BERGEN_CITY_ID)
      id && { community_id: id }
    end

    def post(app)
      id = scalar(app, "SELECT id FROM posts WHERE city_id = ? AND removed_at IS NULL ORDER BY id LIMIT 1", BERGEN_CITY_ID)
      id && { id: id }
    end

    def user(app)
      id = scalar(app, <<~SQL, BERGEN_CITY_ID)
        SELECT id FROM users
        WHERE city_id = ? AND guest = 0 AND deleted_at IS NULL AND username IS NOT NULL
        ORDER BY id LIMIT 1
      SQL
      id && { id: id }
    end

    def place(app)
      id = scalar(app, "SELECT id FROM places WHERE city_id = ? ORDER BY id LIMIT 1", BERGEN_CITY_ID)
      id && { id: id }
    end

    # Marketplace::CategoriesController#show is `find_by!(slug: params[:id])`
    # with no numeric fallback, so the :id segment here has to be the slug.
    def marketplace_category(app)
      slug = scalar(app, "SELECT slug FROM marketplace_categories WHERE slug IS NOT NULL ORDER BY id LIMIT 1")
      slug && { id: slug }
    end

    def marketplace_listing(app)
      id = marketplace_listing_row(app)
      id && { id: id }
    end

    def marketplace_listing_id(app)
      id = marketplace_listing_row(app)
      id && { listing_id: id }
    end

    def marketplace_listing_row(app)
      scalar(app, "SELECT id FROM marketplace_listings WHERE city_id = ? ORDER BY id LIMIT 1", BERGEN_CITY_ID)
    end

    # Marketplace::StoresController#show is also slug-only.
    def marketplace_store(app)
      slug = scalar(app, "SELECT slug FROM marketplace_stores WHERE city_id = ? ORDER BY id LIMIT 1", BERGEN_CITY_ID)
      slug && { id: slug }
    end

    # HostedTracksController#set_track only shows privacy public/unlisted/blank
    # to a guest, and expired tracks are gone from the catalogue either way.
    def hosted_track(app)
      id = scalar(app, <<~SQL)
        SELECT id FROM playlist_tracks
        WHERE privacy = 'public' AND (expires_at IS NULL OR expires_at > datetime('now'))
        ORDER BY id LIMIT 1
      SQL
      id && { id: id }
    end

    # SetsController#show reads private as "owner or collaborator only", which
    # a guest probe is neither.
    def playlist_set(app)
      id = scalar(app, "SELECT id FROM playlist_sets WHERE privacy = 'public' ORDER BY id LIMIT 1")
      id && { id: id }
    end

    def playlist(app)
      id = scalar(app, "SELECT id FROM playlist_playlists WHERE city_id = ? ORDER BY id LIMIT 1", BERGEN_CITY_ID)
      id && { id: id }
    end

    def delivery_driver(app)
      id = scalar(app, "SELECT id FROM takeaway_delivery_drivers ORDER BY id LIMIT 1")
      id && { id: id }
    end

    def restaurant(app)
      id = scalar(app, "SELECT id FROM takeaway_restaurants WHERE city_id = ? ORDER BY id LIMIT 1", BERGEN_CITY_ID)
      id && { id: id }
    end

    def tv_channel_row(app)
      scalar(app, "SELECT slug FROM tv_channels WHERE city_id = ? AND slug IS NOT NULL ORDER BY id LIMIT 1", BERGEN_CITY_ID)
    end

    # Tv::ChannelsController#set_channel is slug-only (params[:slug], not
    # params[:id] -- the route declares `param: :slug`).
    def tv_channel(app)
      slug = tv_channel_row(app)
      slug && { slug: slug }
    end

    def tv_channel_slug(app)
      slug = tv_channel_row(app)
      slug && { channel_slug: slug }
    end

    # Tv::Video has no city_id of its own -- it is TenantedThrough :channel
    # (see Tv::ChannelTenanted) -- so the city has to come through a join
    # rather than a column this table carries.
    def tv_video(app)
      id = scalar(app, <<~SQL, BERGEN_CITY_ID)
        SELECT tv_videos.id FROM tv_videos
        JOIN tv_channels ON tv_channels.id = tv_videos.tv_channel_id
        WHERE tv_channels.city_id = ?
        ORDER BY tv_videos.id LIMIT 1
      SQL
      id && { id: id }
    end

    # -- amber -------------------------------------------------------------

    # DemoWardrobeController#show reads Amber::DemoWardrobe.items, which is
    # `user.items.active_wardrobe` on the one demo@amberapp.art account --
    # released/donated/sold/recycled items fall out of that scope, so #show
    # 404s on one even though the row still exists.
    def amber_demo_item(app)
      id = scalar(app, <<~SQL)
        SELECT items.id FROM items
        JOIN users ON users.id = items.user_id
        WHERE users.email_address = 'demo@amberapp.art'
          AND items.lifecycle_state NOT IN ('released', 'donated', 'sold', 'recycled')
        ORDER BY items.id LIMIT 1
      SQL
      id && { id: id }
    end

    # -- bsdports ------------------------------------------------------------

    # CategoriesController#show is `find_by!(slug: params[:id])`, slug-only
    # like its brgen marketplace counterpart.
    def bsdports_category(app)
      slug = scalar(app, "SELECT slug FROM categories WHERE slug IS NOT NULL ORDER BY id LIMIT 1")
      slug && { id: slug }
    end

    def bsdports_port(app)
      id = scalar(app, "SELECT id FROM ports ORDER BY id LIMIT 1")
      id && { id: id }
    end

    # -- sqlite plumbing -----------------------------------------------------

    def db(app)
      path = DB_PATH[app]
      return nil unless path && File.file?(path)

      @conn ||= {}
      @conn[app] ||= SQLite3::Database.new(path, readonly: true)
    rescue SQLite3::Exception
      nil
    end

    def scalar(app, sql, *binds)
      db(app)&.get_first_value(sql, *binds)
    rescue SQLite3::Exception
      nil
    end
  end
end
