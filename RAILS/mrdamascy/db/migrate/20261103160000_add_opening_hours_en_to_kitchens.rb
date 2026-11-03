# frozen_string_literal: true

# The English pages showed the Norwegian hours string, because the kitchen
# held one. The English wording lives beside it on the same record.
class AddOpeningHoursEnToKitchens < ActiveRecord::Migration[8.0]
  def change
    add_column :kitchens, :opening_hours_en, :string
  end
end
