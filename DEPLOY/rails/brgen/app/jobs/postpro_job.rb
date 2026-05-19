# frozen_string_literal: true

class PostproJob < ApplicationJob
  queue_as :default

  POSTPRO = Rails.root.join("../../../../postpro.rb").expand_path.freeze
  VALID_PRESETS = %w[portrait landscape street blockbuster].freeze

  def perform(record_gid, preset, attachment_name = "image")
    record = GlobalID::Locator.locate(record_gid)
    return unless record

    attachment = record.public_send(attachment_name)
    return unless attachment.attached?
    return unless VALID_PRESETS.include?(preset.to_s)

    Dir.mktmpdir("postpro") do |dir|
      ext    = File.extname(attachment.filename.to_s).downcase.presence || ".jpg"
      input  = File.join(dir, "input#{ext}")
      output = File.join(dir, "output.jpg")

      attachment.download { |chunk| File.open(input, "ab") { |f| f.write(chunk) } }

      ok = system(
        RbConfig.ruby, POSTPRO.to_s,
        "--input", input, "--output", output, "--preset", preset.to_s,
        out: File::NULL, err: File::NULL
      )

      if ok && File.exist?(output)
        attachment.attach(
          io:           File.open(output),
          filename:     "#{File.basename(attachment.filename.to_s, ".*")}_#{preset}.jpg",
          content_type: "image/jpeg"
        )
      end
    end
  end
end
