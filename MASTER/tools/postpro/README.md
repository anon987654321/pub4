# postpro

postpro provides cinematic image post-processing through MASTER’s tool surface while the implementation remains in DEPLOY/postpro/postpro.rb. Run ruby MASTER/tools/postpro.rb --help to see options; all arguments forward to DEPLOY/postpro/postpro.rb.

The tool needs Ruby, libvips via ruby-vips, and optionally tty-prompt. It may shell out for image operations, so treat invocations as side-effecting. MASTER wires postpro as the CLI /postpro with contract postpro and permission exec. New callers should use this entrypoint rather than ad-hoc DEPLOY/postpro.rb paths.