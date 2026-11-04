# Admin page for the RedmineUP Checklists import: shows what would be taken
# over, runs the chosen phases. Synchronous - every phase is a handful of
# INSERT ... SELECT statements; for very large tables use the rake task
# redmine_expert_checklists:legacy_import instead.
class ExpertChecklistImportsController < ApplicationController
  layout 'admin'
  self.main_menu = false if respond_to?(:main_menu=)

  before_action :require_admin

  def show
    @import = RedmineExpertChecklists::LegacyImport.new(:force => params[:force].present?)
    @report = @import.report
  end

  def create
    import = RedmineExpertChecklists::LegacyImport.new(:force => params[:force].present?,
                                                        :replace => params[:replace].present?)
    result = import.run(params[:phases])
    if result.empty?
      flash[:error] = l(:error_expert_checklist_import_no_phase)
    else
      flash[:notice] = l(:notice_expert_checklist_import_done, :result => summary(result))
    end
    redirect_to expert_checklist_legacy_import_path(:force => params[:force].presence)
  end

  private

  def summary(result)
    result.map do |phase, outcome|
      text = outcome.is_a?(Hash) ? outcome.map { |key, value| "#{key}: #{value}" }.join(', ') : outcome.to_s
      "#{l("label_expert_checklist_import_phase_#{phase}")} (#{text})"
    end.join('; ')
  end
end
