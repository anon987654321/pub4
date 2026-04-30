# encoding: utf-8

require "rest_client"
require "hashie"

Product = Struct.new(:name, :image, :url, :price, :retailer)

module AffiliateProducts

  # Must match `product_group` at Nelly's JSON

  CATEGORIES = [
    "festkjoler",
    "jakker",
    "jeans",
    "jumpsuit",
    "sko",
    "smykker",
    "sports",
    "strømper",
    "truser",
    "vesker"
  ]

  def self.fetch

    # Fetch 5 random categories

    CATEGORIES.sample(5).map do |random_category|
      Tradedoubler.fetch random_category
    end.inject(:+)
  end

  # -------------------------------------------------

  # Rubify JSON keys, ie. `fooBar` => `foo_bar`

  # http://api.rubyonrails.org/classes/ActiveSupport/Inflector.html#method-i-underscore

  def self.prettify(x)
    case x
    when Hash
      x.map { |key, value| [key.underscore, prettify(value)] }.to_h
    when Array
      x.map { |value| prettify(value) }
    else
      x
    end
  end
end

# -------------------------------------------------

class AffiliateProducts::Tradedoubler
  # KEY = Settings.tradedoubler_key
  KEY = "FE34B1309AB749F1578AEE87D9D74535513F6B54"

  # Products to fetch from API

  PSEUDO_LIMIT = 100

  # Max filtered products to display

  REAL_LIMIT = 50

  # -------------------------------------------------

  def self.fetch category
    new(category).filtered_products.take(REAL_LIMIT)
  rescue RestClient::RequestTimeout => e
    Array.new
  end

  def initialize category
    @category = category

    # API doesn't support gender or category searches, so do some filtering based on available JSON fields

    @filters = Array.new

    define_filter { |mash|
      mash.fields.any? { |field|
        field.name == "gender" && field.value.downcase == "kvinne"
      }
    }

    define_filter { |mash|
      mash.categories.any? { |category|
        category.name.underscore.include? @category
      }
    }
  end

  def define_filter(&filter)
    @filters << filter
  end

  def filtered_products
    filtered_mashes.map { |mash|
      Product.new(
        mash.deep_fetch(:name) { "ERROR: `name`" },
        mash.deep_fetch(:product_image, :url) { "ERROR: `image`" },
        mash.deep_fetch(:offers, 0, :product_url) { "ERROR: `url`" },
        mash.deep_fetch(:offers, 0, :price_history, 0, :price, :value) { "ERROR: `price`" },
        mash.deep_fetch(:offers, 0, :program_name) { "ERROR: `retailer`" }
      )
    }
  end

private
  def request

    # Get data from Tradedoubler

    # http://dev.tradedoubler.com/products/publisher/#Search_service

    response = RestClient::Request.execute(
      :method => :get,
      :url => "http://api.tradedoubler.com/1.0/products.json;q=#{ URI.encode(@category) };limit=#{ PSEUDO_LIMIT }?token=#{ KEY }",
      :timeout => 0.4
    )

    # logger.info "http://api.tradedoubler.com/1.0/products.json;q=#{ URI.encode(@category) };limit=#{ PSEUDO_LIMIT }?token=#{ KEY }"
  end

  def hashes
    AffiliateProducts.prettify(JSON.parse(request)["products"])
  end

  def mashes
    hashes.map { |hash| Hashie::Mash.new(hash) }.each do |mash|
      mash.extend Hashie::Extensions::DeepFetch
    end
  end

  def filtered_mashes
    mashes.select { |mash| mash_matches_filter? mash }
  end

  def mash_matches_filter? mash

    # `.all?` requires all filters to match, `.any?` requires only one

    @filters.all? { |filter| filter.call mash }
  end
end

