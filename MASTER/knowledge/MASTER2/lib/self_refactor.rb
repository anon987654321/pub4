# frozen_string_literal: true

module MASTER
  # SelfRefactor — thin wrapper over MultiRefactor for self-application.
  # ONE_SOURCE: MultiRefactor owns the batch-refactor engine. This wrapper
  # exists only to provide the conventional entry point expected by bin/master.
  module SelfRefactor
    extend self

    DEFAULT_PATH = File.join(MASTER.root, "lib").freeze

    # Apply MASTER2's refactor pipeline to its own source.
    # All logic (staging, convergence, resume) lives in MultiRefactor.
    def run(path: nil, dry_run: true, budget_cap: 2.0,
            force_rewrite: false, align_axioms: true,
            include_all_files: false, grounded_depth: :own)
      MultiRefactor.new(
        dry_run: dry_run, budget_cap: budget_cap,
        force_rewrite: force_rewrite, align_axioms: align_axioms,
        include_all_files: include_all_files, grounded_depth: grounded_depth,
      ).run(path: path || DEFAULT_PATH)
    end

    # Convenience: full strict self-apply
    def apply_to_self(dry_run: true)
      run(dry_run: dry_run, align_axioms: true, force_rewrite: true)
    end
  end
end
