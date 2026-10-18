# Contributing to RoadRescue

Quick ground rules so five people working across three layers don't step on each other.

## Branch naming

Never push directly to `main`. Branch off it using this pattern:

```
feature/<short-description>     e.g. feature/sos-screen
fix/<short-description>         e.g. fix/gps-null-crash
docs/<short-description>        e.g. docs/chapter-3-dfd
```

## Commit messages

Keep them short and in the present tense:

```
Add SOS button to home screen
Fix phone-sensor crash detection
Update Chapter 4 architecture diagram
```

Avoid vague commits like "update" or "fix stuff."

## Pull requests

1. Open a PR from your branch into `main`.
2. Write a one-line summary of what changed and why.
3. Tag at least one teammate to review before merging — especially for anything touching `backend/` or shared data models, since other tracks depend on them.
4. Delete the branch after merging to keep things tidy.

## Folder ownership (rough guide)

- `app/` — mobile/frontend developer
- `backend/` — backend developer
- `iot/` — IoT/embedded developer
- `docs/` — whoever's writing that chapter (coordinate to avoid overlap)
- `design/` — shared, update as wireframes/diagrams evolve

## Before you push

- Pull the latest `main` first (`git pull origin main`) to avoid conflicts.
- Don't commit secrets — Firebase config keys, API tokens, etc. go in `.gitignore`'d files (see `.env.example` if one exists).
- Run tests locally if you touched `app/` or `backend/` logic.

## Weekly sync

Review the task tracker as a team weekly. Update task status and flag blockers in the Notes column so nothing silently stalls.
