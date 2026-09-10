# frozen_string_literal: true

require "yaml"

module Brgen
  # Realistic Bergen / r/bergen-inspired demo content for brgen.no (TradeDoubler, demos).
  # Norwegian copy, local handles, staggered timestamps, optional picsum + postpro attachments.
  class BergenDemoSeeder
    include BergenDemoData

    def initialize(city, attach_media: !DemoMedia.skip_attach?)
      @city = city
      @attach_media = attach_media
      @users_by_username = {}
    end

    def seed!
      ActsAsTenant.with_tenant(@city) do
        neighborhoods = ensure_neighborhoods
        communities = ensure_communities
        seed_users
        seed_posts(communities)
        seed_listings
        seed_live_posts
        seed_playlists
        seed_dating
        seed_dating_likes
        seed_places(neighborhoods)
        seed_takeaway
        seed_tv
      end
    end

    private

    def ensure_neighborhoods
      NEIGHBORHOODS.index_with do |name, slug|
        Neighborhood.find_or_create_by!(city: @city, slug: slug) { |row| row.name = name }
      end
    end

    def ensure_communities
      # Admin may pre-exist outside this tenant scope (username "admin" vs "admin_<slug>").
      admin = ActsAsTenant.without_tenant do
        User.strict_loading(false).find_by(email_address: "admin@#{@city.domain}") ||
          User.strict_loading(false).find_by(username: "admin_#{@city.slug}") ||
          User.strict_loading(false).find_by(username: "admin", city_id: @city.id) ||
          User.strict_loading(false).find_by(username: "admin") ||
          User.strict_loading(false).create!(
            email_address: "admin@#{@city.domain}",
            username: "admin_#{@city.slug}",
            password: "password123",
            password_confirmation: "password123",
            city: @city
          )
      end

      Brgen::CityContent.community_slugs_for(@city.country_code).index_with do |slug|
        Community.find_or_create_by!(slug: slug, city: @city) do |community|
          community.name = slug.capitalize
          community.description = "#{@city.name} — #{slug}"
          community.user = admin
        end
      end
    end

    def seed_users
      USERS.each do |_first_name, username|
        @users_by_username[username] = User.strict_loading(false).find_or_create_by!(
          email_address: "#{username}@#{@city.domain}"
        ) do |user|
          user.username = username
          user.password = user.password_confirmation = "password123"
          user.city = @city
          user.latitude = @city.latitude.to_f + rand(-0.04..0.04)
          user.longitude = @city.longitude.to_f + rand(-0.04..0.04)
        end
      end
    end

    def seed_posts(communities)
      POSTS.each do |row|
        next if Post.exists?(city: @city, title: row[:title])

        user = @users_by_username.fetch(row[:user])
        community = communities.fetch(row[:community])

        post = Post.create!(
          user: user,
          city: @city,
          community: community,
          title: row[:title],
          content: row[:content],
          anonymous: row[:anonymous] == true,
          created_at: row[:hours_ago].hours.ago + rand(0..45).minutes
        )
        post.record_activity!("BergenDemoSeed") if post.respond_to?(:record_activity!)

        if @attach_media && row[:image]
          DemoMedia.attach_remote_postpro!(post, :image, seed: row[:image], preset: "landscape")
        end

        seed_comments!(post, row[:comments])

        voters = @users_by_username.values.shuffle
        vote_target = row[:votes].to_i.positive? ? row[:votes].to_i : rand(2..5)
        vote_target.times do |index|
          voter = voters[index % voters.size]
          post.reactions.find_or_create_by!(user: voter, kind: %w[like love].sample)
          post.votes.find_or_create_by!(user: voter) { |vote| vote.value = 1 }
        end
      end
    end

    def seed_listings
      category = Marketplace::Category.first || Marketplace::Category.create!(name: "Diverse", slug: "diverse-bergen")
      base_lat = @city.latitude.to_f
      base_lng = @city.longitude.to_f
      base_lat = 60.3913 if base_lat.zero?
      base_lng = 5.3221 if base_lng.zero?

      LISTINGS.each do |row|
        next if Marketplace::Listing.exists?(title: row[:title])

        user = @users_by_username.fetch(row[:user])
        listing = Marketplace::Listing.create!(
          user: user,
          title: row[:title],
          description: "Hentes i #{@city.name}. PM for detaljer. (Guest kan sende bud uten konto.)",
          price_cents: row[:price_cents],
          category: category,
          location: @city.name,
          latitude: base_lat + rand(-0.03..0.03),
          longitude: base_lng + rand(-0.04..0.04),
          status: "active",
          created_at: rand(2..21).days.ago
        )
        if @attach_media
          DemoMedia.attach_remote_postpro!(listing, :photos, seed: row[:image], preset: "portrait")
        end
      end
    end

    def seed_live_posts
      base_lat = @city.latitude.to_f
      base_lng = @city.longitude.to_f
      base_lat = 60.3913 if base_lat.zero?
      base_lng = 5.3221 if base_lng.zero?
      users = @users_by_username.values
      return if users.empty?

      LIVE_NOTES.each_with_index do |row, i|
        # Idempotent: one Live note per body prefix in city
        next if Post.live.where(city: @city).where("content LIKE ?", "#{row[:body][0, 40]}%").exists?

        user = users[i % users.size]
        body = row[:body]
        post = Post.new(
          user: user,
          city: @city,
          content: body,
          title: body.truncate(80),
          created_at: row[:hours_ago].hours.ago + rand(0..20).minutes
        )
        post.stamp_live_location!(
          lat: base_lat + rand(-0.02..0.02),
          lng: base_lng + rand(-0.03..0.03)
        )
        post.save!
        post.record_activity!("BergenLiveSeed") if post.respond_to?(:record_activity!)

        # A few upvotes so Hot tab isn't empty
        users.sample([ 2, users.size ].min).each do |voter|
          post.votes.find_or_create_by!(user: voter) { |vote| vote.value = 1 }
        end
      end
    end

    def seed_playlists
      owner = @users_by_username.fetch("live_bergenlive")
      playlist = Playlist::Playlist.find_or_initialize_by(city: @city, name: RADIO_BERGEN_PLAYLIST, user: owner)
      playlist.assign_attributes(
        description: "AKMD-lokallåter og beat-referanser fra Radio Bergen-manifestet. Nattbuss, tunnel og regnby.",
        public_access: true,
        collaborative: false,
        plays_count: playlist.plays_count.to_i.positive? ? playlist.plays_count : 428
      )
      playlist.save!

      return if playlist.tracks.count >= radio_bergen_manifest_tracks.size

      radio_bergen_manifest_tracks.each do |row|
        track = find_or_create_radio_track!(row, owner: owner)
        playlist.add_track!(track, user: owner)
      end
      playlist.update_column(:tracks_count, playlist.tracks.count) if playlist.tracks_count != playlist.tracks.count
    end

    def seed_dating
      DATING_BIOS.each do |row|
        user = @users_by_username.fetch(row[:user])
        profile = Dating::Profile.strict_loading(false).find_or_initialize_by(user: user)
        profile.assign_attributes(
          bio: row[:bio],
          age: row[:age],
          gender: row[:gender],
          looking_for: row[:looking_for],
          latitude: user.latitude,
          longitude: user.longitude,
          bydel: row[:bydel],
          visible: false
        )
        if @attach_media && !profile.photos.attached?
          DemoMedia.attach_remote_postpro!(profile, :photos, seed: row[:image], preset: "portrait", width: 600, height: 900)
        end
        profile.visible = profile.photos.attached?
        profile.save!
      end
    end

    def seed_comments!(post, bodies)
      rows = Array(bodies).each_with_index.filter_map do |body, index|
        commenter = @users_by_username.values.sample
        created_at = post.created_at + (index + 1).minutes + rand(10..90).seconds
        {
          user_id: commenter.id,
          commentable_type: post.class.name,
          commentable_id: post.id,
          content: body,
          created_at: created_at,
          updated_at: created_at
        }
      end
      Comment.insert_all(rows) if rows.any?
      post.touch
    end

    def seed_dating_likes
      DATING_MUTUAL_PAIRS.each do |a_name, b_name|
        a = @users_by_username.fetch(a_name)
        b = @users_by_username.fetch(b_name)
        Dating::Like.find_or_create_by!(liker: a, likee: b)
        Dating::Like.find_or_create_by!(liker: b, likee: a)
      end

      DATING_ONE_WAY_LIKES.each do |liker_name, likee_name|
        Dating::Like.find_or_create_by!(
          liker: @users_by_username.fetch(liker_name),
          likee: @users_by_username.fetch(likee_name)
        )
      end
    end

    def radio_bergen_manifest_tracks
      @radio_bergen_manifest_tracks ||= begin
        manifest = load_radio_bergen_manifest
        local = Array(manifest["local_mp3"]).map do |row|
          {
            artist: row["artist"],
            title: row["title"],
            source_type: "direct",
            source_url: "#{LOCAL_AUDIO_BASE}#{row['src']}"
          }
        end
        youtube = Array(manifest.dig("external_reference", "youtube")).map do |row|
          {
            artist: row["artist"],
            title: row["title"],
            source_type: "youtube",
            source_url: "https://www.youtube.com/watch?v=#{row['id']}"
          }
        end
        local + youtube
      end
    end

    def load_radio_bergen_manifest
      RadioBergenManifest.load
    end

    def find_or_create_radio_track!(row, owner:)
      Playlist::Track.find_or_create_by!(
        title: row[:title],
        artist: row[:artist],
        source_type: row[:source_type],
        source_url: row[:source_url]
      ) do |track|
        track.user = owner if track.has_attribute?(:user_id)
        track.privacy = "public"
        track.duration_seconds = rand(150..320)
        track.genre = row[:source_type] == "direct" ? "bergen" : "beats"
      end
    end

    def seed_places(neighborhoods)
      return unless defined?(Place) && Place.table_exists?

      PLACES.each do |row|
        next if Place.exists?(city: @city, slug: row[:slug])

        place = Place.create!(
          city: @city,
          neighborhood: neighborhoods[row[:neighborhood]],
          name: row[:name],
          slug: row[:slug],
          kind: row[:kind],
          address: row[:address],
          latitude: row[:latitude],
          longitude: row[:longitude]
        )
        next unless @attach_media && row[:image]

        DemoMedia.attach_remote_postpro!(place, :photo, seed: row[:image], preset: "landscape")
      end
    end

    def seed_takeaway
      RESTAURANTS.each do |row|
        next if Takeaway::Restaurant.exists?(name: row[:name])

        user = @users_by_username.fetch(row[:user])
        restaurant = Takeaway::Restaurant.create!(
          user: user,
          name: row[:name],
          cuisine_type: row[:cuisine_type],
          address: row[:address],
          active: true,
          delivery_fee_cents: row[:delivery_fee_cents],
          min_order_cents: row[:min_order_cents],
          latitude: row[:latitude],
          longitude: row[:longitude],
          rating: row[:rating]
        )
        restaurant.update_column(:city, @city.name) if restaurant.has_attribute?(:city)

        Array(row[:menu]).each do |item_row|
          menu_item = Takeaway::MenuItem.create!(
            restaurant: restaurant,
            name: item_row[:name],
            description: item_row[:description],
            price_cents: item_row[:price_cents],
            available: true
          )
          next unless @attach_media && item_row[:image]

          DemoMedia.attach_remote_postpro!(menu_item, :photo, seed: item_row[:image], preset: "portrait", width: 720, height: 540)
        end
      end
    end

    def seed_tv
      TV_CHANNELS.each do |row|
        user = @users_by_username.fetch(row[:user])
        channel = Tv::Channel.find_or_initialize_by(slug: row[:slug])
        channel.assign_attributes(
          user: user,
          name: row[:name],
          description: row[:description],
          subscribers_count: channel.subscribers_count.to_i.positive? ? channel.subscribers_count : rand(120..2400)
        )
        channel.save!

        if @attach_media
          DemoMedia.attach_remote_postpro!(channel, :avatar, seed: row[:avatar], preset: "portrait", width: 480, height: 480) unless channel.avatar.attached?
          DemoMedia.attach_remote_postpro!(channel, :banner, seed: row[:banner], preset: "landscape", width: 1280, height: 480) unless channel.banner.attached?
        end

        Array(row[:videos]).each do |video_row|
          next if channel.videos.exists?(title: video_row[:title])

          video = Tv::Video.create!(
            user: user,
            channel: channel,
            title: video_row[:title],
            description: "Demo fra #{@city.name}.",
            status: "published",
            duration_seconds: video_row[:duration_seconds],
            views_count: video_row[:views_count],
            published_at: rand(2..45).days.ago
          )
          next unless @attach_media && video_row[:thumbnail]

          DemoMedia.attach_remote_postpro!(video, :thumbnail, seed: video_row[:thumbnail], preset: "landscape", width: 1280, height: 720)
        end
      end
    end
  end
end
