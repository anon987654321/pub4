RubyPants: SmartyPants for Ruby

[![Gem](https://img.shields.io/gem/v/rubypants.svg?maxAge=2592000&style=plastic)](https://rubygems.org/gems/rubypants)
[![Travis](https://img.shields.io/travis/jmcnevin/rubypants.svg?maxAge=2592000&style=plastic)](https://travis-ci.org/jmcnevin/rubypants)
[![CodeCov](https://img.shields.io/codecov/c/github/jmcnevin/rubypants.svg?maxAge=2592000&style=plastic)](https://codecov.io/gh/jmcnevin/rubypants)

Synopsis
--------
RubyPants converts ASCII punctuation to smart typographic HTML entities.

Description
-----------
Transforms:
- Straight quotes (`"` and `'`) to curly quote entities
- Backticks-style quotes (`''like this''`) to curly quotes
- Dashes (`--`, `---`) to en‑ and em‑dashes
- Three consecutive dots (`...` or `. . .`) to an ellipsisApplies only outside `<pre>`, `<code>`, `<kbd>`, `<math>`, `<style>`, `<script>` tags.

Installation
------------
gem install rubypants
# or
gem 'rubypants'   # Gemfile

Usage
-----
output = RubyPants.new(input_string).to_html
# Options: see lib/rubypants/core.rb

Backslash Escapes
-----------------
Precede characters to keep them literal:
\\ → \   \" → "   \' → '
\. → .   \- → -   \` → `

Escapes render as decimal HTML entities, e.g., `6\'2\"` produces 6'2".

Algorithmic Shortcomings
------------------------
Apostrophes at the start of contractions (e.g., *'Twas'*) may become opening quotes. This is a known limitation; use `&#8217;` manually when needed.

Bugs
----Report issues on GitHub, including example text for quote‑curling problems.

Authors
-------
John Gruber created SmartyPants (Perl) and its documentation.
Chad Miller ported it to Python.
Christian Neukirchen ported it to Ruby.
Jeremy McNevin hosted the GitHub repository.
Aron Griffis maintains jekyll‑pants.

Links
-----
John Gruber: http://daringfireball.net
SmartyPants: http://daringfireball.net/projects/smartypants
Chad Miller: http://web.chad.org
Christian Neukirchen: http://kronavita.de/chris
Aron Griffis: https://arongriffis.com