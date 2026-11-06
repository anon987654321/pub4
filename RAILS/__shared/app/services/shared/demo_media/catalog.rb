# frozen_string_literal: true

require "yaml"

module Shared
  module DemoMedia
    # YAML catalog of seed-key → URL/file mappings (city demo photography).
    module Catalog
      extend self

      def resolve(seed, catalog: nil)
        path = catalog_path(catalog)
        return nil unless path && File.file?(path)

        entry = load(path).dig("images", seed.to_s)
        normalize(entry, seed)
      end

      def catalog_path(catalog = nil)
        return Pathname.new(catalog) if catalog.is_a?(String) && !catalog.empty?
        return catalog if catalog.is_a?(Pathname)

        env = ENV["DEMO_MEDIA_CATALOG"].to_s
        return Pathname.new(env) unless env.empty?

        return unless defined?(Rails)

        slug = ENV["DEMO_MEDIA_CITY"].presence
        # respond_to?, not just defined?. city_record is brgen's multi-tenant
        # attribute; amber and bsdports define a Current without it, so
        # `defined?(Current)` was true there and the call raised NoMethodError --
        # `&.` guards against nil, not against the method not existing. Every
        # demo image attachment on amber failed with
        # "undefined method 'city_record' for an instance of Current", which is
        # why its wardrobe showcase rendered as empty outlined tiles.
        slug ||= Current.city_record&.slug if defined?(Current) && Current.respond_to?(:city_record)

        if slug.present?
          candidate = Rails.root.join("config/demo_media/#{slug}.yml")
          return candidate if candidate.file?
        end

        # default.yml before bergen.yml, because the last fallback in a shared
        # engine has to be nameable by an app that is not a city. amber has no
        # city_record, so every lookup there landed on a file called bergen.yml
        # inside the wardrobe app -- which either does not exist, and the catalog
        # silently becomes picsum, or exists under a name that lies about what is
        # in it.
        %w[default bergen].each do |name|
          candidate = Rails.root.join("config/demo_media/#{name}.yml")
          return candidate if candidate.file?
        end

        nil
      end

      def file_path(relative, catalog: nil)
        base = catalog_path(catalog)
        return nil unless base

        path = base.dirname.join(relative.to_s)
        path if path.file?
      end

      private

      def load(path)
        @cache ||= {}
        @cache[path.to_s] ||= YAML.safe_load_file(path, permitted_classes: [], aliases: true) || {}
      end

      def normalize(entry, seed)
        return nil if entry.nil?

        hash = entry.is_a?(String) ? { "url" => entry } : entry.transform_keys(&:to_s)
        hash["seed"] = seed.to_s
        hash
      end
    end
  end
end
