# Changelog – redmine_expert_checklists

> 🇬🇧 English version · [Deutsche Version](CHANGELOG.de.md)
>
> EN is authoritative — release notes are generated from this file.

## [Unreleased]

## [0.3.0] - 2026-11-09

### Added

- **Checklist templates.** Reusable item lists for a project (project settings, tab *Checklist
  templates*, permission *Manage checklist templates*) or for all projects (plugin settings,
  administrators), for one tracker or all, public or private, grouped by categories. The issue form
  appends one with *Add from template*. A default template fills new issues created with the form
  or through the REST API: project before global, tracker before all trackers. An untouched default
  follows a change of tracker or project in the form.
- The import takes over RedmineUP's templates and categories (step *Templates*, also when
  switching single projects) and maps its *Manage checklist templates* permission.

### Fixed

- PostgreSQL: the RedmineUP import could fail with a duplicate key when items of both plugins had
  the same id (side-by-side use): the ids given to those rows could hit ones just kept.

## [0.2.0] - 2026-11-09

### Added

- **Switch project by project.** The import page and the rake task (`PROJECTS=`) switch chosen
  projects from RedmineUP Checklists while it stays installed for the others: their checklists are
  copied again, their saved queries converted, our module switched on and RedmineUP's off - in one
  transaction. Needs RedmineUP's permissions in a project module of their own; the README lists
  the changes to RedmineUP this takes.
- RedmineUP's history entries render in switched projects, and copying an issue from a project
  still on RedmineUP takes RedmineUP's items.

### Changed

- **The checklists step copies again what RedmineUP still holds.** While RedmineUP is installed,
  issues of projects without our module are copied again, replacing an earlier copy (or removing
  it where RedmineUP's checklist has since been emptied), instead of being skipped once copied. Once it is gone, issues with a checklist of ours are still skipped.
- The module step also switches RedmineUP's own module off where it has one, and always copies the
  checklists first. Next to an installed RedmineUP it is no longer preselected on the import page.
- Import steps always run in their fixed order, whatever order they are given in.

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
