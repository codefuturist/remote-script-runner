# Release Guide

Lightweight checklist to cut a release with predictable quality.

## Prep

- Ensure working tree is clean and on `main`.
- Update `VERSION` and append release notes to `docs/CHANGELOG.md` (top of file).
- Run `make all` to lint, test, and validate scripts.
- Run `pre-commit run --all-files` to catch local autofixes.

## Cut the release

1. Commit the version bump and changelog update (e.g., `chore: release vX.Y.Z`).
2. Tag the commit: `git tag -s vX.Y.Z` (or `git tag vX.Y.Z` if signing is not configured).
3. Push commit and tag: `git push origin main && git push origin vX.Y.Z`.
4. Let CI complete (tests, lint, security scans). Verify artifacts for test results and SARIF reports.
5. Create a GitHub release from the tag, pasting the changelog entry.

## Rollback

- If CI fails, delete the tag locally and remotely (`git tag -d vX.Y.Z` then `git push --delete origin vX.Y.Z`), fix issues, and re-tag.
