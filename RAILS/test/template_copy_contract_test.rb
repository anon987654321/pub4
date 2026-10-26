# frozen_string_literal: true

require "minitest/autorun"

class TemplateCopyContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def read(relative)
    File.read(File.join(ROOT, relative))
  end

  def test_share_draft_copy_comes_from_both_locale_files
    view = read("brgen/app/views/share_drafts/show.html.erb")
    %w[share_draft_lead shared_media_staged photo and_video].each do |key|
      assert_includes view, %(t("post.#{key}")), "share-draft copy must be translated: #{key}"
      refute_match(/t\("post\.#{key}",\s*default:/, view, "remove the fallback for #{key}")
    end

    %w[en nb].each do |locale|
      yaml = read("brgen/config/locales/#{locale}.yml")
      %w[share_draft_lead shared_media_staged photo and_video].each do |key|
        assert_match(/^    #{key}:/, yaml, "#{locale} must define post.#{key}")
      end
    end
  end

  def test_mailer_brand_uses_localized_app_name
    paths = %w[
      brgen/app/views/abandoned_cart_mailer/reminder.html.erb
      brgen/app/views/email_subscription_mailer/confirm.html.erb
    ]
    paths.each do |path|
      template = read(path)
      assert_includes template, 't("app.name")', "#{path} must use the app's translated brand"
      refute_includes template, '<td class="mail-brand">Brgen</td>'
    end
  end
end
