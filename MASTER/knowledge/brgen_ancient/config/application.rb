require File.expand_path("../boot", __FILE__)

require "rails/all"

Bundler.require(:default, Rails.env)

module Brgen
  class Application < Rails::Application
    config.autoload_paths += %W(#{config.root}/lib)

    # -------------------------------------------------

    # Do not swallow errors in `after_commit` / `after_rollback` callbacks

    config.active_record.raise_in_transactional_callbacks = true

    # -------------------------------------------------

    config.encoding = "utf-8"

    # -------------------------------------------------

    # i18n-js

    config.middleware.use I18n::JS::Middleware

    # Prevent from exporting all locales to the JS

    config.i18n.available_locales = [:nb, :en]

    # -------------------------------------------------

    if Rails.env.production?
      config.i18n.default_locale = :nb
    else
      config.i18n.default_locale = :en
    end

    # -------------------------------------------------

    config.assets.enabled = true
    config.assets.precompile += ["all.css", "desktop.css", "mobile.css"]
    config.assets.precompile += ["all.js", "desktop.js", "mobile.js"]
    config.assets.version = "1.0"

    # `i18n-js`

    config.assets.initialize_on_precompile = true

    # -------------------------------------------------

    # Gemoji

    config.assets.paths << Emoji.images_path
    config.assets.precompile << "emoji/*.png"

    # -------------------------------------------------

    # Photo editor

    config.filter_parameters += [:processed_photos, :original_photos]

    # -------------------------------------------------

    # Attachment background processing

    config.active_job.queue_adapter = :delayed_job
  end
end

