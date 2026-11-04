# Changelog – redmine_expert_checklists

> 🇬🇧 English version · [Deutsche Version](CHANGELOG.de.md)
>
> EN is authoritative — release notes are generated from this file.

## [Unreleased]

### Changed

- **The tests also run on MySQL and PostgreSQL.** CI runs the suite on MariaDB for every supported
  Redmine version and, for the oldest and the newest (5.1 and 7.0), on MySQL 8.4 and PostgreSQL 17
  as well.

## [0.1.0] - 2026-11-03

### Added

- Checklists on issues: items and sections, a block on the issue page with progress and
  "Hide done", ticking without a page reload.
- Editor in the issue form: add, rename, tick, delete, drag or Alt+Up/Down to reorder, paste
  several lines as several items (`-- ` section, `[x] ` done). Rows only overwrite what the user
  changed, so a tick made by someone else while the form was open survives the save.
- History: one detail per changed item, rendered as one line each in the history, notification
  mails, the PDF export and the journals feed. Hidden from users without the view permission.
- Bundled mails: ticks and REST changes by the same user within 60 seconds share one history entry
  and one notification, sent in the background once the user stops (at most ten minutes per
  bundle). Pending mails are stored, a sweeper re-sends what a restart left behind, and
  `POST /expert_checklists/notifications/flush.json` (admin API key) sends everything due.
  Setting: like issue updates / always / never.
- Optional: % Done from the share of ticked items; blocking the change to a closed status while
  items are open.
- Copying an issue (form, bulk, project copy, subtasks) copies its checklist.
- Issue list: "Checklist" column (HTML, CSV, PDF) and filters by item state and item text.
- REST API under `/issues/:id/expert_checklist_items` and `/expert_checklist_items/:id` (JSON and
  XML, RedmineUP field names), `issue[expert_checklist_items_attributes]` on the issue API. Once
  RedmineUP Checklists is removed, its paths and `issue[checklists_attributes]` answer as well.
- Import from RedmineUP Checklists (admin page and rake task, dry run first): items with their ids,
  permissions, settings, saved queries, project module. RedmineUP's history entries stay readable.
- Project module "expert Checklists" with the permissions view, tick and edit.
- UI in English, German, Spanish, French, Italian and Portuguese (Portugal, Brazil).
