require 'diff/lcs'   # gem 'diff-lcs', '~> 2.0'

# Original list
seq1 = %w[a b c e h j l m n p]

# Modified list
seq2 = %w[b c d e f j k l m r s t]

# Compute the diff as an array of Diff::LCS::Change objects
diff = Diff::LCS.diff(seq1, seq2).flatten

# Pretty‑print the changes
diff.each do |change|
  case change.action
  when '+' # insertion in seq2
    puts "+ #{change.element.inspect} (at index #{change.position})"
  when '-' # deletion from seq1
    puts "- #{change.element.inspect} (at index #{change.position})"
  when '!'
    # Replacement (treated as a delete + insert)
    puts "~ #{change.element.inspect} (at index #{change.position})"
  end
end
