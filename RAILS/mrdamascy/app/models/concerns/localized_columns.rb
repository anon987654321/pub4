# frozen_string_literal: true

# Menu rows carry an English mirror of their copy (name_en, description_en).
# localized(:name) reads the mirror under ?locale=en when it is filled and
# the Norwegian column otherwise, so a row without a translation still
# reads.
module LocalizedColumns
  def localized(attribute)
    (I18n.locale == :en && self["#{attribute}_en"].presence) || self[attribute]
  end
end
