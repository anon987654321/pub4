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
# Video, Event, Recipe (food), Product (marketplace).

module SchemaHelper
  def json_ld_for(resource, type: nil)
    data = build_schema(resource, type)
    return "" if data.blank?

    content_tag :script, data.to_json.html_safe,
                type: "application/ld+json",
                data: { turbo_permanent: true }
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
    when /Video/, /Tv::/ then :video_object
    when /Recipe/, /Food/ then :recipe
    else :thing
    end
  end

  def article_schema(post)
    {
      "@context" => "https://schema.org",
      "@type" => "Article",
      "headline" => post.try(:title) || post.try(:body)&.truncate(80),
      "author" => person_snippet(post.try(:user) || Current.user),
      "datePublished" => post.created_at&.iso8601,
      "dateModified" => post.updated_at&.iso8601,
      "description" => post.try(:body)&.truncate(200),
      "url" => url_for(post) rescue nil
    }.compact
  end

  def person_schema(user)
    {
      "@context" => "https://schema.org",
      "@type" => "Person",
      "name" => user.try(:name) || user.try(:username) || "User",
      "url" => url_for(user) rescue nil,
      "image" => user.try(:avatar_url)
    }.compact
  end

  def local_business_schema(place)
    {
      "@context" => "https://schema.org",
      "@type" => "LocalBusiness",
      "name" => place.try(:name) || place.try(:title),
      "address" => place.try(:address),
      "geo" => geo_snippet(place),
      "url" => url_for(place) rescue nil
    }.compact
  end

  def product_schema(listing)
    {
      "@context" => "https://schema.org",
      "@type" => "Product",
      "name" => listing.try(:title),
      "description" => listing.try(:description)&.truncate(200),
      "url" => url_for(listing) rescue nil,
      "offers" => {
        "@type" => "Offer",
        "price" => listing.try(:price),
        "priceCurrency" => "NOK" # or from Current.currency
      }.compact
    }.compact
  end

  def video_schema(video)
    {
      "@context" => "https://schema.org",
      "@type" => "VideoObject",
      "name" => video.try(:title),
      "description" => video.try(:description)&.truncate(200),
      "uploadDate" => video.created_at&.iso8601,
      "url" => url_for(video) rescue nil
    }.compact
  end

  def recipe_schema(recipe)
    {
      "@context" => "https://schema.org",
      "@type" => "Recipe",
      "name" => recipe.try(:title),
      "description" => recipe.try(:description)&.truncate(200)
    }.compact
  end

  def generic_schema(resource)
    {
      "@context" => "https://schema.org",
      "@type" => "Thing",
      "name" => resource.try(:title) || resource.try(:name) || resource.to_s,
      "url" => url_for(resource) rescue nil
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
      "longitude" => place.longitude
    }
  end
end
