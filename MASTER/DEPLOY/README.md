# Deployment

Master can be deployed via OpenBSD scripts or as a Rails application.

## OpenBSD

See `openbsd/README.md` for detailed instructions. The `openbsd/openbsd.sh` script handles:
- Package installation
- User and service creation
- Configuration file deployment
- System startup

## Rails (Web Interface)

See `rails/README.md` for deploying the web interface. Includes:
- Ruby and dependency setup
- Database configuration
- Asset precompilation
- Server startup (Puma/systemd)

## Common Steps

1. Clone repository
2. Install Ruby dependencies: `bundle install`
3. Review configuration in `config/`
4. Set environment variables (see deployment guides)
5. Run migrations: `bin/rails db:migrate` (if applicable)
6. Start services per platform instructions

## Troubleshooting

- Check logs in `log/` and `tmp/`
- Verify dependencies with `bundle check`
- Consult platform-specific guides in subdirectories
- See `SOUL.md` for architectural overview

--- 
*Last updated: $(date +%Y-%m-%d)*