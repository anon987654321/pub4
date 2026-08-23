# frozen_string_literal: true

require "minitest/autorun"

# `includes(:image)` where :image is an attachment raises, and only when rows
# exist.
#
# has_one_attached :image does not create an association called :image. It
# creates image_attachment and image_blob, plus a with_attached_image scope.
# Passing the bare name to includes/preload/eager_load raises
# ActiveRecord::AssociationNotFoundError — but Active Record skips preloading
# entirely when the relation comes back empty, so the call is silent against an
# empty table and raises in production the moment there is something to load.
#
# NewsletterEditionBuilder#fetch_posts did exactly this. brgen composed no
# newsletter for as long as the builder existed, and because ApplicationJob then
# carried `retry_on StandardError`, each scheduled run raised it three times.
# A test suite that creates no posts cannot catch this, which is why the check
# is on the source text rather than on behaviour.
class AttachmentPreloadTest < Minitest::Test
  RAILS_ROOT = File.expand_path("..", __dir__)
  PRELOAD = /\b(?:includes|preload|eager_load)\(([^)]*)\)/

  def sources
    @sources ||= Dir[
      File.join(RAILS_ROOT, "{brgen,amber,bsdports}/app/**/*.rb"),
      File.join(RAILS_ROOT, "brgen/engines/*/app/**/*.rb"),
      File.join(RAILS_ROOT, "shared/app/**/*.rb")
    ].reject { |path| path.include?("/vendor/") }
  end

  # Every name any model in the tree attaches. Reading the declarations rather
  # than listing them keeps the check honest when a model gains an attachment.
  def attachment_names
    @attachment_names ||= sources.flat_map { |path|
      File.read(path).scan(/has_(?:one|many)_attached\s+:(\w+)/).flatten
    }.uniq
  end

  # Comments are not code, and the comment above the fixed call site names the
  # broken form on purpose. Blanking them is what MASTER's own scanners do.
  def code_only(text)
    text.lines.reject { |line| line.lstrip.start_with?("#") }.join
  end

  def offenders(text)
    code_only(text).scan(PRELOAD).flatten.flat_map do |args|
      attachment_names.select { |name| args.match?(/:#{name}\b/) && !args.include?("#{name}_attachment") }
    end
  end

  def test_no_attachment_is_preloaded_by_its_bare_name
    found = sources.flat_map do |path|
      offenders(File.read(path)).map { |name| "#{path.delete_prefix("#{RAILS_ROOT}/")}: includes(:#{name})" }
    end

    assert_empty found, "use with_attached_<name> — a bare attachment name is not an association:\n  " \
                        "#{found.join("\n  ")}"
  end

  # A source-text checker that has stopped matching reports a clean tree and
  # reads exactly like one. This drives the detector over the defect itself.
  def test_the_detector_still_finds_the_defect_it_was_written_for
    refute_empty attachment_names, "no attachments found — the declaration scan has stopped matching"
    assert_includes attachment_names, "image"

    assert_equal ["image"], offenders("Post.hot.includes(:user, :community, :image)")
    assert_empty offenders("Post.hot.includes(:user, :community).with_attached_image")
    assert_empty offenders("Post.includes(image_attachment: :blob)")
  end
end
