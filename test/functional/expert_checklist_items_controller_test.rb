require File.expand_path('../../test_helper', __FILE__)

class ExpertChecklistItemsControllerTest < Redmine::ControllerTest
  include ExpertChecklistsTestHelper

  fixtures :projects, :users, :email_addresses, :user_preferences, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers, :projects_trackers, :enumerations,
           :enabled_modules, :journals, :journal_details, :watchers

  def setup
    enable_checklists
    use_test_job_adapter
    @issue = Issue.find(1)
    @items = add_items(@issue, '-- Prep', 'Buy milk', 'Bake bread')
    @request.session[:user_id] = 2
    ActionMailer::Base.deliveries.clear
  end

  def teardown
    restore_job_adapter
  end

  def put_done(item, done = '1')
    @request.accept = 'application/json'
    put :done, :params => { :id => item.id, :is_done => done }
  end

  def test_done_ticks_the_item_and_answers_with_progress
    put_done(@items[1])
    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal true, json['is_done']
    assert_equal 1, json['done']
    assert_equal 2, json['total']
    assert json.key?('lock_version')
    assert @items[1].reload.is_done?
    assert_empty ActionMailer::Base.deliveries
  end

  def test_done_with_done_permission_only
    Role.find(1).remove_permission!(:edit_expert_checklists)
    put_done(@items[1])
    assert_response :success
  end

  def test_done_is_denied_with_view_permission_only
    Role.find(1).remove_permission!(:edit_expert_checklists)
    Role.find(1).remove_permission!(:done_expert_checklists)
    put_done(@items[1])
    assert_response :forbidden
    assert_not @items[1].reload.is_done?
  end

  def test_done_is_denied_while_the_module_is_off
    Project.find(1).disable_module!(:expert_checklists)
    put_done(@items[1])
    assert_response :forbidden
  end

  def test_sections_cannot_be_ticked
    put_done(@items[0])
    assert_response 422
  end

  def test_done_stays_fast
    queries = 0
    counter = lambda do |*, payload|
      queries += 1 unless %w(SCHEMA TRANSACTION CACHE).include?(payload[:name]) || payload[:cached]
    end
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { put_done(@items[1]) }
    assert_response :success
    assert_operator queries, :<=, 45, "#{queries} SQL statements for one tick"
  end
end
