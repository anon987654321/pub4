# frozen_string_literal: true

# Shared schema.org JSON-LD helper.
# Implements SEO / structured data requirements from apps.yml and ruby_style.
#
# Usage in controllers or views:
#   content_for :json_ld, json_ld_for(@post, type: :article)
#   # or
#   <%= json_ld_for(@restaurant, type: :local_business) %>
#
# Supports common Brgen vertical entities: Post, Profile/User, Listing, Restaurant,
# Video, Event, Recipe (food), Product (marketplace), MusicPlaylist (playlist).

module SchemaHelper
  include Shared::SeoKit

  def json_ld_for(resource, type: nil)
    data = build_schema(resource, type)
    return "" if data.blank?

    content_tag :script, data.to_json.html_safe,
                type: "application/ld+json",
                data: { turbo_permanent: true }
  end

  # ItemList for category / search result pages (marketplace index, etc.)
  def item_list_schema(items, title: nil)
    {
      "@context" => "https://schema.org",
      "@type" => "ItemList",
      "name" => title,
      "numberOfItems" => items.size,
      "itemListElement" => items.map.with_index(1) do |item, index|
        {
          "@type" => "ListItem",
          "position" => index,
          "item" => {
            "@type" => "Product",
            "name" => item.try(:title) || item.try(:name),
            "url" => schema_url_for(item),
          },
        }
      end,
    }.compact
  end

  # Absolute, not the path url_for returns by default in a view. A relative
  # "url" in JSON-LD is resolved against the page it appears on, which makes
  # the same resource carry a different identity on every page that lists it —
  # the one field consumers use to deduplicate.
  # Prefer record_public_href so brgen verticals keep their subdomain host
  # (markedsplass.brgen.no, tv.brgen.no). polymorphic_url is the amber/bsdports
  # fallback. A leftover path is then joined to request.base_url.
  def schema_url_for(resource)
    href = record_public_href(resource) if respond_to?(:record_public_href)
    if href.blank?
      href = begin
        polymorphic_url(resource)
      rescue StandardError
        nil
      end
    end
    return if href.blank?
    return href if href.start_with?("http://", "https://")
    return "#{request.base_url}#{href}" if href.start_with?("/") && respond_to?(:request)

    href
  end

  # Absolute URL for a share card or JSON-LD image. Isolated engines do not
  # own ActiveStorage routes, so go through main_app when it is there.
  def seo_image_url(attachment)
    return if attachment.blank?
    return if attachment.respond_to?(:attached?) && !attachment.attached?

    blob = attachment.try(:blob) || attachment
    if respond_to?(:main_app) && main_app.respond_to?(:rails_blob_url)
      main_app.rails_blob_url(blob, only_path: false)
    else
      rails_blob_url(blob, only_path: false)
    end
  rescue StandardError
    nil
  end

  private

  def build_schema(resource, explicit_type)
    return nil unless resource.present?

    case (explicit_type || infer_type(resource)).to_s
    when "article", "post"
      article_schema(resource)
    when "person", "profile", "user"
      person_schema(resource)
    when "local_business", "restaurant"
      local_business_schema(resource)
    when "product", "listing"
      product_schema(resource)
    when "video", "video_object"
      video_schema(resource)
    when "music_playlist", "playlist"
      music_playlist_schema(resource)
    when "recipe"
      recipe_schema(resource)
    else
      generic_schema(resource)
    end
  end

  def infer_type(resource)
    case resource.class.name
    when /Post/, /Article/ then :article
    when /User/, /Profile/ then :person
    when /Restaurant/, /Takeaway/ then :local_business
    when /Listing/, /Marketplace/ then :product
    when /Playlist/ then :music_playlist
    when /Video/, /Tv::/ then :video_object
    when /Recipe/, /Food/ then :recipe
    else :thing
    end
  end

  def article_schema(post)
    body = post.try(:content) || post.try(:body)
    {
      "@context" => "https://schema.org",
      "@type" => "Article",
      "headline" => post.try(:title) || body&.truncate(80),
      "author" => person_snippet(post.try(:user) || Current.user),
      "datePublished" => post.created_at&.iso8601,
      "dateModified" => post.updated_at&.iso8601,
      "description" => meta_description_for(post),
      "url" => schema_url_for(post),
      "image" => seo_image_url(post.try(:image)),
      "wordCount" => body.to_s.split.size,
      "inLanguage" => I18n.locale.to_s,
    }.compact
  end

  def person_schema(user)
    {
      "@context" => "https://schema.org",
      "@type" => "Person",
      "name" => user.try(:name) || user.try(:username) || "User",
      "url" => schema_url_for(user),
      "image" => user.try(:avatar_url),
    }.compact
  end

  def local_business_schema(place)
    {
      "@context" => "https://schema.org",
      "@type" => "LocalBusiness",
      "name" => place.try(:name) || place.try(:title),
      "address" => place.try(:address),
      "geo" => geo_snippet(place),
      "url" => schema_url_for(place),
      "image" => seo_image_url(place.try(:photo) || place.try(:image)),
    }.compact
  end

  def product_schema(listing)
    price = listing.try(:price_cents).to_i / 100.0 if listing.try(:price_cents).to_i > 0

    data = {
      "@context" => "https://schema.org",
      "@type" => "Product",
      "name" => listing.try(:title),
      "description" => listing.try(:description)&.truncate(300),
      "url" => schema_url_for(listing),
      "sku" => listing.try(:id)&.to_s,
      # try(:name), not &.name: only brgen's User responds to #name. amber's
      # does not, so &.name raised NoMethodError and took out every
      # amber /items/:id render via json_ld_for(@item, type: :product).
      # Every other branch in this helper already uses try(:name).
      "brand" => { "@type" => "Brand", "name" => listing.try(:user).try(:name) || "Local Seller" },
      "offers" => {
        "@type" => "Offer",
        "price" => price,
        "priceCurrency" => listing.try(:currency) || "NOK",
        # try(:sold?), not sold?: this branch was written for brgen's
        # Marketplace::Listing but amber renders its Item through it, and Item
        # has no #sold?. nil is falsy, so unknown reads as InStock.
        "availability" => listing.try(:sold?) ? "https://schema.org/OutOfStock" : "https://schema.org/InStock",
        "url" => schema_url_for(listing),
      }.compact,
    }

    if listing.respond_to?(:photos) && listing.photos.attached?
      data["image"] = schema_photo_url_for(listing.photos.first)
    end

    data.compact
  end

  def video_schema(video)
    {
      "@context" => "https://schema.org",
      "@type" => "VideoObject",
      "name" => video.try(:title),
      "description" => video.try(:description)&.truncate(200),
      "uploadDate" => video.created_at&.iso8601,
      "url" => schema_url_for(video),
      "thumbnailUrl" => seo_image_url(video.try(:thumbnail)),
      "duration" => iso8601_duration(video.try(:duration_seconds).to_i),
    }.compact
  end

  def music_playlist_schema(playlist)
    tracks = playlist.respond_to?(:tracks) ? playlist.tracks.unexpired.limit(50) : []
    {
      "@context" => "https://schema.org",
      "@type" => "MusicPlaylist",
      "name" => playlist.try(:name),
      "description" => playlist.try(:description)&.truncate(300),
      "numTracks" => playlist.try(:tracks_count),
      "duration" => iso8601_duration(playlist.try(:duration_seconds).to_i),
      "creator" => person_snippet(playlist.try(:user)),
      "url" => schema_url_for(playlist),
      "track" => tracks.map do |track|
        {
          "@type" => "MusicRecording",
          "name" => track.title,
          "byArtist" => { "@type" => "MusicGroup", "name" => track.artist.presence || "Unknown artist" },
          "duration" => iso8601_duration(track.duration_seconds.to_i),
        }.compact
      end,
    }.compact
  end

  def recipe_schema(recipe)
    {
      "@context" => "https://schema.org",
      "@type" => "Recipe",
      "name" => recipe.try(:title),
      "description" => recipe.try(:description)&.truncate(200),
    }.compact
  end

  def generic_schema(resource)
    {
      "@context" => "https://schema.org",
      "@type" => "Thing",
      "name" => resource.try(:title) || resource.try(:name) || resource.to_s,
      "url" => schema_url_for(resource),
    }.compact
  end

  def person_snippet(user)
    return nil unless user
    { "@type" => "Person", "name" => user.try(:name) || user.try(:username) }
  end

  def geo_snippet(place)
    return nil unless place.respond_to?(:latitude) && place.latitude.present?
    {
      "@type" => "GeoCoordinates",
      "latitude" => place.latitude,
      "longitude" => place.longitude,
    }
  end

  def schema_photo_url_for(photo)
    seo_image_url(photo)
  end

  def iso8601_duration(seconds)
    return nil if seconds.to_i <= 0

    minutes, secs = seconds.to_i.divmod(60)
    hours, minutes = minutes.divmod(60)
    "PT#{hours}H#{minutes}M#{secs}S"
  end
end
