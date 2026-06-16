require "unicode_utils/upcase"

# Basic usage – German sharp‑s becomes "SS"
UnicodeUtils.upcase("weiß")
#=> "WEISS"

# Turkish dotted I (requires the :tr locale)
UnicodeUtils.upcase("i", :tr)
#=> "İ"
