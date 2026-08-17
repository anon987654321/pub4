# frozen_string_literal: true

# A document that declares no encoding leaves the browser to guess, and the
# guess is wrong often enough that WHATWG requires the declaration.
#
# Only a document can carry one. A partial has no head to put it in, so the
# earlier detector — anything lacking the meta tag — fired on all 423 partials
# in RAILS and on 5 layouts, and the 423 could not have complied if they tried.
# The guard asks whether this file is a document before asking whether it
# declares its encoding.
Law.define(:META_CHARSET) do
  source "HTML Living Standard — meta charset utf-8 (WHATWG)"
  severity :error
  languages %i[html]
  scope :file
  # Both spellings count. The http-equiv form is the older one, and mail clients
  # honour it more reliably than the HTML5 short form — so shared/layouts/mailer
  # declares its encoding that way on purpose, and a detector accepting only the
  # short form called the one correct file in the tree an error.
  detect { |text| text.match?(/<html\b|<body\b/) && !text.match?(/<meta\s+charset=|charset=["']?utf-8/i) }
  fix "Add a UTF-8 charset declaration as the first element in head."
  bad  "<html><head><title>x</title></head></html>"
  good "<html><head><meta charset=\"UTF-8\"></head></html>"
end
