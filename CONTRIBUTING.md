# Contributing

Thanks for helping make homelab-starter useful on more machines.

## Module expectations

Each module should:

- document prerequisites and the exact state it changes;
- provide an idempotent install/apply path where practical;
- support status and a dry-run or preview mode for destructive actions;
- keep machine-specific values in ignored configuration files or profiles;
- avoid embedding credentials, usernames, hostnames, or absolute local paths.

Before opening a pull request, run the validation commands from the module
README and include any platform limitations in the description.
