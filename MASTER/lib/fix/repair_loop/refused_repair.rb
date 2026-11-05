# frozen_string_literal: true

require_relative "../../io/atomic_write"
require_relative "../../io/exec"

module Master
  module Fix
    class RepairLoop
      # A repair the committer refused (house lint, rubocop, scope) used to stay in the file,
      # uncommitted: the next attempt on the file and the operator inherited the model's edit.
      # The file goes back to what it held before the repair, when it still holds exactly the
      # repair's bytes and HEAD does not already carry them (a commit whose push failed is delivered).
      module RefusedRepair
        extend Master::Io::AtomicWrite

        Write = Struct.new(:path, :before, :after, keyword_init: true)

        module_function

        def uncommitted?(write)
          path = write.path
          return false unless File.file?(path) && File.binread(path) == write.after.b

          !committed?(path, write.after.b)
        end

        def restore(write)
          write_atomic(write.path, write.before)
          Master::Trace::Dmesg.status("fix0", "put back #{File.basename(write.path)}, its repair was refused at commit")
        end

        def committed?(path, bytes)
          shown, _err, status = Master::Io::Exec.capture3("git", "-C", File.dirname(path), "show",
                                                          "HEAD:./#{File.basename(path)}")
          status.success? && shown.b == bytes
        end
      end
    end
  end
end
