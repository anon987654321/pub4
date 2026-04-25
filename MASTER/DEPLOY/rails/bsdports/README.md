# Master Port for OpenBSD

This port installs the Master application, an AI agent system, on OpenBSD.

## Installation

To install the port, use the OpenBSD ports system:

    # cd /usr/ports/rails/master
    # make install clean

## Dependencies

This port depends on:
- Ruby (version specified in the port's Makefile)
- Ruby gems managed via Bundler (see Gemfile)
- System packages: none required beyond base OpenBSD

## Configuration

After installation, configure the application by editing:
    /etc/master/master.yaml

Example configuration is installed to:
    /usr/local/share/examples/master/master.yaml

## Service

To enable and start the service:

    # rcctl enable master
    # rcctl start master

The service runs as the _master user (created automatically).

## Logs

Application logs are written to:
    /var/log/master/master.log

Log rotation is configured via newsyslog(8).

## Further Information

For more information about the Master application, see:
    https://github.com/yourorg/master

Refer to the port's Makefile for build-time options and patches.

# Master Port for OpenBSD

This port installs the Master application, an AI agent system, on OpenBSD.

## Installation

To install the port, use the OpenBSD ports system:

    # cd /usr/ports/rails/master
    # make install clean

## Dependencies

This port depends on:
- Ruby (version specified in the port)
- Ruby gems managed via Bundler
- No additional system packages beyond base OpenBSD

## Configuration

After installation, configure the application by editing:
    /etc/master/master.yaml

Example configuration is installed to:
    /usr/local/share/examples/master/master.yaml

## Service

To enable and start the service:

    # rcctl enable master
    # rcctl start master

The service runs as the _master user (created automatically).

## Logs

Application logs are written to:
    /var/log/master/master.log

Log rotation is configured via /etc/newsyslog.conf.

## Further Information

For more information about the Master application, see:
    https://github.com/yourorg/master

Refer to the port's Makefile for build-time options and patches.