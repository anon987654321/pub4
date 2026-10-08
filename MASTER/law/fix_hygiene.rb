# frozen_string_literal: true

# Post-incident /fix hygiene laws. These are deliberately narrow deterministic
# guards: they catch the shapes that actually caused the recent failures while
# leaving ordinary numeric conversion and explanatory prose alone.

Law.define(:NO_INFINITY_TO_I) do
  source "MASTER post-incident /fix hardening — finite convergence ranks"
  severity :error
  languages %i[ruby]
  path_exclude %r{/law/fix_hygiene\.rb\z}
  detect do |line|
    code = line.gsub(/(['"]).*?\1/, "").sub(/#.*\z/, "")
    code.match?(
      /Float::(?:INFINITY|POSITIVE_INFINITY|NEGATIVE_INFINITY|NAN).*?\.(?:to_i|to_int)\b|
       \.(?:to_i|to_int)\b.*?Float::(?:INFINITY|POSITIVE_INFINITY|NEGATIVE_INFINITY|NAN)/x,
    )
  end
  fix "Use a finite sentinel or score_value before integer coercion; never call to_i/to_int on a non-finite float."
  bad "Float::INFINITY.to_i"
  good "UNMEASURED_SCORE = 1_000_000_000"
end

Law.define(:NO_OVERESCAPED_NONCAPTURING) do
  source "MASTER post-incident /fix hardening — extract-then-match regex integrity"
  severity :error
  languages %i[ruby]
  path_exclude %r{/law/fix_hygiene\.rb\z}
  detect do |line|
    code = line.gsub(/(['"]).*?\1/, "")
    code.include?("\\\\(?:")
  end
  fix "Match the extracted regex body with regex syntax appropriate to the body; do not add source-level escaping twice."
  bad 'body.scan(/phantom:\\\\(?:detected|halt|recovery)/)'
  good "body.scan(/phantom:(detected|halt|recovery)/)"
end
