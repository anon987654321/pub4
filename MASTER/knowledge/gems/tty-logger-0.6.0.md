logger = TTY::Logger.new
logger.info "Deployed"
logger.success "Deployed", "successfully"
logger.warn  "Low memory"
logger.error "Failed"
