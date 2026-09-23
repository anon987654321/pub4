# frozen_string_literal: true
# instrument: code_lines=6 longest_method=2 public_methods=1

# Comments are not length.
#
# lint:spine charged for comment lines while [DENSITY] deliberately did not, so
# a paragraph of rationale above a tricky line satisfied one rule and breached
# the other. In a tree whose convention is to write that paragraph, the only way
# to pass was to delete the explanation. Settled 2026-08-10: both count code
# lines. This fixture is what "both" has to mean.
class DocumentedMethod
  # A method whose comments outnumber its code, which is normal here and must
  # not read as a long method.
  def call(input)
    # Explaining the next line does not make the method longer.
    normalized = input.to_s.strip
    normalized.empty? ? nil : normalized
  end
end
