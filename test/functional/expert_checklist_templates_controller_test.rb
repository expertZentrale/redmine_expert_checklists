require File.expand_path('../../test_helper', __FILE__)

class ExpertChecklistTemplatesControllerTest < Redmine::ControllerTest
  include ExpertChecklistsTestHelper

  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles, :issues, :issue_statuses,
           :trackers, :projects_trackers, :enumerations, :enabled_modules

  def setup
    @project = enable_checklists
    Role.find(1).add_permission!(:manage_expert_checklist_templates)
  end

  def template_params(attributes = {})
    { :name => 'Release', :items => "-- Prep\nTag\nAnnounce", :tracker_id => '', :is_public => '1',
      :is_default => '0' }.merge(attributes)
  end

  def test_manager_creates_a_project_template
    @request.session[:user_id] = 2
    get :new, :params => { :project_id => 'ecookbook' }
    assert_response :success
    assert_select 'textarea[name=?]', 'expert_checklist_template[items]'
    assert_select 'select[name=?] option[value="1"]', 'expert_checklist_template[tracker_id]'

    post :create, :params => { :project_id => 'ecookbook', :expert_checklist_template => template_params }
    assert_redirected_to '/projects/ecookbook/settings/expert_checklist_templates'
    template = ExpertChecklistTemplate.order(:id).last
    assert_equal [1, 2, 'Release', 3], [template.project_id, template.author_id, template.name, template.rows.size]
  end

  def test_invalid_template_shows_the_form_again
    @request.session[:user_id] = 2
    post :create, :params => { :project_id => 'ecookbook', :expert_checklist_template => template_params(:items => '') }
    assert_response :success
    assert_select '#errorExplanation'
    assert_equal 0, ExpertChecklistTemplate.count
  end

  def test_project_templates_need_the_permission_and_the_module
    @request.session[:user_id] = 3
    get :new, :params => { :project_id => 'ecookbook' }
    assert_response :forbidden

    @request.session[:user_id] = 2
    @project.disable_module!(:expert_checklists)
    get :new, :params => { :project_id => 'ecookbook' }
    assert_response :forbidden
  end

  def test_global_templates_are_for_admins
    @request.session[:user_id] = 2
    get :new
    assert_response :forbidden

    @request.session[:user_id] = 1
    post :create, :params => { :expert_checklist_template => template_params(:is_default => '1') }
    assert_redirected_to '/settings/plugin/redmine_expert_checklists?tab=templates'
    template = ExpertChecklistTemplate.order(:id).last
    assert_nil template.project_id
    assert template.is_default?
  end

  def test_update_and_destroy
    template = add_template(:name => 'Old')
    @request.session[:user_id] = 2
    patch :update, :params => { :id => template.id, :expert_checklist_template => { :name => 'New' } }
    assert_redirected_to '/projects/ecookbook/settings/expert_checklist_templates'
    assert_equal 'New', template.reload.name

    delete :destroy, :params => { :id => template.id }
    assert_redirected_to '/projects/ecookbook/settings/expert_checklist_templates'
    assert_nil ExpertChecklistTemplate.find_by(:id => template.id)
  end

  def test_private_template_of_another_user_only_for_admins
    template = add_template(:author_id => 3, :is_public => false)
    @request.session[:user_id] = 2
    get :edit, :params => { :id => template.id }
    assert_response :forbidden

    @request.session[:user_id] = 1
    get :edit, :params => { :id => template.id }
    assert_response :success
  end
end
