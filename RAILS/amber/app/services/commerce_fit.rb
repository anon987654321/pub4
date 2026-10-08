# frozen_string_literal: true

module CommerceFit
  Result = Data.define(:score, :reasons, :duplicate_risk)

  module_function

  def score(item, product)
    result = evaluate(item, product)
    result.score
  end

  def evaluate(item, product)
    item_category = item.category.to_s.downcase
    product_category = product.category.to_s.downcase
    item_brand = item.brand.to_s.downcase
    product_title = product.title.to_s.downcase
    item_text = [ item.title, item.brand, item.category, item.color, item.material ].compact.join(" ").downcase
    product_words = product_title.scan(/[[:alnum:]]+/).reject { |word| word.length < 3 }.uniq

    category = item_category.present? && product_category.present? && item_category == product_category ? 0.35 : 0.0
    brand = item_brand.present? && product_title.include?(item_brand) ? 0.20 : 0.0
    overlap = product_words.empty? ? 0.0 : product_words.count { |word| item_text.include?(word) }.to_f / product_words.length
    title = overlap * 0.25

    duplicate_risk = same_product_shape?(item, product, overlap)
    duplicate_penalty = duplicate_risk ? 0.25 : 0.0

    raw = (category + brand + title + 0.20 - duplicate_penalty).clamp(0.0, 1.0)
    reasons = []
    reasons << I18n.t("commerce_fit.category", default: "Matches this wardrobe category.") if category.positive?
    reasons << I18n.t("commerce_fit.brand", default: "Matches your brand signal.") if brand.positive?
    reasons << I18n.t("commerce_fit.words", default: "Matches the item's description and material signals.") if title >= 0.10
    reasons << I18n.t("commerce_fit.duplicate", default: "Possible duplicate of something already in your wardrobe.") if duplicate_risk
    reasons << I18n.t("commerce_fit.local", default: "Sold through BRGEN's local marketplace.") if product.metadata["source"] == "brgen"

    Result.new(Shared::Commerce.score(raw), reasons.first(3), duplicate_risk)
  end

  def same_product_shape?(item, product, overlap)
    item.category.to_s.casecmp?(product.category.to_s) && overlap >= 0.65
  end
end
