# frozen_string_literal: true

# Small runtime flag to let operators transition from inline job execution
# (run_inline!) to running jobs in Solid Queue without editing many job classes.
#
# Set RUN_JOBS_INLINE=false in the process environment (rc.d, systemd, deploy.yml)
# on machines that run the Solid Queue supervisor. Default is true for backwards
# compatibility with current deployments that inline critical mail jobs.
#
# This file only documents the env flag used by ApplicationJob.run_inline!.
