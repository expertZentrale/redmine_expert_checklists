> 🇬🇧 English version · [Deutsche Version](README.de.md)

# Redmine expert Checklists

Checklists on Redmine issues: tick items right on the issue page, edit the list in the issue
form, and find every change in the issue history. Quick ticks by one person are bundled into
**one history entry and one mail**, sent in the background, so a click answers at once instead of
waiting for a mail per watcher. Includes a REST API, an issue list column with filters, and an
import from RedmineUP Checklists that keeps its history readable.
Works on **Redmine 5.1, 6.0, 6.1 and 7.0**.

## What it does

- **Issue page.** A checklist block under the description, with sections, progress (`3/5`) and
  "Hide done". Ticking saves immediately; the edit form on the same page stays in step, so saving
  it afterwards neither reverts the tick nor fails as changed by someone else.
- **Issue form.** Add, rename, tick, remove and reorder items while editing the issue: Enter adds
  the next item, drag the handle or press Alt+Up/Down to move one, paste several lines to add one
  item per line (`-- ` starts a section, `[x] ` marks an item done). Copying an issue copies its
  checklist; so do bulk copy, project copy and copied subtasks.
- **History.** One line per changed item ("Checklist item *Buy milk* done"). Reordering alone
  writes no history.
- **Mails.** See [History and mails](#history-and-mails).
- **% Done from the checklist** (optional): the share of ticked items, rounded down to tens.
- **Block closing** (optional): an issue with open items cannot be set to a closed status.
- **Issue list.** A "Checklist" column (also in CSV and PDF exports, as `[+] done` / `[-] open`
  lines) and two filters: by item state (has open / done items, has a checklist at all) and by
  item text.
- **REST API.** See [REST API](#rest-api).
- **Import from RedmineUP Checklists.** See [Moving from RedmineUP Checklists](#moving-from-redmineup-checklists).

Item texts are plain text; issue references like `#123` become links.

## History and mails

A tick on the issue page (and every REST API change) is written to the issue history at once,
but the mail waits. Further ticks by the same person within **60 seconds** go into the same history
entry, and the mail goes out once nobody has ticked for 60 seconds. Ticking an item and unticking
it again leaves no history entry and sends no mail. A bundle closes after ten minutes at the latest,
and as soon as someone else writes to the issue.

The mail is Redmine's own "issue updated" notification, so recipients, mail preferences and
private notes work as for any other change. Users without any of the checklist permissions are
not mailed about checklist changes and do not see them in the history. A % Done the checklist
changed is an ordinary issue field and shows like any other change.

Checklist changes saved **with the issue form** are part of that edit: they go into its history
entry and its mail, right away.

The pending mails are kept in a table, not only in memory. If Redmine restarts within the minute,
the next checklist change anywhere sends what was left over. To be independent of that, an
external job can call `POST /expert_checklists/notifications/flush.json` with an administrator's
API key. If handing a mail to Redmine fails (database or job queue unavailable), it is tried again
with growing gaps for up to a day, then dropped with an error in the log.

Setting *Mails for checklist changes*:

| Value | Meaning |
|---|---|
| Like issue updates (default) | Mailed when Redmine mails issue updates (*Administration » Settings » Email notifications*, "Issue updated") |
| Always | Mailed even when Redmine does not mail issue updates |
| Never | No mails for checklist changes; form edits with other changes are still mailed |

## Permissions

Everything is behind the project module **expert Checklists**. While it is off in a project, the
plugin shows nothing there and refuses its API.

| Permission | Allows |
|---|---|
| View checklists | See the checklist, its history, the list column and filters; read the API |
| Tick checklist items | Everything "View checklists" allows, plus ticking and unticking items on the issue page |
| Edit checklists | Everything above, plus adding, renaming, reordering and deleting items in the issue form and through the API |

## Issue list

The column is not sortable or groupable. Filters:

| Filter | Operators |
|---|---|
| Checklist items | *is* open / done (has at least one such item), *is not*, *any* (has a checklist), *none* |
| Checklist item text | Redmine's text operators (contains, starts with, is, ...); "does not contain" also matches issues without a checklist |

Sections count for neither progress nor the state filter.

## REST API

| Request | Path |
|---|---|
| List an issue's items | `GET /issues/:issue_id/expert_checklist_items.json` |
| Add an item | `POST /issues/:issue_id/expert_checklist_items.json` |
| Show / change / delete an item | `GET` / `PUT` / `DELETE /expert_checklist_items/:id.json` |
| Tick / untick | `PUT /expert_checklist_items/:id/done.json` with `is_done=1` / `0` |

Payload root `checklist`, fields `id`, `issue_id`, `subject`, `is_done`, `position`, `is_section`,
`created_at`, `updated_at` (XML works too):

```bash
curl -X POST -H "X-Redmine-API-Key: $KEY" -H 'Content-Type: application/json' \
     -d '{"checklist": {"subject": "Order parts"}}' \
     https://redmine.example/issues/42/expert_checklist_items.json
```

The issue API accepts the whole list as `issue[expert_checklist_items_attributes]` (an array of
`{id, subject, is_done, is_section, _destroy}`; positions follow the order).

**Clients written for RedmineUP Checklists keep working:** once RedmineUP Checklists is removed,
the plugin also answers its paths (`/issues/:id/checklists`, `/checklists/:id`) with the same root
keys and fields, and accepts `issue[checklists_attributes]`.

## Moving from RedmineUP Checklists

Both plugins can be installed side by side. Ours stays invisible until its project module is
switched on, so the switch can be prepared and rehearsed. Projects change over all at once (below)
or [one at a time](#project-by-project).

1. Install this plugin next to RedmineUP Checklists and run the migrations.
2. Open *Administration » expert Checklists » Open the import*. The page shows what it found
   (items, issues, roles, saved queries, projects) without writing anything. Checklists,
   permissions and settings can already be imported here to try it out.
3. Take a database backup, then remove `plugins/redmine_checklists` and restart. **Do not** run
   `rake redmine:plugins:migrate NAME=redmine_checklists VERSION=0`: that drops RedmineUP's
   tables, and with them the data to import.
4. Run the import with all steps. Each step can run again.

| Step | What it does |
|---|---|
| Checklists | Copies the items **with the same ids**. While RedmineUP is installed, every issue of a project without our module is copied again, replacing an earlier copy, and a copy whose RedmineUP checklist has since been emptied goes (RedmineUP is still in use there); otherwise only issues without a checklist of ours. Items of deleted issues and empty items are skipped; texts are cut to 1000 characters. |
| Permissions | Every role that may view, tick or edit RedmineUP checklists gets the matching permission. |
| Settings | Done ratio and block-closing take RedmineUP's values; the mail setting follows its "Checklist updated" notification event. |
| Saved queries | RedmineUP's checklist column and filters in saved issue queries are replaced by ours. Queries that kept the old filter would fail once RedmineUP is gone. |
| Project module | Switches *expert Checklists* on in every project that uses issue tracking, and for new projects. Where RedmineUP has a project module of its own (see below), that one goes off. |

RedmineUP's own history entries keep rendering as readable lines ("Checklist item *X* done").
For large installations the same import runs as a rake task:

```bash
bundle exec rake redmine_expert_checklists:legacy_import DRY_RUN=1 RAILS_ENV=production
bundle exec rake redmine_expert_checklists:legacy_import RAILS_ENV=production
```

### Project by project

To move single projects while RedmineUP stays installed for the others, RedmineUP must be
switchable per project. Out of the box it is not: its permissions belong to the *Issue tracking*
module. Prepare it once:

1. In `plugins/redmine_checklists/init.rb`, put the permissions into a module of their own:
   `map.project_module :checklists do |map|` instead of `:issue_tracking`.
2. Switch that module on in every project that uses issue tracking, and for new projects
   (*Administration » Settings » Projects*), so nothing changes for anyone yet.
3. RedmineUP does a few things without asking for a permission: blocking the close, recalculating
   the done ratio after an edit, copying items with an issue, and its issue list column. Guard
   them with `project.module_enabled?(:checklists)` as well (`need_to_block_issue_closing?`,
   `controller_issues_edit_after_save`, `after_create_from_copy`, `checklist_relations`);
   otherwise its frozen items keep acting in switched projects.

The import page then shows *Switch project by project*:

1. Import *Permissions* and *Settings* first; they apply to all projects.
2. Choose projects and switch them. For each one, in a single transaction, this copies the
   checklists of its issues again, converts the project's saved queries, switches *expert
   Checklists* on and RedmineUP's module off. As a rake task:
   `rake redmine_expert_checklists:legacy_import PROJECTS=one,two RAILS_ENV=production`.
3. Once every project is switched, convert the remaining saved queries (those without a project)
   and remove RedmineUP; the import does not need to run again.

While both are in use:

- RedmineUP's own history entries render in switched projects too.
- Copying an issue from a project still on RedmineUP into a switched one takes RedmineUP's
  items. The other way round, RedmineUP copies its items as they were at the switch.
- RedmineUP's issue list filters still search all of its items, including the frozen ones of
  switched projects. Its REST paths refuse issues of switched projects; use
  `/issues/:id/expert_checklist_items` there.
- To switch a project back, turn RedmineUP's module on and ours off: RedmineUP shows its items as
  they were at the switch, and a later switch copies them again.

Differences to RedmineUP Checklists:

- The issue form editor needs *Edit checklists*; *Tick checklist items* alone ticks on the issue
  page only.
- Blocking the close only applies to the change to a closed status; notes on an issue that is
  already closed still work.
- Templates and the checklist custom field are not part of this version yet. Their data stays in
  RedmineUP's tables until a later version imports it.
- RedmineUP Agile boards stop showing checklists on cards; boards of redmine_expert_agile can show
  the "Checklist" column.

## Languages

The user interface ships in English, German, Spanish, French, Italian and Portuguese (`en`, `de`,
`es`, `fr`, `it`, `pt`, `pt-BR`). Redmine shows each user the language set in their account, or the
default language under *Administration » Settings » Display*; for any other language it falls back
to English. This documentation is kept in English and German.

Corrections from native speakers are welcome as a pull request on `config/locales/<language>.yml`.
`test/unit/locale_files_test.rb` checks that every language has every key of `en.yml`, in the same
order and with the same `%{…}` placeholders.

## Installation

```bash
cd /path/to/redmine/plugins
git clone https://github.com/expertZentrale/redmine_expert_checklists.git
cd ..
bundle exec rake redmine:plugins:migrate NAME=redmine_expert_checklists RAILS_ENV=production
# restart Redmine
```

Then switch the **expert Checklists** module on in the projects that should use it (or use the
import, which does that) and grant the permissions to the roles.

## Tests

```bash
bundle exec rake redmine:plugins:test NAME=redmine_expert_checklists RAILS_ENV=test
```

CI runs them against Redmine 5.1, 6.0, 6.1 and 7.0 on MariaDB, against 5.1 and 7.0 on MySQL and
PostgreSQL as well, and starts the official Redmine Docker images with the plugin mounted.

## License

GNU General Public License v2 or later, see [LICENSE](LICENSE).
