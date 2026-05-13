# frozen_string_literal: true
require "yaml"
require "ostruct"
module Master
  module Judge
    module Scan
      module RuleLoader
        def self.load_definitions
          rules = []
          Dir.glob(File.join(Master::ROOT, "data/rules/universal/**/*.yml")).each do |path|
            data = YAML.load_file(path)
            rules << OpenStruct.new(
              id: data["id"], name: data["name"], description: data["description"],
              principle: data["principle"], severity: data["severity"], mode: data["mode"] || "violation",
              auto_fix: data["auto_fix"] || false, adapters: data["adapters"] || []
            )
          end
          rules
        end

        def self.load_profiles
          YAML.load_file(File.join(Master::ROOT, "data/rules/profiles.yml")) || {}
        end

        def self.load_for_profile(profile_name)
          profiles = load_profiles
          expand_profile(profiles, profile_name.to_s)
        end

        def self.expand_profile(profiles, name)
          list = profiles[name]
          return [] unless list
          list.flat_map do |item|
            if profiles[item]
              expand_profile(profiles, item)
            else
              [item]
            end
          end.uniq
        end
      end
    end
  end
end
