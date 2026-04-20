require 'diff/lcs'

seq1 = %w[a b c e h j l m n p]
seq2 = %w[b c d e f j k l m r s t]

diffs   = Diff::LCS.diff(seq1, seq2)
sdiff   = Diff::LCS.sdiff(seq1, seq2)
lcs     = Diff::LCS.lcs(seq1, seq2)
patch!  = Diff::LCS.patch!(seq1, diffs)
unpatch! = Diff::LCS.unpatch!(seq2, diffs)
