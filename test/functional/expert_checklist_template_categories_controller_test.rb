require File.expand_path('../../test_helper', __FILE__)

class ExpertChecklistTemplateCategoriesControllerTest < Redmine::ControllerTest
  include ExpertChecklistsTestHelper

  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles, :enabled_modules

  def test_admin_manages_categories
    @request.session[:user_id] = 1
    post :create, :params => { :expert_checklist_template_category => { :name => 'Releases' } }
    assert_redirected_to '/settings/plugin/redmine_expert_checklists?tab=categories'
    category = ExpertChecklistTemplateCategory.find_by(:name => 'Releases')

    patch :update, :params => { :id => category.id, :expert_checklist_template_category => { :name => 'Release' } }
    assert_equal 'Release', category.reload.name

    template = add_template(:category_id => category.id)
    delete :destroy, :params => { :id => category.id }
    assert_nil ExpertChecklistTemplateCategory.find_by(:id => category.id)
    assert_nil template.reload.category_id
  end

  def test_reorder_by_drag_and_drop
    first = ExpertChecklistTemplateCategory.create!(:name => 'First')
    second = ExpertChecklistTemplateCategory.create!(:name => 'Second')
    @request.session[:user_id] = 1
    put :update, :params => { :id => second.id, :expert_checklist_template_category => { :position => 1 },
                              :format => 'js' }, :xhr => true
    assert_response :success
    assert_equal [second.id, first.id], ExpertChecklistTemplateCategory.sorted.pluck(:id)
  end

  def test_non_admins_are_refused
    @request.session[:user_id] = 2
    get :new
    assert_response :forbidden
  end
end
