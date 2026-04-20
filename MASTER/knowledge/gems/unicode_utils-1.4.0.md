require "unicode_utils/upcase"

UnicodeUtils.upcase("weiß")   # => "WEISS"
UnicodeUtils.upcase("i", :tr) # => "İ"
