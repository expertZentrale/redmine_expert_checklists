# Checklist templates: project ones from the project settings tab ("Manage
# checklist templates" there), global ones from the plugin settings (admins).
# A template keeps its scope; lists live in those two places, so there is no
# index or show.
class ExpertChecklistTemplatesController < ApplicationController
  layout :template_layout
  menu_item :settings

  before_action :find_template, :only => [:edit, :update, :destroy]
  before_action :find_project_for_new, :only => [:new, :create]
  before_action :authorize_template

  helper :expert_checklists

  def new
    @checklist_template = ExpertChecklistTemplate.new(:project => @project)
    @checklist_template.safe_attributes = params[:expert_checklist_template] if params[:expert_checklist_template]
  end

  def create
    @checklist_template = ExpertChecklistTemplate.new(:project => @project, :author => User.current)
    @checklist_template.safe_attributes = params[:expert_checklist_template]
    if @checklist_template.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to_list
    else
      render :action => 'new'
    end
  end

  def edit
  end

  def update
    @checklist_template.safe_attributes = params[:expert_checklist_template]
    if @checklist_template.save
      flash[:notice] = l(:notice_successful_update)
      redirect_to_list
    else
      render :action => 'edit'
    end
  end

  def destroy
    @checklist_template.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to_list
  end

  private

  def find_template
    @checklist_template = ExpertChecklistTemplate.find(params[:id])
    @project = @checklist_template.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_project_for_new
    @project = Project.find(params[:project_id]) if params[:project_id].present?
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # Global templates: admins. Project templates: "Manage checklist templates"
  # with the module on; another user's private one only for admins.
  def authorize_template
    allowed =
      if @checklist_template && @checklist_template.persisted?
        @checklist_template.editable_by?(User.current) && (@checklist_template.global? || RedmineExpertChecklists.enabled?(@project))
      elsif @project
        RedmineExpertChecklists.enabled?(@project) &&
          User.current.allowed_to?(:manage_expert_checklist_templates, @project)
      else
        User.current.admin?
      end
    deny_access unless allowed
  end

  def template_layout
    @project ? 'base' : 'admin'
  end

  def redirect_to_list
    if @project
      redirect_to settings_project_path(@project, :tab => 'expert_checklist_templates')
    else
      redirect_to plugin_settings_path('redmine_expert_checklists', :tab => 'templates')
    end
  end
end
