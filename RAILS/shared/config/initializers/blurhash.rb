# frozen_string_literal: true

# Enqueue blurhash generation when the host app defines GenerateBlurhashJob (brgen).
Rails.application.config.after_initialize do
  next unless defined?(GenerateBlurhashJob)

  ActiveStorage::Blob.class_eval do
    after_create_commit :enqueue_blurhash_generation, if: :image?

    def image?
      content_type.to_s.start_with?("image/")
    end

    private

    def enqueue_blurhash_generation
      GenerateBlurhashJob.perform_later(id)
    end
  end
end
