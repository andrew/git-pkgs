# Package Enrichment

Most git-pkgs commands work entirely from your git history. Your manifests and lockfiles tell us which packages you depend on, who added them, and when. But some questions require data that isn't in your repository: what's the latest version available? what license does this package use? has a security vulnerability been disclosed?

The `outdated`, `licenses`, and `sbom` commands fetch this external metadata from the [ecosyste.ms Packages API](https://packages.ecosyste.ms/), which aggregates data from npm, RubyGems, PyPI, and other registries. See also [vulns.md](vulns.md) for vulnerability scanning via OSV.

## outdated

Show packages that have newer versions available in their registries.

```
$ git pkgs outdated
lodash      4.17.15  ->  4.17.21  (patch)
express     4.17.0   ->  4.19.2   (minor)
webpack     4.46.0   ->  5.90.3   (major)

3 outdated packages: 1 major, 1 minor, 1 patch
```

Major updates are shown in red, minor in yellow, patch in cyan.

### Options

```
-e, --ecosystem=NAME    Filter by ecosystem
-r, --ref=REF           Git ref to check (default: HEAD)
-f, --format=FORMAT     Output format (text, json)
    --major             Show only major version updates
    --minor             Show only minor or major updates (skip patch)
    --stateless         Parse manifests directly without database
```

### Examples

Show only major updates:

```
$ git pkgs outdated --major
webpack     4.46.0   ->  5.90.3   (major)
```

Check a specific release:

```
$ git pkgs outdated v1.0.0
```

JSON output:

```
$ git pkgs outdated -f json
```

## licenses

Show licenses for dependencies with optional compliance checks.

```
$ git pkgs licenses
lodash      MIT       (npm)
express     MIT       (npm)
request     Apache-2.0  (npm)
```

### Options

```
-e, --ecosystem=NAME    Filter by ecosystem
-r, --ref=REF           Git ref to check (default: HEAD)
-f, --format=FORMAT     Output format (text, json, csv)
    --allow=LICENSES    Comma-separated list of allowed licenses
    --deny=LICENSES     Comma-separated list of denied licenses
    --permissive        Only allow permissive licenses (MIT, Apache, BSD, etc.)
    --copyleft          Flag copyleft licenses (GPL, AGPL, etc.)
    --unknown           Flag packages with unknown/missing licenses
    --group             Group output by license
    --stateless         Parse manifests directly without database
```

### Compliance Checks

Only allow permissive licenses:

```
$ git pkgs licenses --permissive
lodash      MIT       (npm)
express     MIT       (npm)
gpl-pkg     GPL-3.0   (npm)  [copyleft]

1 license violation found
```

Explicit allow list:

```
$ git pkgs licenses --allow=MIT,Apache-2.0
```

Deny specific licenses:

```
$ git pkgs licenses --deny=GPL-3.0,AGPL-3.0
```

Flag packages with no license information:

```
$ git pkgs licenses --unknown
```

### Output Formats

Group by license:

```
$ git pkgs licenses --group
MIT (45)
  lodash
  express
  ...

Apache-2.0 (12)
  request
  ...
```

CSV for spreadsheets:

```
$ git pkgs licenses -f csv > licenses.csv
```

JSON for scripting:

```
$ git pkgs licenses -f json
```

### Exit Codes

The licenses command exits with code 1 if any violations are found. This makes it suitable for CI pipelines:

```yaml
- run: git pkgs licenses --stateless --permissive
```

### License Categories

Permissive licenses (allowed with `--permissive`):
MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, ISC, Unlicense, CC0-1.0, 0BSD, WTFPL, Zlib, BSL-1.0

Copyleft licenses (flagged with `--copyleft` or `--permissive`):
GPL-2.0, GPL-3.0, LGPL-2.1, LGPL-3.0, AGPL-3.0, MPL-2.0 (and their variant identifiers)

## sbom

Export dependencies as a Software Bill of Materials (SBOM) in SPDX or CycloneDX format.

```
$ git pkgs sbom
{
  "spdxVersion": "SPDX-2.3",
  "name": "my-project",
  "packages": [
    {
      "name": "lodash",
      "versionInfo": "4.17.21",
      "licenseConcluded": "MIT",
      "externalRefs": [
        {
          "referenceType": "purl",
          "referenceLocator": "pkg:npm/lodash@4.17.21"
        }
      ]
    }
  ]
}
```

### Options

```
-t, --type=TYPE         SBOM type: cyclonedx (default) or spdx
-f, --format=FORMAT     Output format: json (default) or xml
-n, --name=NAME         Project name (default: repository directory name)
-e, --ecosystem=NAME    Filter by ecosystem
-r, --ref=REF           Git ref to export (default: HEAD)
    --skip-enrichment   Skip fetching license data from registries
    --stateless         Parse manifests directly without database
```

### Examples

CycloneDX format:

```
$ git pkgs sbom --type cyclonedx
```

XML output:

```
$ git pkgs sbom -f xml
```

Skip license enrichment for faster output:

```
$ git pkgs sbom --skip-enrichment
```

The SBOM includes package URLs (purls), versions, licenses (from registry lookup), and integrity hashes (from lockfiles when available).

## Data Source

These commands fetch package metadata from [ecosyste.ms](https://packages.ecosyste.ms/), which aggregates data from npm, RubyGems, PyPI, Cargo, and other package registries.

## Caching

Package metadata is cached in the pkgs.sqlite3 database. Each package tracks when it was last enriched, and stale data (older than 24 hours) is automatically refreshed on the next query.

The cache stores:
- Latest version number
- License (SPDX identifier)
- Description
- Homepage URL
- Repository URL

## Stateless Mode

All three commands support `--stateless` mode, which parses manifest files directly from git without requiring a database. This is useful in CI environments where you don't want to run `git pkgs init` first.

```
$ git pkgs outdated --stateless
$ git pkgs licenses --stateless --permissive
$ git pkgs sbom --stateless
```

In stateless mode, package metadata is fetched fresh each time and cached only in memory for the duration of the command.
