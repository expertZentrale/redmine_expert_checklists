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
end
