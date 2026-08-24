# Homebrew integration

The project keeps `homelab` as the canonical cross-platform command. The
repository also ships `cmd/brew-homelab`, which follows Homebrew's external
command convention and delegates to the same CLI.

For local development, put the adapter on `PATH`:

```sh
ln -s "$PWD/cmd/brew-homelab" "$HOME/.local/bin/brew-homelab"
brew homelab status
```

For public distribution, publish the adapter from a dedicated tap repository
named `homebrew-homelab-starter`. The tap should contain `cmd/brew-homelab`
and package the canonical `homelab` CLI plus its modules alongside it. Keep the main
project repository independent from Homebrew so Linux and NAS users can use
the same CLI.
