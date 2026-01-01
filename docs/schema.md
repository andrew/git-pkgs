# Database Schema

git-pkgs stores dependency history in a SQLite database at `.git/pkgs.sqlite3`.

## Tables

### branches

Tracks which branches have been analyzed.

| Column | Type | Description |
|--------|------|-------------|
| id | integer | Primary key |
| name | string | Branch name (e.g., "main", "develop") |
| last_analyzed_sha | string | SHA of last commit analyzed for incremental updates |
| created_at | datetime | |
| updated_at | datetime | |

Indexes: `name` (unique)

### commits

Stores commit metadata for commits that have been analyzed.

| Column | Type | Description |
|--------|------|-------------|
| id | integer | Primary key |
| sha | string | Full commit SHA |
| message | text | Commit message |
| author_name | string | Author name |
| author_email | string | Author email |
| committed_at | datetime | Commit timestamp |
| has_dependency_changes | boolean | True if this commit modified dependencies |
| created_at | datetime | |
| updated_at | datetime | |

Indexes: `sha` (unique)

### branch_commits

Join table linking commits to branches. A commit can belong to multiple branches.

| Column | Type | Description |
|--------|------|-------------|
| id | integer | Primary key |
| branch_id | integer | Foreign key to branches |
| commit_id | integer | Foreign key to commits |
| position | integer | Order of commit in branch history |

Indexes: `(branch_id, commit_id)` (unique)

### manifests

Stores manifest file metadata.

| Column | Type | Description |
|--------|------|-------------|
| id | integer | Primary key |
| path | string | File path (e.g., "Gemfile", "package.json") |
| platform | string | Package manager (e.g., "rubygems", "npm") |
| kind | string | Manifest type (e.g., "manifest", "lockfile") |
| created_at | datetime | |
| updated_at | datetime | |

Indexes: `path`

### dependency_changes

Records each dependency addition, modification, or removal.

| Column | Type | Description |
|--------|------|-------------|
| id | integer | Primary key |
| commit_id | integer | Foreign key to commits |
| manifest_id | integer | Foreign key to manifests |
| name | string | Package name |
| platform | string | Package manager |
| change_type | string | "added", "modified", or "removed" |
| requirement | string | Version constraint after change |
| previous_requirement | string | Version constraint before change (for modifications) |
| dependency_type | string | "runtime", "development", etc. |
| created_at | datetime | |
| updated_at | datetime | |

Indexes: `name`, `platform`, `(commit_id, name)`

### dependency_snapshots

Stores the complete dependency state at each commit that has changes. Enables O(1) queries for "what dependencies existed at commit X" without replaying history.

| Column | Type | Description |
|--------|------|-------------|
| id | integer | Primary key |
| commit_id | integer | Foreign key to commits |
| manifest_id | integer | Foreign key to manifests |
| name | string | Package name |
| platform | string | Package manager |
| requirement | string | Version constraint |
| dependency_type | string | "runtime", "development", etc. |
| created_at | datetime | |
| updated_at | datetime | |

Indexes: `(commit_id, manifest_id, name)` (unique), `name`, `platform`

## Relationships

```
branches ──┬── branch_commits ──┬── commits
           │                    │
           │                    ├── dependency_changes ──── manifests
           │                    │
           │                    └── dependency_snapshots ── manifests
           │
           └── last_analyzed_sha (references commits.sha)
```

## Design Notes

**Why snapshots?**

Without snapshots, answering "what dependencies existed at commit X" requires replaying all changes from the beginning. With snapshots, it's a single query. The tradeoff is storage space, but SQLite handles this well.

**Why branch_commits?**

Git commits are branch-agnostic. The same commit can appear on multiple branches. This join table tracks which commits belong to which branches and their order, enabling branch-specific queries.

**Platform field duplication**

The platform appears in both `manifests` and `dependency_changes`/`dependency_snapshots`. This denormalization speeds up queries that filter by platform without requiring joins.
