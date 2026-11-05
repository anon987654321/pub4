# frozen_string_literal: true

module Marketplace
  # Money typed in kroner, stored in øre. A form asked sellers for 25000 to mean
  # NOK 250, and one missing zero listed a bike at a tenth of its price.
  # `kroner_field :price_cents` adds price_kroner, which reads the stored value
  # back as "250" or "250,50" and takes "250", "250,50", "250.50" or "1 250".
  # Anything else is a validation error on the kroner field, not a silent nil.
  module KronerFields
    extend ActiveSupport::Concern

    AMOUNT = /\A(\d+)(?:[.,](\d{1,2}))?\z/

    # The øre for a typed amount, nil when blank, :invalid when unreadable.
    def self.parse(text)
      cleaned = text.to_s.gsub(/[[:space:]]|kr|nok/i, "")
      return nil if cleaned.empty?

      match = AMOUNT.match(cleaned) or return :invalid
      (match[1].to_i * 100) + match[2].to_s.ljust(2, "0").to_i
    end

    def self.format(ore)
      return nil if ore.nil?

      whole, part = ore.to_i.divmod(100)
      part.zero? ? whole.to_s : "#{whole}#{I18n.locale == :en ? '.' : ','}#{part.to_s.rjust(2, '0')}"
    end

    class_methods do
      # blank: what an empty field stores; 0 for a column that is never null.
      def kroner_field(cents_attribute, blank: nil)
        name = "#{cents_attribute.to_s.delete_suffix('_cents')}_kroner"
        typed = "@#{name}_typed"

        define_method(name) do
          instance_variable_defined?(typed) ? instance_variable_get(typed) : KronerFields.format(self[cents_attribute])
        end

        define_method("#{name}=") do |text|
          instance_variable_set(typed, text)
          ore = KronerFields.parse(text)
          self[cents_attribute] = ore == :invalid ? blank : (ore || blank)
        end

        validate do
          next unless instance_variable_defined?(typed)

          errors.add(name, :invalid_amount) if KronerFields.parse(instance_variable_get(typed)) == :invalid
        end
      end
    end
  end
end
