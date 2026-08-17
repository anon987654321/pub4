# frozen_string_literal: true

# Migrated from data/rules.yml RESCUE_ON_DEF.
Law.define(:RESCUE_ON_DEF) do
  source "Ruby Style Guide — rescue in method definitions"
  severity :info
  languages %i[ruby]
  scope :file
  detect { |text| text.match?(/^\s*def \w+.*\n\s*begin\n(?:.*\n)*?\s*rescue/m) }
  fix "Put rescue directly on the def block."
  bad <<~X
    def go
      begin
        run
      rescue Foo
      end
    end
  X
  good <<~X
    def go
      run
    rescue Foo
      nil
    end
  X
end
