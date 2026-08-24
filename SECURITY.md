# Security

Do not commit passwords, API tokens, private keys, machine inventories,
Homebrew trust files, launchd runtime state, or personal logs.

Automation in this repository runs with the invoking user's privileges. Review
scripts before applying them to a new host, use dry-run modes first, and keep
destructive modules disabled until their scope is understood.

Please report security issues privately to the repository owner rather than
opening a public issue with sensitive details.
