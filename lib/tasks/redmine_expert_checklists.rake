namespace :redmine_expert_checklists do
  desc <<~DESC
    Imports RedmineUP Checklists data.
      PHASES=items,permissions,settings,queries,modules (default: all; with PROJECTS: items,queries,modules)
      PROJECTS=a,b  switch only these projects (identifiers or ids) while RedmineUP stays installed
      DRY_RUN=1   only print what would be imported
      FORCE=1     run the queries/modules phases although RedmineUP is still in use
      REPLACE=1   delete our items first (only while no project uses the module)
  DESC
  task :legacy_import => :environment do
    projects = ENV['PROJECTS'].to_s.split(',').map(&:strip).reject(&:empty?).map do |key|
      Project.find_by(:identifier => key) || Project.find_by(:id => key) || abort("Unknown project: #{key}")
    end
    phases = ENV['PHASES'].to_s.split(',').map(&:strip).reject(&:empty?)
    if phases.empty?
      phases = projects.any? ? RedmineExpertChecklists::LegacyImport::PROJECT_PHASES : RedmineExpertChecklists::LegacyImport::PHASES
    end
    import = RedmineExpertChecklists::LegacyImport.new(:force => ENV['FORCE'] == '1',
                                                        :replace => ENV['REPLACE'] == '1',
                                                        :projects => projects)
    if projects.any? && import.switch_blocked?
      abort 'RedmineUP Checklists cannot be switched off per project: its permissions belong to the ' \
            'issue tracking module. See README, "Moving from RedmineUP Checklists".'
    end
    if ENV['DRY_RUN'] == '1'
      import.report.each { |key, value| puts "#{key}: #{value.inspect}" }
    else
      import.run(phases).each { |phase, result| puts "#{phase}: #{result.inspect}" }
    end
  end
end
