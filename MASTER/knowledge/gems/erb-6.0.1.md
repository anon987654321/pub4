# ERB (Embedded Ruby)

ERB is a template processor. It formats runtime data into strings.

## Typical Uses
- Personalized email.
- Personalized web pages.
- Code generation.

ERB behaves like `sprintf` but supports arbitrary Ruby execution.

## Operation

Create a template: a plain‑text string with special tags. Store it in an ERB object. When ERB renders, it:

- Inserts evaluated expressions.
- Executes Ruby snippets.
- Ignores comment tags.

Result handling:

- Non‑tag text passes through unchanged.
- Expression tags (`<%={ expression }%>`) replace themselves with the expression value.
- Execution tags (`<% code %>`) run silently.
- Comment tags (`<%# comment %>`) are ignored.

Examples using the `erb` CLI:

- Expression: `<%= $VERBOSE %>` → `"false"`
- Expression: `<%= 2 + 2 %>` → `"4"`
- Execution: `<% if $VERBOSE %> Long<% else %> Short<% end %>` → `" Short "`
- Comment: `<%# TODO %> Nonsense` → `" Nonsense."`

## Usage

Use ERB in code via the `ERB` class or from the command line (`erb` executable).

## InstallationRuby includes ERB; no separate installation is required.

## Template Engines

Other template engines exist for Ruby projects. RDoc provides its own engine. Additional engines are listed in the Ruby Toolbox.

## Code

The ERB source resides in the `ruby/erb` repository on GitHub.

## Bugs

Report bugs to the `ruby/erb` issue tracker.

## LicenseERB is released under the 2‑Clause BSD License.

[2‑Clause BSD License]: https://opensource.org/licenses/BSD-2-Clause  
[ruby/erb]: https://github.com/ruby/erb  
[ruby toolbox]: https://www.ruby-toolbox.com/categories/template_engines  
[sprintf]: https://docs.ruby-lang.org/en/master/Kernel.html#method-i-sprintf  
[template processor]: https://en.wikipedia.org/wiki/Template_processor