#!/usr/bin/env bash
# Convenience wrapper for manual runs (`./backup.sh`).
# The real, launchd-safe script lives OUTSIDE ~/Desktop because the weekly
# launchd agent cannot read scripts in the TCC-protected Desktop folder.
exec "$HOME/Library/Application Support/n8n-local/backup.sh" "$@"
