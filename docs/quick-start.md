# Quick Start

## Setup

```bash
cd your-project
git pkgs init
```

## Basic Commands

```bash
# Show current dependencies
git pkgs list

# Filter by manifest
git pkgs list --manifest=Gemfile

# Show dependencies at a specific point in time
git pkgs list january-2025

# Show dependency changes in HEAD commit
git pkgs show

# Compare dependencies between refs
git pkgs diff --from=HEAD~10
git pkgs diff --from=january-2025
```

## History and Blame

```bash
# History of a specific package
git pkgs history rails

# All dependency changes by an author
git pkgs history --author=Andrew

# Find where a package is declared
git pkgs where dotenv-rails
```

## Package Health

```bash
# Find outdated packages
git pkgs outdated

# Show licenses with compliance check
git pkgs licenses
git pkgs licenses --permissive
```

## Vulnerability Scanning

```bash
# Show commits that introduced or fixed vulnerabilities
git pkgs vulns log

# Show who introduced vulnerabilities
git pkgs vulns blame

# Show who fixed vulnerabilities
git pkgs vulns praise

# Show exposure metrics over all time
git pkgs vulns exposure --all-time
```

## SBOM Export

```bash
# Export as CycloneDX (default)
git pkgs sbom > sbom.json

# Export as SPDX
git pkgs sbom --type=spdx
```

## Git Integration

```bash
# Install diff driver for semantic lockfile diffs
git pkgs diff-driver --install

# Now git diff shows dependency changes
git diff HEAD~5 -- Gemfile.lock
```

## Database Schema

```bash
# Show database schema
git pkgs schema
```
