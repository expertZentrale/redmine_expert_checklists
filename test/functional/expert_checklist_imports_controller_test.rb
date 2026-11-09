require File.expand_path('../../test_helper', __FILE__)

class ExpertChecklistImportsControllerTest < Redmine::ControllerTest
  include ExpertChecklistsTestHelper

  fixtures :projects, :users, :roles, :members, :member_roles, :issues, :issue_statuses,
           :trackers, :projects_trackers, :enumerations, :enabled_modules

  def setup
    ActiveRecord::Base.connection.execute('DELETE FROM checklists')
    insert_legacy_item(9001, 1, 'Buy milk')
  end

  def test_admin_sees_the_dry_run
    @request.session[:user_id] = 1
    get :show
    assert_response :success
    assert_select 'input[name="phases[]"][value=items]'
    assert_equal 0, ExpertChecklistItem.count
  end

  def test_admin_runs_the_import
    @request.session[:user_id] = 1
    post :create, :params => { :phases => %w(items) }
    assert_redirected_to '/expert_checklists/legacy_import'
    assert_equal 'Buy milk', ExpertChecklistItem.find(9001).subject
  end

  def test_non_admins_are_refused
    @request.session[:user_id] = 2
    get :show
    assert_response :forbidden
  end

  def test_the_page_offers_projects_to_switch
    RedmineExpertChecklists.stubs(:redmineup_present?).returns(true)
    RedmineExpertChecklists.stubs(:legacy_module).returns('checklists')
    @request.session[:user_id] = 1
    get :show
    assert_response :success
    assert_select 'form#expert-checklist-switch select[name=?] option[value="1"]', 'project_ids[]'
    # Next to RedmineUP, switching every project at once is offered but not preselected.
    assert_select 'input#phase_modules:not([checked])'
  end

  def test_admin_switches_a_project
    RedmineExpertChecklists.stubs(:redmineup_present?).returns(true)
    RedmineExpertChecklists.stubs(:legacy_module).returns('checklists')
    EnabledModule.create!(:project_id => 1, :name => 'checklists')
    @request.session[:user_id] = 1
    post :switch_projects, :params => { :project_ids => ['1'] }
    assert_redirected_to '/expert_checklists/legacy_import'
    assert_equal 'Buy milk', ExpertChecklistItem.find(9001).subject
    project = Project.find(1)
    assert project.module_enabled?(:expert_checklists)
    assert_not project.module_enabled?(:checklists)
  end

  def test_switching_is_refused_while_redmineup_cannot_be_switched_off
    RedmineExpertChecklists.stubs(:redmineup_present?).returns(true)
    RedmineExpertChecklists.stubs(:legacy_module).returns('issue_tracking')
    @request.session[:user_id] = 1
    post :switch_projects, :params => { :project_ids => ['1'] }
    assert_redirected_to '/expert_checklists/legacy_import'
    assert flash[:error].present?
    assert_not Project.find(1).module_enabled?(:expert_checklists)
    assert_equal 0, ExpertChecklistItem.count
  end

  def test_non_admins_cannot_switch_projects
    @request.session[:user_id] = 2
    post :switch_projects, :params => { :project_ids => ['1'] }
    assert_response :forbidden
    assert_not Project.find(1).module_enabled?(:expert_checklists)
  end

  def test_projects_without_issue_tracking_are_not_switched
    RedmineExpertChecklists.stubs(:redmineup_present?).returns(true)
    RedmineExpertChecklists.stubs(:legacy_module).returns('checklists')
    EnabledModule.where(:project_id => 1, :name => 'issue_tracking').delete_all
    @request.session[:user_id] = 1
    post :switch_projects, :params => { :project_ids => ['1'] }
    assert_redirected_to '/expert_checklists/legacy_import'
    assert_include 'eCookbook', flash[:error]
    assert_equal 0, ExpertChecklistItem.count
  end
end

