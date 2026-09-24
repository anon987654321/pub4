# frozen_string_literal: true

require "time"

module Master
  module Plugin
    class Base
      attr_reader :manifest

      def initialize(manifest:)
        @manifest = manifest
      end

      def call(action:, **)
        raise NotImplementedError, "#{manifest.id}: #{action} is not implemented"
      end

      private

      def law_admission!
        Master::Ground::LawHandshake::Admission.require!
      end

      def policy
        Master::Plugin.policy(manifest.id)
      end

      def require_policy!(key, expected: true)
        actual = policy.fetch(key.to_s)
        return true if actual == expected

        raise PolicyError, "#{manifest.id}: policy #{key}=#{actual.inspect} does not admit #{expected.inspect}"
      end

      def require_consent!(value)
        return true if value == true

        raise PolicyError, "#{manifest.id}: explicit consent is required for an external write"
      end
    end
  end
end
