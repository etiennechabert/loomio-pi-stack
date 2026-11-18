# frozen_string_literal: true

# Waits until the backup container has opened the restore gate, then exits 0.
# Run by scripts/wait-for-restore.sh (through `bundle exec`, for the pg gem)
# before the app and worker start Loomio. See that script for why.
#
# The gate is open once backup-service/entrypoint.sh has written one row into
# GATE_TABLE in PostgreSQL's own `postgres` database, at the end of its restore
# step (restored, skipped because the database was populated, or no backup).
# Anything else - database not up yet, table missing, connection error - means
# "keep waiting". This script never starts Loomio on its own after a timeout.

require "pg"

# Keep in sync with RESTORE_GATE_DB / RESTORE_GATE_TABLE in backup-service/entrypoint.sh
GATE_DB = "postgres"
GATE_TABLE = "loomio_restore_gate"

POLL_SECONDS = 5
REPORT_EVERY_SECONDS = 60

$stdout.sync = true

# Returns the gate row (a Hash) once the gate is open, or a String saying why
# we are still waiting.
def gate_state(database_url)
  conn = PG.connect(database_url, dbname: GATE_DB, connect_timeout: 10)
  conn.exec("SELECT outcome, finished_at FROM #{GATE_TABLE} LIMIT 1").first ||
    "the restore gate is closed"
rescue PG::UndefinedTable
  "the backup container has not finished its restore step yet"
rescue PG::Error => e
  "cannot check the database yet (#{e.message.lines.first.to_s.strip})"
ensure
  conn&.close
end

database_url = ENV["DATABASE_URL"].to_s
if database_url.empty?
  warn "wait_for_restore: DATABASE_URL is not set, cannot check whether the restore has finished"
  exit 1
end

puts "wait_for_restore: waiting for the backup container to finish its restore step before starting Loomio"
started = Time.now
last_report = nil

loop do
  state = gate_state(database_url)

  if state.is_a?(Hash)
    puts "wait_for_restore: restore step finished at #{state['finished_at']} " \
         "(#{state['outcome']}) - starting Loomio"
    exit 0
  end

  now = Time.now
  if last_report.nil? || now - last_report >= REPORT_EVERY_SECONDS
    puts "wait_for_restore: still waiting after #{(now - started).round}s: #{state}. " \
         "Check `docker compose logs backup`. If the backup container is healthy but the " \
         "db container was restarted after it, run `docker compose restart backup`."
    last_report = now
  end

  sleep POLL_SECONDS
end
