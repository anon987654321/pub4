# frozen_string_literal: true

# A script or style block written into a template is the html half of
# NO_MULTIPLE_LANGUAGES, split out so its detector can say what it means. The
# parent rule caught it by matching a language marker, which also matched every
# ERB tag in every view.
#
# A strict Content-Security-Policy cannot fingerprint an inline block without a
# nonce, the cache cannot hold it apart from the page carrying it, and every
# tool that reads stylesheets and scripts as files walks straight past it. A tag
# with src or href suffers none of that, so this ignores them.
Law.define(:NO_INLINE_SCRIPT_BLOCK) do
  source "CSP script-src / separation of concerns — assets are files"
  severity :warn
  languages %i[html]
  detect { |line| line.match?(/<script(?![^>]*\bsrc=)|<style\b(?![^>]*\bhref=)/) }
  fix "Move it to an asset file and reference it with javascript_include_tag or stylesheet_link_tag."
  bad  "<div><script>boot()</script></div>"
  good "<div></div>"
end
