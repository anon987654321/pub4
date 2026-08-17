# frozen_string_literal: true

# Migrated from data/rules.yml KERNEL_COERCION.
Law.define(:KERNEL_COERCION) do
  source "Ruby Style Guide — Integer()/Float() over to_i/to_f"
  severity :info
  languages %i[ruby]
  detect { |line| line.match?(/(\w+)\s*\.\s*nil\?\s*\?\s*\[\]\s*:\s*\1|(\w+)\s*\|\|\s*\[\]/) }
  fix "Use Array(x) instead of x.nil? ? [] : x"
  bad  "list.nil? ? [] : list"
  good "Array(list)"
end
