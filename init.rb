# Redmine expert Checklists Plugin
#
# Copyright (C) 2026 Dennis Buehring
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version. See LICENSE for the full text.
#
# Checklists on issues: items and sections, ticking on the issue page, editing
# in the issue form, history, bundled notification mails, REST API, issue list
# column and filters, and an import from RedmineUP Checklists.
#
# Naming note: "expert" is the company name and is always written with a
# lowercase "e" in user-facing text. Code identifiers keep their normal casing.

require 'redmine'

require File.expand_path('../lib/redmine_expert_checklists', __FILE__)
require File.expand_path('../lib/redmine_expert_checklists/legacy_diff', __FILE__)
require File.expand_path('../lib/redmine_expert_checklists/journalizer', __FILE__)
require File.expand_path('../lib/redmine_expert_checklists/recorder', __FILE__)
require File.expand_path('../lib/redmine_expert_checklists/detail_renderer', __FILE__)
require File.expand_path('../lib/redmine_expert_checklists/list_value', __FILE__)
require File.expand_path('../lib/redmine_expert_checklists/legacy_import', __FILE__)
require File.expand_path('../lib/redmine_expert_checklists/hooks', __FILE__)
require File.expand_path('../lib/redmine_expert_checklists/patches/issue_patch', __FILE__)
require File.expand_path('../lib/redmine_expert_checklists/patches/journal_patch', __FILE__)
require File.expand_path('../lib/redmine_expert_checklists/patches/issues_helper_patch', __FILE__)
require File.expand_path('../lib/redmine_expert_checklists/patches/issue_query_patch', __FILE__)
require File.expand_path('../lib/redmine_expert_checklists/patches/queries_helper_patch', __FILE__)
require File.expand_path('../lib/redmine_expert_checklists/patches/projects_helper_patch', __FILE__)

Redmine::Plugin.register :redmine_expert_checklists do
  name 'Redmine expert Checklists'
  author 'Dennis Buehring'
  description 'Checklists on issues: tick items on the issue page, edit them in the issue form, see every change in the history and get one bundled mail instead of one per click. Templates, REST API, issue list column and filters, import from RedmineUP Checklists.'
  version '0.3.0'
  url 'https://github.com/expertZentrale/redmine_expert_checklists'
  requires_redmine :version_or_higher => '5.0'

  # All values are strings ('0'/'1' for booleans), like the other expert plugins.
  settings :partial => 'settings/expert_checklists_settings',
           :default => {
             # issue_updated: mail checklist changes when Redmine mails issue
             # updates; always / never: regardless of that event.
             'notifications' => 'issue_updated',
             # "% done" follows the share of ticked items (done ratio must be an
             # issue field, see Administration » Settings » Issue tracking).
             'done_ratio_from_checklist' => '0',
             # An issue with open items cannot be closed.
             'block_issue_closing' => '0',
             # Set by the RedmineUP import (time of the last run).
             'legacy_import_done_at' => ''
           }

  # Off in every project until switched on (or until the RedmineUP import
  # enables it where issue tracking is on), so the plugin can be installed next
  # to RedmineUP Checklists without showing a second checklist anywhere.
  project_module :expert_checklists do
    permission :view_expert_checklists,
               { :expert_checklist_items => [:index, :show] },
               :read => true
    # Ticking and editing include viewing (RedmineExpertChecklists.viewable?),
    # so both also allow reading the API.
    permission :done_expert_checklists,
               { :expert_checklist_items => [:index, :show, :done] }
    permission :edit_expert_checklists,
               { :expert_checklist_items => [:index, :show, :create, :update, :destroy, :done] }
    # Templates of the project (settings tab); global ones are for admins.
    permission :manage_expert_checklist_templates,
               { :expert_checklist_templates => [:new, :create, :edit, :update, :destroy] }
  end

  menu_options = { :caption => :label_expert_checklists }
  if Redmine::VERSION::MAJOR >= 6
    menu_options[:icon] = 'checked'
    menu_options[:html] = { :class => 'icon' }
  else
    menu_options[:html] = { :class => 'icon icon-checked' }
  end
  menu :admin_menu, :redmine_expert_checklists,
       { :controller => 'settings', :action => 'plugin', :id => 'redmine_expert_checklists' },
       menu_options
end

# Redmine runs init.rb inside a to_prepare callback (again on every dev reload),
# so patch directly; every apply! guards against patching twice.
RedmineExpertChecklists::Patches::IssuePatch.apply!
RedmineExpertChecklists::Patches::JournalPatch.apply!
RedmineExpertChecklists::Patches::IssuesHelperPatch.apply!
RedmineExpertChecklists::Patches::IssueQueryPatch.apply!
RedmineExpertChecklists::Patches::QueriesHelperPatch.apply!
RedmineExpertChecklists::Patches::ProjectsHelperPatch.apply!
IssuesController.send(:helper, :expert_checklists)
# Project settings tab and plugin settings tabs list templates.
ProjectsController.send(:helper, :expert_checklists)
SettingsController.send(:helper, :expert_checklists)
