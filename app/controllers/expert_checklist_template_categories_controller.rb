# Template categories (global, admins), listed on the plugin settings page.
# update also takes the drag-and-drop reordering there (core positionedItems).
class ExpertChecklistTemplateCategoriesController < ApplicationController
  layout 'admin'
  self.main_menu = false if respond_to?(:main_menu=)

  before_action :require_admin
  before_action :find_category, :only => [:edit, :update, :destroy]

  def new
    @category = ExpertChecklistTemplateCategory.new
  end

  def create
    @category = ExpertChecklistTemplateCategory.new
    @category.safe_attributes = params[:expert_checklist_template_category]
    if @category.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to_list
    else
      render :action => 'new'
    end
  end

  def edit
  end

  def update
    @category.safe_attributes = params[:expert_checklist_template_category]
    saved = @category.save
    respond_to do |format|
      format.html do
        if saved
          flash[:notice] = l(:notice_successful_update)
          redirect_to_list
        else
          render :action => 'edit'
        end
      end
      format.js { head(saved ? 200 : 422) }
    end
  end

  def destroy
    @category.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to_list
  end

  private

  def find_category
    @category = ExpertChecklistTemplateCategory.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def redirect_to_list
    redirect_to plugin_settings_path('redmine_expert_checklists', :tab => 'categories')
  end
end
