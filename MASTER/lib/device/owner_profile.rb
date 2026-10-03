# frozen_string_literal: true

require "fileutils"

module Master
  module Device
    module OwnerProfile
      extend Master::Io::AtomicWrite
      KEYS = %w[name pet_name language locale timezone communication_style interests].freeze
      LABELS = {
        "name" => "Name",
        "pet_name" => "MASTER pet name",
        "language" => "Language",
        "locale" => "Locale",
        "timezone" => "Timezone",
        "communication_style" => "Communication style",
        "interests" => "Interests",
      }.freeze
      module_function

      def path(root:, subject:)
        File.join(Master::Ground::PersonalWorkspace.dir_for(subject, root:), "USER.md")
      end

      def values(root:, subject:)
        ensure!(root:, subject:)
        File.read(path(root:, subject:), encoding: "UTF-8").each_line.filter_map do |line|
          match = line.match(/\A-\s+([^:]+):\s*(.*?)\s*\z/)
          next unless match
          key = LABELS.key(match[1].strip)
          key && !match[2].empty? ? [key, match[2]] : nil
        end.to_h
      end

      def set(root:, subject:, **fields)
        ensure!(root:, subject:)
        updates = fields.transform_keys(&:to_s).slice(*KEYS).transform_values { |value| value.to_s.strip }.reject { |_k, v| v.empty? }
        return values(root:, subject:) if updates.empty?

        rows = File.read(path(root:, subject:), encoding: "UTF-8").lines
        labels = LABELS.values.map { |label| Regexp.escape(label) }.join("|")
        rows.reject! { |line| line.match?(/\A-\s+(?:#{labels}):/) }
        profile = KEYS.filter_map do |key|
          value = updates.fetch(key, nil) || values(root:, subject:)[key]
          value && !value.empty? ? "- #{LABELS.fetch(key)}: #{value}\n" : nil
        end
        body = rows.join
        body += "\n## Profile\n" unless body.match?(/^## Profile\s*$/)
        body = body.sub(/\n?\z/, "\n") + profile.join
        write_atomic(path(root:, subject:), body)
        values(root:, subject:)
      end

      def forget(root:, subject:, key:)
        key = key.to_s
        raise ArgumentError, "unknown owner field: #{key}" unless KEYS.include?(key)

        set(root:, subject:, **{ key => "" })
        rows = File.read(path(root:, subject:), encoding: "UTF-8").lines
        rows.reject! { |line| line.match?(/\A-\s+#{Regexp.escape(LABELS.fetch(key))}:/) }
        write_atomic(path(root:, subject:), rows.join)
        values(root:, subject:)
      end

      GREETINGS = [
        "Oh! #{'%s'} heard you. Tiny ears, giant agenda.",
        "There you are. #{'%s'} is awake.",
        "Boop. #{'%s'} online and behaving suspiciously well.",
        "Hey! #{'%s'} reporting for mischief.",
      ].freeze

      def wake_greeting(root:, subject:)
        profile = values(root:, subject:)
        pet = profile["pet_name"].to_s.strip
        name = pet.empty? ? "MASTER" : pet
        GREETINGS.fetch(Time.now.to_i % GREETINGS.length) % name
      end

      def onboarding_prompt(root:, subject:)
        profile = values(root:, subject:)
        missing = KEYS.select { |key| !profile.key?(key) }
        return "owner0: profile complete" if missing.empty?

        labels = missing.first(3).map { |key| LABELS.fetch(key) }
        "owner0: tell me any of these you want me to remember: #{labels.join(", ")}. "           "You can skip any item. Give me a pet name too, if you want a more personal feel."
      end

      def ensure!(root:, subject:)
        Ground::PersonalWorkspace.ensure!(root:, subject:)
      end
      private_class_method :ensure!
    end
  end
end
