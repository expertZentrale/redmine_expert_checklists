require File.expand_path('../../test_helper', __FILE__)

class LegacyImportTest < ActiveSupport::TestCase
  include ExpertChecklistsTestHelper

  fixtures :projects, :users, :roles, :members, :member_roles, :issues, :issue_statuses,
           :trackers, :projects_trackers, :enumerations, :enabled_modules, :queries

  def setup
    # As without RedmineUP (GitHub CI); tests that need it installed say so.
    RedmineExpertChecklists.stubs(:redmineup_present?).returns(false)
    RedmineExpertChecklists.stubs(:legacy_module).returns(nil)
    ActiveRecord::Base.connection.execute('DELETE FROM checklists')
    ActiveRecord::Base.connection.execute('DELETE FROM checklist_templates')
    ActiveRecord::Base.connection.execute('DELETE FROM checklist_template_categories')
    insert_legacy_item(9001, 1, ' Buy milk ', true, 1)
    insert_legacy_item(9002, 1, 'Shopping', false, 1, true)
    insert_legacy_item(9003, 2, 'Second issue', false, 1)
    insert_legacy_item(9004, 999_999, 'Deleted issue', false, 1)
    insert_legacy_item(9005, 2, '   ', false, 2)
  end

  def import(options = {})
    RedmineExpertChecklists::LegacyImport.new(options)
  end

  # RedmineUP installed; switchable: its permissions in a module of their own.
  def redmineup_installed(switchable = true)
    RedmineExpertChecklists.stubs(:redmineup_present?).returns(true)
    RedmineExpertChecklists.stubs(:legacy_module).returns(switchable ? 'checklists' : 'issue_tracking')
  end

  def test_report_counts_without_writing
    report = import.report
    assert_equal 5, report['legacy_items']
    assert_equal 2, report['legacy_issues']
    assert_equal 1, report['orphan_items']
    assert_equal 1, report['blank_items']
    assert_equal 2, report['issues_to_import']
    assert_equal 0, ExpertChecklistItem.count
  end

  def test_items_keep_their_ids_and_skip_orphans_and_blanks
    result = import.run(%w(items))
    assert_equal({ 'imported' => 3, 'new_ids' => 0, 'replaced' => 0 }, result['items'])
    item = ExpertChecklistItem.find(9001)
    assert_equal ['Buy milk', 1, true, false], [item.subject, item.issue_id, item.is_done, item.is_section]
    assert ExpertChecklistItem.find(9002).is_section?
    assert_nil ExpertChecklistItem.find_by(:id => 9004)
    assert_equal 1, ExpertChecklistItem.where(:issue_id => 2).count
    # New items continue after the imported ids.
    assert_operator ExpertChecklistItem.create!(:issue_id => 3, :subject => 'new').id, :>, 9003
  end

  def test_items_run_again_imports_nothing
    import.run(%w(items))
    assert_equal({ 'imported' => 0, 'new_ids' => 0, 'replaced' => 0 }, import.run(%w(items))['items'])
    assert_equal 3, ExpertChecklistItem.count
  end

  def test_once_redmineup_is_gone_issues_with_items_of_ours_are_skipped
    ExpertChecklistItem.create!(:issue_id => 1, :subject => 'mine')
    import.run(%w(items))
    assert_equal ['mine'], ExpertChecklistItem.where(:issue_id => 1).pluck(:subject)
  end

  def test_colliding_ids_get_new_ones
    ExpertChecklistItem.create!(:id => 9003, :issue_id => 3, :subject => 'mine')
    result = import.run(%w(items))
    assert_equal 1, result['items']['new_ids']
    assert_equal ['Second issue'], ExpertChecklistItem.where(:issue_id => 2).pluck(:subject)
    assert_equal 'mine', ExpertChecklistItem.find(9003).subject
  end

  def test_permissions_follow_the_legacy_ones
    role = Role.find(2)
    role.add_permission!(:view_checklists, :done_checklists)
    assert_equal({ 'roles' => 1 }, import.run(%w(permissions))['permissions'])
    role.reload
    assert role.permissions.include?(:view_expert_checklists)
    assert role.permissions.include?(:done_expert_checklists)
    assert_not role.permissions.include?(:edit_expert_checklists)
  end

  def test_settings_are_mapped
    # Stored the way Redmine stores plugin settings saved from the settings page.
    Setting.where(:name => 'plugin_redmine_checklists').delete_all
    yaml = ActiveSupport::HashWithIndifferentAccess.new(
      'issue_done_ratio' => '1', 'block_issue_closing' => '1', 'save_log' => '1'
    ).to_yaml
    connection = ActiveRecord::Base.connection
    connection.execute("INSERT INTO settings (name, value, updated_on) VALUES " \
                       "('plugin_redmine_checklists', #{connection.quote(yaml)}, CURRENT_TIMESTAMP)")
    with_settings(:notified_events => %w(issue_added issue_updated)) do
      mapped = import.run(%w(settings))['settings']
      assert_equal({ 'notifications' => 'issue_updated', 'done_ratio_from_checklist' => '1',
                     'block_issue_closing' => '1' }, mapped)
    end
    assert RedmineExpertChecklists.setting_on?(:block_issue_closing)
    assert RedmineExpertChecklists.settings['legacy_import_done_at'].present?
  ensure
    Setting.plugin_redmine_expert_checklists = Setting.plugin_redmine_expert_checklists.merge(
      'block_issue_closing' => '0', 'done_ratio_from_checklist' => '0', 'legacy_import_done_at' => ''
    )
  end

  def test_checklist_event_without_issue_updated_means_always
    with_settings(:notified_events => %w(issue_added checklist_updated)) do
      assert_equal 'always', import.report['settings']['notifications']
    end
    with_settings(:notified_events => %w(issue_added)) do
      assert_equal 'never', import.report['settings']['notifications']
    end
  end

  def test_saved_queries_are_converted
    query = IssueQuery.new(:name => 'With checklists', :project_id => 1, :user_id => 2,
                           :column_names => [:subject, :checklist_relations])
    query.filters = { 'status_id' => { :operator => 'o', :values => [''] },
                      'checklists_status' => { :operator => '!', :values => ['1'] },
                      'checklists_item' => { :operator => '~', :values => ['milk'] } }
    query.save!(:validate => false)

    import(:force => true).run(%w(queries))
    query.reload
    assert_equal [:subject, :expert_checklist], query.column_names
    assert_equal({ :operator => '=', :values => ['0'] }, query.filters['expert_checklist_status'].symbolize_keys)
    assert_equal '~', query.filters['expert_checklist_item'][:operator]
    assert_not query.filters.key?('checklists_status')
    assert query.filters.key?('status_id')
  end

  def test_modules_are_enabled_where_issue_tracking_is
    with_settings(:default_projects_modules => %w(issue_tracking wiki)) do
      result = import(:force => true).run(%w(modules))
      assert_operator result['modules']['projects'], :>, 0
      assert Project.find(1).reload.module_enabled?(:expert_checklists)
      assert_include 'expert_checklists', Setting.default_projects_modules
    end
  end

  def test_queries_and_modules_wait_for_redmineup_to_be_removed
    redmineup_installed(false)
    result = import.run(%w(queries modules))
    assert_equal({ 'queries' => 'blocked', 'modules' => 'blocked' }, result)
    assert_not Project.find(1).module_enabled?(:expert_checklists)
  end

  def test_while_redmineup_is_in_use_its_issues_are_copied_again
    redmineup_installed
    ExpertChecklistItem.create!(:issue_id => 1, :subject => 'stale copy')
    result = import.run(%w(items))['items']
    assert_equal 1, result['replaced']
    assert_equal ['Buy milk', 'Shopping'], ExpertChecklistItem.where(:issue_id => 1).order(:position, :id).pluck(:subject)
  end

  def test_projects_with_our_module_keep_their_items
    redmineup_installed
    Project.find(1).enable_module!(:expert_checklists)
    ExpertChecklistItem.create!(:issue_id => 1, :subject => 'mine')
    import.run(%w(items))
    assert_equal ['mine'], ExpertChecklistItem.where(:issue_id => 1).pluck(:subject)
    assert_equal 0, ExpertChecklistItem.where(:issue_id => 2).count
  end

  def test_switching_a_project_touches_only_that_project
    redmineup_installed
    other = Issue.where.not(:project_id => 1).first
    insert_legacy_item(9010, other.id, 'Elsewhere')
    [1, other.project_id].each { |id| EnabledModule.create!(:project_id => id, :name => 'checklists') }
    mine = IssueQuery.new(:name => 'Mine', :project_id => 1, :user_id => 2,
                          :column_names => [:subject, :checklist_relations])
    mine.save!(:validate => false)
    theirs = IssueQuery.new(:name => 'Theirs', :project_id => other.project_id, :user_id => 2,
                            :column_names => [:subject, :checklist_relations])
    theirs.save!(:validate => false)

    with_settings(:default_projects_modules => %w(issue_tracking checklists)) do
      result = import(:projects => [Project.find(1)]).run(RedmineExpertChecklists::LegacyImport::PROJECT_PHASES)
      assert_equal 3, result['items']['imported']
      assert_equal({ 'queries' => 1 }, result['queries'])
      assert_equal({ 'projects' => 1, 'redmineup_off' => 1 }, result['modules'])
      assert_equal %w(issue_tracking checklists), Setting.default_projects_modules
    end
    assert_equal 0, ExpertChecklistItem.where(:issue_id => other.id).count
    assert_equal [:subject, :expert_checklist], mine.reload.column_names
    assert_equal [:subject, :checklist_relations], theirs.reload.column_names
    switched = Project.find(1)
    assert switched.module_enabled?(:expert_checklists)
    assert_not switched.module_enabled?(:checklists)
    assert Project.find(other.project_id).module_enabled?(:checklists)
    assert_not Project.find(other.project_id).module_enabled?(:expert_checklists)
  end

  def test_global_module_step_swaps_the_modules_of_new_projects
    redmineup_installed
    EnabledModule.create!(:project_id => 1, :name => 'checklists')
    with_settings(:default_projects_modules => %w(issue_tracking checklists wiki)) do
      import.run(%w(modules))
      assert_equal %w(issue_tracking wiki expert_checklists), Setting.default_projects_modules
    end
    assert_not Project.find(1).module_enabled?(:checklists)
    assert Project.find(1).module_enabled?(:expert_checklists)
  end

  def test_switching_needs_redmineup_in_a_module_of_its_own
    redmineup_installed(false)
    switch = import(:projects => [Project.find(1)])
    assert switch.switch_blocked?
    result = switch.run(RedmineExpertChecklists::LegacyImport::PROJECT_PHASES)
    assert_equal 'blocked', result['modules']
    assert_equal 'blocked', result['queries']
    assert_not Project.find(1).module_enabled?(:expert_checklists)
  end

  def test_global_queries_wait_until_every_project_is_switched
    redmineup_installed
    assert import.blocked?('queries')
    EnabledModule.where(:name => 'issue_tracking').pluck(:project_id).each do |id|
      EnabledModule.create!(:project_id => id, :name => 'expert_checklists')
    end
    assert_not import.blocked?('queries')
  end

  def test_items_of_reads_redmineup_rows_for_a_copy
    items = RedmineExpertChecklists::LegacyImport.items_of(1)
    assert_equal ['Buy milk', 'Shopping'], items.map(&:subject)
    assert_equal [true, false], items.map(&:is_done)
    assert items.last.is_section?
    assert items.all?(&:new_record?)
    assert_equal ['Second issue'], RedmineExpertChecklists::LegacyImport.items_of(2).map(&:subject)
  end

  def test_a_copy_goes_when_redmineup_emptied_the_checklist
    redmineup_installed
    ExpertChecklistItem.create!(:issue_id => 3, :subject => 'copied before it was emptied')
    assert_equal 1, import.report['issues_to_clear']
    import.run(%w(items))
    assert_equal 0, ExpertChecklistItem.where(:issue_id => 3).count
  end

  def test_switched_projects_keep_items_redmineup_does_not_have
    redmineup_installed
    Project.find(1).enable_module!(:expert_checklists)
    ExpertChecklistItem.create!(:issue_id => 3, :subject => 'mine')
    import.run(%w(items))
    assert_equal ['mine'], ExpertChecklistItem.where(:issue_id => 3).pluck(:subject)
  end

  def test_replace_is_ignored_when_switching_single_projects
    redmineup_installed
    other = Issue.where.not(:project_id => 1).first
    insert_legacy_item(9010, other.id, 'Elsewhere')
    ExpertChecklistItem.create!(:issue_id => other.id, :subject => 'Elsewhere')
    import(:projects => [Project.find(1)], :replace => true).run(%w(items))
    assert_equal ['Elsewhere'], ExpertChecklistItem.where(:issue_id => other.id).pluck(:subject)
  end

  def test_projects_without_issue_tracking_are_refused
    redmineup_installed
    EnabledModule.where(:project_id => 1, :name => 'issue_tracking').delete_all
    switch = import(:projects => [Project.find(1)])
    assert_equal [1], switch.ineligible_projects.map(&:id)
    assert_raise(ArgumentError) { switch.run(RedmineExpertChecklists::LegacyImport::PROJECT_PHASES) }
    assert_equal 0, ExpertChecklistItem.count
  end

  def test_switching_a_project_copies_items_first_whatever_the_phases
    redmineup_installed
    EnabledModule.create!(:project_id => 1, :name => 'checklists')
    result = import(:projects => [Project.find(1)]).run(%w(modules))
    assert_equal %w(items templates modules), result.keys
    assert_equal 3, result['items']['imported']
    assert Project.find(1).module_enabled?(:expert_checklists)
  end

  def test_phases_run_in_their_fixed_order
    redmineup_installed
    result = import(:projects => [Project.find(1)]).run(%w(modules queries items))
    assert_equal %w(items templates queries modules), result.keys
    assert_equal 3, result['items']['imported']
  end

  def test_switched_projects_without_issue_tracking_may_run_again
    redmineup_installed
    Project.find(1).enable_module!(:expert_checklists)
    EnabledModule.create!(:project_id => 1, :name => 'checklists')
    EnabledModule.where(:project_id => 1, :name => 'issue_tracking').delete_all
    switch = import(:projects => [Project.find(1)])
    assert_empty switch.ineligible_projects
    assert_equal 1, switch.run(RedmineExpertChecklists::LegacyImport::PROJECT_PHASES)['modules']['redmineup_off']
    assert_not Project.find(1).module_enabled?(:checklists)
  end

  def test_global_module_step_copies_items_first
    redmineup_installed
    result = import.run(%w(modules))
    assert_equal %w(items templates modules), result.keys
    assert_equal 3, result['items']['imported']
    assert Project.find(1).module_enabled?(:expert_checklists)
  end

  def test_templates_arrive_with_categories_authors_and_visibility
    connection = ActiveRecord::Base.connection
    connection.execute("INSERT INTO checklist_template_categories (id, name, position) VALUES (7, 'Releases', 1)")
    insert_legacy_template(1, nil, 'Global', "-- Prep\r\nTag", :category_id => 7, :is_default => true, :user_id => 3)
    insert_legacy_template(2, 1, 'Bugs', "Reproduce\r\nFix", :is_default => true, :tracker_id => 1,
                           :is_public => false)
    assert_equal 2, import.report['legacy_templates']
    assert_equal 1, import.report['legacy_default_templates']

    result = import.run(%w(templates))['templates']
    assert_equal({ 'templates' => 2, 'replaced' => 0, 'categories' => 1 }, result)
    global = ExpertChecklistTemplate.find_by(:name => 'Global')
    assert_nil global.project_id
    assert_not global.is_default?, 'RedmineUP never applied global defaults'
    assert_equal "-- Prep\nTag", global.items
    assert_equal ['Releases', 3, true], [global.category.name, global.author_id, global.is_public?]
    bugs = ExpertChecklistTemplate.find_by(:name => 'Bugs')
    assert_equal [1, 1, true, false], [bugs.project_id, bugs.tracker_id, bugs.is_default?, bugs.is_public?]
  end

  def test_templates_run_again_add_nothing_once_redmineup_is_gone
    insert_legacy_template(1, nil, 'Global', 'Tag')
    insert_legacy_template(2, 1, 'Bugs', 'Fix')
    import.run(%w(templates))
    assert_equal({ 'templates' => 0, 'replaced' => 0, 'categories' => 0 }, import.run(%w(templates))['templates'])
    assert_equal 2, ExpertChecklistTemplate.count
  end

  def test_templates_of_projects_still_on_redmineup_are_copied_again
    redmineup_installed
    insert_legacy_template(2, 1, 'Bugs', 'Fix')
    import.run(%w(templates))
    ActiveRecord::Base.connection.execute("UPDATE checklist_templates SET template_items = 'Fix\nTest' WHERE id = 2")
    result = import.run(%w(templates))['templates']
    assert_equal 1, result['replaced']
    assert_equal "Fix\nTest", ExpertChecklistTemplate.find_by(:name => 'Bugs').items
  end

  def test_switched_projects_keep_their_templates
    redmineup_installed
    Project.find(1).enable_module!(:expert_checklists)
    add_template(:name => 'Mine')
    insert_legacy_template(2, 1, 'Bugs', 'Fix')
    import.run(%w(templates))
    assert_equal ['Mine'], ExpertChecklistTemplate.where(:project_id => 1).pluck(:name)
  end

  def test_switching_a_project_takes_its_templates_and_the_global_ones
    redmineup_installed
    other = Issue.where.not(:project_id => 1).first.project_id
    insert_legacy_template(1, nil, 'Global', 'Tag')
    insert_legacy_template(2, 1, 'Mine', 'Fix')
    insert_legacy_template(3, other, 'Theirs', 'Fix')
    import(:projects => [Project.find(1)]).run(RedmineExpertChecklists::LegacyImport::PROJECT_PHASES)
    assert_equal %w(Global Mine), ExpertChecklistTemplate.order(:name).pluck(:name)
  end

  def test_template_permission_follows_the_legacy_one
    role = Role.find(2)
    role.add_permission!(:manage_checklist_templates)
    import.run(%w(permissions))
    assert role.reload.permissions.include?(:manage_expert_checklist_templates)
  end

  # PostgreSQL keeps a sequence that inserting rows with their own ids does not
  # move; put it behind the kept ids, as an import leaves it.
  def test_new_ids_do_not_hit_kept_ones
    ExpertChecklistItem.create!(:id => 9003, :issue_id => 3, :subject => 'mine')
    connection = ActiveRecord::Base.connection
    if connection.adapter_name =~ /postg/i
      connection.execute("SELECT setval(pg_get_serial_sequence('expert_checklist_items', 'id'), 9001)")
    end
    assert_equal 1, import.run(%w(items))['items']['new_ids']
    assert_equal ['Second issue'], ExpertChecklistItem.where(:issue_id => 2).pluck(:subject)
  end
end
