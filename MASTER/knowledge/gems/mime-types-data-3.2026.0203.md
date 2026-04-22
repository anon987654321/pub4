# frozen_string_literal: true

# Configure MiniMime with **absolute, immutable** paths to the mime‑type databases.
# The databases are shipped with the `mime-types-data` gem under
# `MIME::Types::Data::PATH`. Using `File.expand_path` guarantees reliable absolute
# paths on all platforms, including OpenBSD, regardless of the current working
# directory.
#
#   • **ext_db_path** – maps file extensions → MIME types.
#   • **content_type_db_path** – maps MIME types → default extensions.

EXT_DB_PATH     = File.expand_path('ext_mime.db', MIME::Types::Data::PATH).freeze
CONTENT_DB_PATH = File.expand_path('content_type_mime.db', MIME::Types::Data::PATH).freeze

# Fail fast if the data files are missing – this surfacing helps during CI and
# prevents silent fall‑through to a broken configuration.
raise LoadError, "Missing MiniMime extension DB at #{EXT_DB_PATH}" unless File.file?(EXT_DB_PATH)
raise LoadError, "Missing MiniMime content‑type DB at #{CONTENT_DB_PATH}" unless File.file?(CONTENT_DB_PATH)

# Apply configuration only once; subsequent loads become a no‑op.
MiniMime::Configuration.ext_db_path          ||= EXT_DB_PATH
MiniMime::Configuration.content_type_db_path ||= CONTENT_DB_PATH