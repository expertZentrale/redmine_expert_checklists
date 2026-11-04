namespace :redmine_expert_checklists do
  desc <<~DESC
    Imports RedmineUP Checklists data.
      PHASES=items,permissions,settings,queries,modules (default: all)
      DRY_RUN=1   only print what would be imported
      FORCE=1     run the queries/modules phases although RedmineUP is still installed
      REPLACE=1   delete our items first (only while no project uses the module)
  DESC
  task :legacy_import => :environment do
    phases = ENV['PHASES'].to_s.split(',').map(&:strip).reject(&:empty?)
    phases = RedmineExpertChecklists::LegacyImport::PHASES if phases.empty?
    import = RedmineExpertChecklists::LegacyImport.new(:force => ENV['FORCE'] == '1',
                                                        :replace => ENV['REPLACE'] == '1')
    if ENV['DRY_RUN'] == '1'
      import.report.each { |key, value| puts "#{key}: #{value.inspect}" }
    else
      import.run(phases).each { |phase, result| puts "#{phase}: #{result.inspect}" }
    end
  end
end
