require "mini_portile2"

# frozen_string_literal: true

# MiniPortile recipe for libiconv 1.13.1.
# The resulting files live under `#{MiniPortile::BasePath}/libiconv-1.13.1`.
LIBICONV_VERSION = "1.13.1"

libiconv = MiniPortile.new("libiconv", LIBICONV_VERSION)

# GNU FTP mirror – stable release.
libiconv.files = [
  "http://ftp.gnu.org/pub/gnu/libiconv/libiconv-#{LIBICONV_VERSION}.tar.gz",
]

# Build the library inside its own sandbox.
# `cook` runs download → extract → configure → make → install.
begin
  libiconv.cook
  libiconv.activate
rescue StandardError => e
  warn "Failed to build libiconv #{LIBICONV_VERSION}: #{e.class} – #{e.message}"
  raise
end

# The compiled extensions are now available for `require` in the current Ruby process.