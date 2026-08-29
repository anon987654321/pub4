# Virus museum

**A quarantine that is empty is still a quarantine, and this one is load-bearing
precisely because nothing is in it.** Material flagged and pulled out of the live
tree lands here as inert reference rather than being deleted outright.

`MASTER/tools/security_sweep.rb` enforces two things about this directory. Every
file in it is a `.txt`, or this README — never an executable extension, and never
tracked with an executable git file mode. And nothing here is run, sourced, or
loaded by any part of the codebase.

The directory holds nothing today. It exists so the sweep's structural check has
a subject.
