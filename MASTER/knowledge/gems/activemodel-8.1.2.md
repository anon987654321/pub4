# frozen_string_literal: true

require "active_model"

class Person
  include ActiveModel::Attributes

  # Simple string attribute
  attribute :name, :string

  # Integer attribute with a static default
  attribute :age, :integer, default: 0

  # Date attribute with a lazy default (evaluated on each read)
  attribute :joined_at, :date do
    Date.today
  end
end
