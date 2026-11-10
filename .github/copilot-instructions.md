# Copilot instructions – redmine_expert_checklists

This file mirrors [`CLAUDE.md`](../CLAUDE.md). The two are intentional duplicates for
different tools — **keep them in sync when either changes.**

Checklists on Redmine issues, replacing RedmineUP Checklists PRO. Items and sections, ticking on
the issue page, an editor in the issue form, history, bundled notification mails, REST API, issue
list column and filters, templates, and an import from RedmineUP's tables. Three migrations (items,
pending notifications, templates + categories), project module `:expert_checklists` (permissions
view / done / edit / manage templates), settings
`notifications`, `done_ratio_from_checklist`, `block_issue_closing`, `legacy_import_done_at`.

This directory lives inside the parent `redmine-expert` deployment repo (`../../`). It is
**not** a Redmine checkout — Redmine only exists inside the Docker image. Run everything
from the parent repo root and read its `README.md` first (hard rule: never `docker exec`;
rebuild with `docker-compose -f docker-compose.yml up --build`).

## Layout

- `lib/redmine_expert_checklists.rb` – settings readers, permission checks (`viewable?` – any of
  the three permissions, `tickable?`, `editable?` – all false while the module is off in the
  project), the item snapshot `{subject, is_done, is_section}` and `redmineup_present?` (a file
  test, also used by routes.rb).
- `lib/redmine_expert_checklists/recorder.rb` – **direct changes** (tick, REST): one transaction
  with the issue row locked, snapshot before/after, `Journalizer.diff`, done ratio, then either
  merge into the user's pending journal (`expert_checklist_notifications` row still due, issue's
  last journal, at most `MAX_BUNDLE_SPAN`) or a new journal with `notify = false` plus a row.
  `ExpertChecklistNotificationJob` is scheduled for `due_at`; it claims the row by deleting it for
  its revision (a merge bumps the revision, so stale jobs do nothing) and calls core
  `Mailer.deliver_issue_edit` in the same transaction; if that raises, the claim rolls back and
  `due_at` moves out by the row's age (at least 5 min); the sweeper drops rows older than a day.
  `ExpertChecklistNotification.sweep_if_due` (after every write, throttled by a `Rails.cache`
  SET NX) re-enqueues rows whose job died with a pod (`updated_at` marks the re-enqueue, and the
  gap to the next one doubles, so a stalled queue does not get a job per sweep);
  `POST /expert_checklists/notifications/flush` does the same for a cron. **Never deliver mail
  inside the request** – RedmineUP's synchronous mails made a tick take seconds.
- `lib/redmine_expert_checklists/patches/issue_patch.rb` – **form changes**: `has_many
  :expert_checklist_items`, nested attributes (rows in display order give the positions; `*_was`
  fields keep a concurrent tick from being reverted; rows of deleted items are dropped), an
  `after_save` that appends our details to core's `current_journal` (core mails it right away),
  done ratio (`before_save`), block closing (`validate`, only on `closing?`), copy
  (`after_save` on create reading `@copied_from`; `copy_source_items` takes RedmineUP's rows while
  the source's project still uses it). `checklists_attributes` alias only without
  RedmineUP.
- History: `JournalDetail` property `expert_checklist`, `prop_key` = item id, old/new value =
  snapshot JSON (nil = added/removed). `DetailRenderer` renders those and, once RedmineUP is gone
  from the issue's project (`legacy_live?` false), its `attr/checklist` JSON snapshots (`LegacyDiff`,
  diff by id); RedmineUP drops them where its module is off. `IssuesHelperPatch` wraps
  `details_to_strings` (everything – history, mails, PDF, Atom – goes through it);
  `JournalPatch#visible_details` hides checklist details without the view permission, which also
  keeps those users out of the mail recipients.
- `lib/redmine_expert_checklists/patches/issue_query_patch.rb` + `queries_helper_patch.rb` – column
  `:expert_checklist` (value `ListValue`, `to_s` = RedmineUP's `[+]`/`[-]` export lines), batch
  preload in `IssueQuery#issues`, filters `expert_checklist_status` / `expert_checklist_item` as
  EXISTS subqueries ANDed with `Project.allowed_to_condition` (saved filters run even when not
  offered).
- `lib/redmine_expert_checklists/legacy_import.rb` – RedmineUP import (plain SQL on `checklists`,
  ids preserved, phases items / permissions / settings / queries / modules). While RedmineUP is
  installed it holds the checklists of every project without our module (`legacy_live?`): the
  items step copies those issues again; afterwards only issues without items of ours.
  `:projects` limits items, queries and modules to those projects (switch one at a time, one
  transaction). Modules and queries refuse next to an installed RedmineUP unless it is switchable
  per project (`legacy_switchable?`: its permissions moved out of `issue_tracking` into a module of
  their own, which the module step switches off where ours goes on; global queries only once every
  project is switched) or forced. Admin page `ExpertChecklistImportsController` (`switch_projects`
  for single projects), rake `redmine_expert_checklists:legacy_import` (`PROJECTS=`).
- Templates: `ExpertChecklistTemplate` (`items` text in the editor's paste format, `parse` mirrors
  the script's `parseLines`; `available_for` = project + global, tracker + all, public or own;
  `default_for` = project before global, tracker before all, never someone else's private one) and
  `ExpertChecklistTemplateCategory` (`acts_as_positioned`). Defaults: the form editor
  (`expert_checklist_form_items` – new issue; on a form refresh an empty editor no default filled
  yet gets one, an untouched default is swapped, an edited or emptied one stays – the
  `expert_checklist_template_id` hidden field tells which default the rows came from) and core's
  `controller_issues_new_before_save` hook (`Issue#expert_checklists_apply_default_template` – form
  and REST API create, not mail or copy; no wrapping of `build_new_issue_from_params`).
  Management: `ExpertChecklistTemplatesController` (project templates: manage permission + module;
  global: admins),
  `ExpertChecklistTemplateCategoriesController` (admins; `update` also answers core's
  `positionedItems` reorder), project settings tab via `ProjectsHelperPatch`, plugin settings as
  tabs (`settings/expert_checklists/_general|_templates|_categories`). The import phase `templates`
  matches by project + name (categories by name), no ids preserved.
- `app/controllers/expert_checklist_items_controller.rb` – tick (`PUT .../done`, JSON without a
  `.json` suffix so the session counts) and the REST API; RedmineUP-compatible routes in
  `config/routes.rb` only without RedmineUP.
- `assets/javascripts/expert_checklists.js` – delegated events, labels from the `script.ec-config`
  JSON island, ticks queued per list, editor renumbers rows before submit, re-inits after ajax
  (Redmine's form refresh replaces the editor).

## Conventions

- Code comments English; UI via `config/locales/*.yml` in seven languages (`en`, `de`, `es`, `fr`,
  `it`, `pt`, `pt-BR`): every new or changed key goes into all of them, same order as `en.yml`, same
  `%{…}` placeholders (`test/unit/locale_files_test.rb` enforces it).
- Docs bilingual: `README.md` / `CHANGELOG.md` are authoritative, `README.de.md` /
  `CHANGELOG.de.md` are the German mirror — update both for every user-facing change.
- "expert" (the company) is always lowercase in user-facing text.
- Hash rockets, no frozen-string magic comments, `requires_redmine '5.0'`, plain `def ... end`
  (Ruby 2.7 on Redmine 5.1).
- Prefix every `app/` file, class and table `expert_checklist…`: RedmineUP owns `checklist*`
  basenames and the `checklists` table, and all plugins share one autoload path.
- **Never wrap with `prepend` + `super` what an installed plugin aliases** – use UnboundMethod
  capture (`original = base.instance_method(:m)`, `define_method`). Aliased by plugins installed
  alongside: `IssuesHelper#details_to_strings` (redmine_checklists), `QueriesHelper#column_value`
  (redmine_checklists, redmine_contacts), `Query#sql_for_field` (redmine_checklists),
  `IssueQuery#available_columns` / `#issues` (redmine_agile, redmine_contacts_helpdesk),
  `IssueQuery#initialize_available_filters` (redmine_agile), `IssueQuery#available_filters`
  (redmine_checklists, redmine_contacts_helpdesk), `IssuesController#build_new_issue_from_params`
  (redmine_checklists, redmine_contacts_helpdesk), `Journal#send_notification` and
  `Issue#after_create_from_copy` (redmine_checklists), `Issue#copy_from` (redmine_agile),
  `ProjectsHelper#project_settings_tabs` (several). We wrap none of the four before the last;
  `project_settings_tabs` only by capture (`ProjectsHelperPatch`).
- No inline `<script>`: data crosses as a JSON island, URLs as data attributes.
- Item subjects render with `textilizable(..., :formatting => false)` (escaped text plus Redmine
  links), never through the wiki formatter.
- Clean-room: RedmineUP's code was read for behaviour only; nothing is copied from it.
- Add the next migration number; never edit a shipped migration.

## Tests

```bash
# from the parent repo root
docker-compose -f docker-compose.yml --profile test run --build --rm -e PLUGIN=redmine_expert_checklists redmine-test
```

The dev image has RedmineUP Checklists installed, GitHub CI does not: `test_helper.rb` creates
RedmineUP's `checklists` table when it is missing (outside any transaction), and tests that need
the plugin absent skip. Mail bundling tests switch `ExpertChecklistNotificationJob` to the `:test`
adapter (core mail jobs stay `:inline`) and move time with `travel` / `travel_to`.

## CI

- `.github/workflows/ci.yml` – plugin tests against Redmine 5.1/6.0/6.1/7.0-stable on MariaDB,
  5.1 and 7.0 also on MySQL 8.4 and PostgreSQL 17 (the database starts in a step per matrix entry).
- `.github/workflows/docker-image.yml` – official `redmine:*` images with the plugin mounted and
  migrated; `/login` must answer and the head hook's script and stylesheet must be served.
- `.github/workflows/release.yml` – runs on `vX.Y.Z` tags only, see below.

## Git and releases

Branch as `type/short-desc` (Conventional-Commit types), PR into `main`, CI must pass.
Releases are tag driven: bump `version` in `init.rb` (single source of truth), add the
`## [<version>]` section to `CHANGELOG.md` (and its German mirror), commit, then
`git tag -a vX.Y.Z -m vX.Y.Z && git push origin vX.Y.Z`. `release.yml` verifies that the tag matches
the `init.rb` version, builds the notes from the matching CHANGELOG section and attaches the
`.zip` / `.tar.gz` archives to the GitHub release, then asks the plugin website
(`expertZentrale/redmine-plugins`) to rebuild via the `SITE_DISPATCH_TOKEN` secret (optional).

**Every release must also update `docs/redmine_org/`** (Textile, pasted into
<https://www.redmine.org/plugins/redmine_expert_checklists>): a new
`docs/redmine_org/releases/<version>.textile` (`h3. redmine_expert_checklists <version> — <date>`,
`h4. Added`/`Changed`/`Fixed`, closing with `h4. Upgrade notes`), and `description.textile` /
`installation.textile` when features or steps change. `docs/redmine_org/README.md` is the checklist.

`.github/copilot-instructions.md` mirrors this file — keep both in sync.
