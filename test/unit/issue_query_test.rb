require File.expand_path('../../test_helper', __FILE__)

class ExpertChecklistsIssueQueryTest < ActiveSupport::TestCase
  include ExpertChecklistsTestHelper

  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles, :issues,
           :issue_statuses, :trackers, :projects_trackers, :enumerations, :enabled_modules,
           :queries, :versions, :issue_categories

  def setup
    enable_checklists
    User.current = User.find(2)
    add_items(Issue.find(1), '[x] done one', 'open one')
    add_items(Issue.find(2), '[x] all done')
    add_items(Issue.find(3), '-- just a section')
  end

  def teardown
    User.current = nil
  end

  def ids_for(field, operator, values = nil)
    query = IssueQuery.new(:name => '_', :project => Project.find(1))
    query.add_filter(field, operator, values)
    query.issues.map(&:id).sort
  end

  def test_filters_and_column_are_offered_with_the_module
    query = IssueQuery.new(:project => Project.find(1))
    assert query.available_filters.key?('expert_checklist_status')
    assert query.available_filters.key?('expert_checklist_item')
    assert query.available_columns.any? { |column| column.name == :expert_checklist }

    Project.find(1).disable_module!(:expert_checklists)
    query = IssueQuery.new(:project => Project.find(1).reload)
    assert_not query.available_filters.key?('expert_checklist_status')
  end

  def test_status_filter
    assert_equal [1], ids_for('expert_checklist_status', '=', ['0'])
    assert_equal [1, 2], ids_for('expert_checklist_status', '=', ['1'])
    assert_equal [1, 2], ids_for('expert_checklist_status', '*')
    assert_not_include 1, ids_for('expert_checklist_status', '!', ['0'])
    assert_include 2, ids_for('expert_checklist_status', '!', ['0'])
    assert_include 3, ids_for('expert_checklist_status', '!*')
  end

  def test_item_filter
    assert_equal [1], ids_for('expert_checklist_item', '~', ['open'])
    assert_equal [2], ids_for('expert_checklist_item', '=', ['all done'])
    assert_equal [1, 2, 3], ids_for('expert_checklist_item', '*')
    assert_not_include 1, ids_for('expert_checklist_item', '!~', ['open'])
  end

  # A saved query keeps its filter after the user lost the permission (the
  # filter is then no longer offered); it must not reveal anything.
  def test_saved_filter_respects_the_permission
    revoke_checklists
    query = IssueQuery.new(:name => '_', :project => Project.find(1))
    query.filters = { 'expert_checklist_status' => { :operator => '*', :values => [''] } }
    assert_equal [], query.issues.map(&:id)
  end

  def test_filter_with_the_tick_permission_only
    Role.find(1).remove_permission!(:view_expert_checklists)
    Role.find(1).remove_permission!(:edit_expert_checklists)
    assert_equal [1, 2, 3], ids_for('expert_checklist_item', '*')
  end

  def test_column_value_and_export_format
    query = IssueQuery.new(:project => Project.find(1), :column_names => [:subject, :expert_checklist])
    issue = query.issues.detect { |i| i.id == 1 }
    value = issue.expert_checklist
    assert_kind_of RedmineExpertChecklists::ListValue, value
    assert_equal "[+] done one\r\n[-] open one", value.to_s
    assert_nil Issue.find(4).expert_checklist
  end

  def test_preload_takes_one_query
    query = IssueQuery.new(:project => Project.find(1), :column_names => [:subject, :expert_checklist])
    issues = query.issues
    count = 0
    counter = lambda { |*, payload| count += 1 if payload[:sql] =~ /expert_checklist_items/ }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
      issues.each(&:expert_checklist)
    end
    assert_equal 0, count
  end
end
