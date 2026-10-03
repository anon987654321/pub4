# frozen_string_literal: true

class LastChanceOutfit
  def initialize(item)
    @item = item
    @user = item.user
  end

  def suggestions(limit: 3)
    compatible_items = @user.items.active_wardrobe.where.not(id: @item.id).to_a
    outfits = []

    limit.times do |index|
      outfit_items = build_candidate(compatible_items, offset: index)
      outfits << explain(outfit_items) if outfit_items.size > 1
    end

    outfits.uniq { |outfit| outfit[:item_ids].sort }
  end

  private

  def build_candidate(items, offset: 0)
    selected = [ @item ]
    needed_categories.each_with_index do |category, idx|
      candidate = items.select { |item| item.category == category }.sort_by do |item|
        [ -(item.times_worn.to_i), item.color.to_s == @item.color.to_s ? 0 : 1, item.title.to_s ]
      end.rotate(offset + idx).first
      selected << candidate if candidate
    end
    selected.compact.uniq
  end

  def needed_categories
    case @item.category
    when "Tops" then %w[Bottoms Shoes Outerwear]
    when "Bottoms" then %w[Tops Shoes Outerwear]
    when "Shoes" then %w[Tops Bottoms]
    when "Dresses" then %w[Shoes Outerwear Accessories]
    else %w[Tops Bottoms Shoes]
    end
  end

  def explain(items)
    {
      item_ids: items.map(&:id),
      titles: items.map(&:title),
      reason: "Last-chance outfit for #{@item.title}: test whether it still has a role in your real wardrobe."
    }
  end
end
