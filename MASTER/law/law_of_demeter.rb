# frozen_string_literal: true

# Migrated from data/rules.yml LAW_OF_DEMETER. Folds MESSAGE_CHAIN (identical detector).
Law.define(:LAW_OF_DEMETER) do
  source "Law of Demeter (Ian Holland, Northeastern, 1987)"
  severity :warn
  detect { |line| line.match?(/\w+\.\w+\.\w+\.\w+/) }
  fix "Add delegate method. Talk only to direct collaborators."
  bad  "order.customer.address.city"
  good "order.shipping_city"
end
