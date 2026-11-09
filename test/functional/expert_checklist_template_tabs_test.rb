require File.expand_path('../../test_helper', __FILE__)

# The places templates are listed: the project settings tab and the plugin
# settings tabs.
class ExpertChecklistProjectTemplatesTabTest < Redmine::ControllerTest
  include ExpertChecklistsTestHelper
  tests ProjectsController

  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles, :issues, :issue_statuses,
           :trackers, :projects_trackers, :enumerations, :enabled_modules

  def setup
    enable_checklists
    Role.find(1).add_permission!(:manage_expert_checklist_templates, :edit_project)
  end

  def test_managers_see_the_tab_with_project_and_global_templates
    add_template(:name => 'Project one')
    add_template(:project_id => nil, :name => 'Global one')
    @request.session[:user_id] = 2
    get :settings, :params => { :id => 'ecookbook', :tab => 'expert_checklist_templates' }
    assert_response :success
    assert_select '#tab-expert_checklist_templates'
    assert_select 'table.ec-templates td.name a', :text => 'Project one'
    assert_select 'table.ec-templates td.name', :text => 'Global one'
    assert_select 'a[href=?]', '/projects/ecookbook/expert_checklist_templates/new'
  end

  def test_tab_needs_the_permission
    Role.find(1).remove_permission!(:manage_expert_checklist_templates)
    @request.session[:user_id] = 2
    get :settings, :params => { :id => 'ecookbook' }
    assert_response :success
    assert_select '#tab-expert_checklist_templates', 0
  end
end

class ExpertChecklistSettingsTabsTest < Redmine::ControllerTest
  include ExpertChecklistsTestHelper
  tests SettingsController

  fixtures :users, :email_addresses

  def test_plugin_settings_have_template_and_category_tabs
    add_template(:project_id => nil, :name => 'Global one')
    ExpertChecklistTemplateCategory.create!(:name => 'Releases')
    @request.session[:user_id] = 1
    get :plugin, :params => { :id => 'redmine_expert_checklists', :tab => 'templates' }
    assert_response :success
    assert_select '#tab-general'
    assert_select '#tab-templates'
    assert_select '#tab-categories'
    assert_select 'select[name=?]', 'settings[notifications]'
    assert_select 'table.ec-templates td.name a', :text => 'Global one'
    assert_select 'table.ec-template-categories td.name a', :text => 'Releases'
  end

  # Every tab is rendered into the settings form (only hidden), so saving from
  # the templates tab still sends the general settings.
  def test_general_settings_render_their_saved_values_on_every_tab
    with_checklist_settings(:done_ratio_from_checklist => '1', :block_issue_closing => '1',
                            :legacy_import_done_at => '2026-11-09 12:00') do
      @request.session[:user_id] = 1
      get :plugin, :params => { :id => 'redmine_expert_checklists', :tab => 'categories' }
      assert_response :success
      assert_select '#tab-content-general input[type=checkbox][name=?][checked]', 'settings[done_ratio_from_checklist]'
      assert_select '#tab-content-general input[type=checkbox][name=?][checked]', 'settings[block_issue_closing]'
      assert_select '#tab-content-general input[name=?][value=?]', 'settings[legacy_import_done_at]', '2026-11-09 12:00'
    end
  end
end
