# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# public/ holds canonical face sources; never re-digest output under public/assets/.
Rails.application.config.assets.excluded_paths << Rails.root.join("public", "assets")
