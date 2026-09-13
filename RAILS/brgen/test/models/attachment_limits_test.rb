# frozen_string_literal: true

require "test_helper"

class AttachmentLimitsTest < ActiveSupport::TestCase
  FILES = Rails.root.join("test/fixtures/files")
  FakeBlob = Struct.new(:byte_size, :content_type)

  def attach(record, name, file, type)
    record.public_send(name).attach(io: File.open(FILES.join(file)), filename: file, content_type: type)
    record.valid?
    record.errors[name]
  end

  test "an image slot takes an image" do
    assert_empty attach(Post.new, :image, "tiny.png", "image/png")
  end

  test "an image slot refuses a video" do
    errors = attach(Post.new, :image, "tiny.mp4", "video/mp4")

    assert_includes errors, I18n.t("errors.messages.file_type_not_allowed")
  end

  test "a video slot takes a video and refuses an image" do
    assert_empty attach(Post.new, :video, "tiny.mp4", "video/mp4")
    assert_includes attach(Post.new, :video, "tiny.png", "image/png"), I18n.t("errors.messages.file_type_not_allowed")
  end

  # Safari's audio-only recording is an mp4 container and identifies as video.
  test "an audio slot takes an mp4 container" do
    assert_empty attach(Post.new, :audio, "tiny.mp4", "video/mp4")
  end

  test "a mixed slot holds size alone" do
    assert_empty attach(Message.new, :attachment, "tiny.png", "image/png")
  end

  test "an oversized upload is refused with its limit" do
    post = Post.new
    limits = Shared::AttachmentLimits::KINDS.fetch(:image)
    post.send(:attachment_limit_errors, :image, FakeBlob.new(limits[:max_bytes] + 1, "image/png"), limits)

    assert_includes post.errors[:image], I18n.t("errors.messages.file_too_large", count: limits[:max_bytes] / 1.megabyte)
  end

  test "svg is not an image here" do
    post = Post.new
    post.send(:attachment_limit_errors, :image, FakeBlob.new(10, "image/svg+xml"), Shared::AttachmentLimits::KINDS.fetch(:image))

    assert_includes post.errors[:image], I18n.t("errors.messages.file_type_not_allowed")
  end

  test "names choose the kind" do
    assert_equal :audio, Shared::AttachmentLimits.kind_for(:audio_file)
    assert_equal :mixed, Shared::AttachmentLimits.kind_for(:attachment)
    assert_equal :image, Shared::AttachmentLimits.kind_for(:photos)
  end
end
