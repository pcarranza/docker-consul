#!/usr/bin/dumb-init /bin/sh
set -e

# Note above that we run dumb-init as PID 1 in order to reap zombie processes
# as well as forward signals to all processes in its session. Normally, sh
# wouldn't do either of these functions so we'd leak zombies as well as do
# unclean termination of all our sub-processes.
# As of docker 1.13, using docker run --init achieves the same outcome.

# If the user is trying to run Consul directly with some arguments, then
# pass them to Consul.
if [ "${1:0:1}" = '-' ]; then
    set -- consul "$@"
fi

# Look for Consul subcommands.
if [ "$1" = 'agent' ]; then
    shift
    set -- consul agent \
        "$@"
elif [ "$1" = 'version' ]; then
    # This needs a special case because there's no help output.
    set -- consul "$@"
elif consul --help "$1" 2>&1 | grep -q "consul $1"; then
    # We can't use the return code to check for the existence of a subcommand, so
    # we have to use grep to look for a pattern in the help output.
    set -- consul "$@"
fi

# If we are running Consul, make sure it executes as the proper user.
if [ "$1" = 'consul' ]; then
    # If the data or config dirs are bind mounted then chown them.
    # Note: This checks for root ownership as that's the most common case.
    if [ "$(stat -c %u /consul/data)" != "$(id -u consul)" ]; then
        chown consul:consul /consul/data
    fi
    if [ "$(stat -c %u /consul/config)" != "$(id -u consul)" ]; then
        chown consul:consul /consul/config
    fi

    # If requested, set the capability to bind to privileged ports before
    # we drop to the non-root user. Note that this doesn't work with all
    # storage drivers (it won't work with AUFS).
    if [ ! -z ${CONSUL_ALLOW_PRIVILEGED_PORTS+x} ]; then
        setcap "cap_net_bind_service=+ep" /bin/consul
    fi

    set -- su-exec consul:consul "$@"
fi

exec "$@"
