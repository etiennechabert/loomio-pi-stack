#!/bin/bash
# Start a Loomio process (app or worker) only once the backup container has
# finished, or deliberately skipped, restoring the database.
#
# Usage (from docker-compose.yml): bash /scripts/wait-for-restore.sh COMMAND [ARGS...]
#
# Why: PostgreSQL keeps its data on tmpfs, so the database is empty every time
# the db container starts, and backup-service/entrypoint.sh restores the newest
# backup into it. `depends_on: backup: service_healthy` is only applied by
# `docker compose up`. When Docker starts every container at once (Docker daemon
# restart, power loss), the app would run `rake db:prepare` straight away: on
# the empty database that creates an empty schema, the backup container then
# finds tables, decides the database is already populated and skips the
# restore, and the site comes up empty. If the restore has already started,
# both write to the database at the same time.
#
# The backup container opens a "restore gate" (a one-row table in PostgreSQL's
# own `postgres` database) once its restore step is done. The waiting is done in
# Ruby (ruby/wait_for_restore.rb) because the Loomio image has the pg gem but no
# psql. It never gives up: if the restore fails, Loomio stays down instead of
# starting on an empty database.
set -euo pipefail

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 COMMAND [ARGS...]" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Returns only once the gate is open; any failure stops this container
bundle exec ruby "${SCRIPT_DIR}/ruby/wait_for_restore.rb"

exec "$@"
