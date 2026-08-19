# frozen_string_literal: true

# How many listings each filter would leave, next to the filter itself.
#
# The index already filtered by category, condition, price and distance; what it
# could not say was how much was behind each option, so every choice was a guess
# and a dead end cost a round trip. A facet count is the difference between
# browsing and querying.
class Marketplace::ListingFacets
  # Kroner, not øre — the bands are read by people, and the listing form asks
  # for kroner too.
  PRICE_BANDS = [
    [ nil, 500 ], [ 500, 2_000 ], [ 2_000, 10_000 ], [ 10_000, nil ]
  ].freeze

  def initialize(scope, params)
    @scope = scope
    @params = params
  end

  # Each facet counts the scope with every OTHER filter applied but not its own.
  # Counting with its own filter on would answer "how many of what you are
  # already looking at", which is the number already on the page.
  def categories = counts_for(:category_id).transform_keys(&:to_i)
  # Rejecting the nil key, not Hash#compact, which drops nil *values*: condition
  # is optional on a listing, so "no condition given" is a real group here and
  # not a facet anyone can pick.
  def conditions = counts_for(:condition).reject { |condition, _count| condition.blank? }
  def price_bands = PRICE_BANDS.map { |low, high| [ [ low, high ], count_in_band(low, high) ] }.to_h

  private

  attr_reader :scope, :params

  def counts_for(column)
    filtered(except: column).group(column).count
  end

  def count_in_band(low, high)
    band = filtered(except: :price)
    band = band.where(price_cents: (low * 100)..) if low
    band = band.where(price_cents: ..(high * 100)) if high
    band.count
  end

  def filtered(except:)
    result = scope
    result = result.where(category_id: params[:category_id]) if params[:category_id].present? && except != :category_id
    result = result.where(condition: params[:condition]) if params[:condition].present? && except != :condition
    if except != :price
      result = result.where("price_cents >= ?", (params[:min_price].to_f * 100).to_i) if params[:min_price].present?
      result = result.where("price_cents <= ?", (params[:max_price].to_f * 100).to_i) if params[:max_price].present?
    end
    result
  end
end
