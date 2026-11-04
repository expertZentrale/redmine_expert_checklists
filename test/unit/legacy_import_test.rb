require File.expand_path('../../test_helper', __FILE__)

class LegacyImportTest < ActiveSupport::TestCase
  include ExpertChecklistsTestHelper

  fixtures :projects, :users, :roles, :members, :member_roles, :issues, :issue_statuses,
           :trackers, :projects_trackers, :enumerations, :enabled_modules, :queries

  def setup
    ActiveRecord::Base.connection.execute('DELETE FROM checklists')
    insert_legacy_item(9001, 1, ' Buy milk ', true, 1)
    insert_legacy_item(9002, 1, 'Shopping', false, 1, true)
    insert_legacy_item(9003, 2, 'Second issue', false, 1)
    insert_legacy_item(9004, 999_999, 'Deleted issue', false, 1)
    insert_legacy_item(9005, 2, '   ', false, 2)
  end

  def import(options = {})
    RedmineExpertChecklists::LegacyImport.new(options)
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
    assert_equal({ 'imported' => 3, 'new_ids' => 0 }, result['items'])
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
    assert_equal({ 'imported' => 0, 'new_ids' => 0 }, import.run(%w(items))['items'])
    assert_equal 3, ExpertChecklistItem.count
  end

  def test_issues_that_already_have_items_of_ours_are_skipped
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
    RedmineExpertChecklists.stubs(:redmineup_present?).returns(true)
    result = import.run(%w(queries modules))
    assert_equal({ 'queries' => 'blocked', 'modules' => 'blocked' }, result)
    assert_not Project.find(1).module_enabled?(:expert_checklists)
  end
end
