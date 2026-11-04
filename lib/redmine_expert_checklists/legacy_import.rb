module RedmineExpertChecklists
  # Takes over what RedmineUP Checklists left in the database. Reads its tables
  # with plain SQL - the plugin itself may already be gone - and writes ours.
  # Every phase can run again: items are imported per issue only while that
  # issue has none of ours, permissions and modules are only added, queries
  # only rewritten where they still name RedmineUP's columns and filters.
  #
  #   import = LegacyImport.new
  #   import.report                      # counts, nothing written
  #   import.run(%w(items permissions))  # report after writing
  #
  # Phases that change what users see (saved queries, modules) refuse to run
  # while RedmineUP is still installed, unless forced: switching the module on
  # next to RedmineUP would show two checklists on every issue.
  class LegacyImport
    PHASES = %w(items permissions settings queries modules).freeze
    NEEDS_REDMINEUP_GONE = %w(queries modules).freeze
    BATCH = 500

    PERMISSIONS = {
      :view_checklists => :view_expert_checklists,
      :done_checklists => :done_expert_checklists,
      :edit_checklists => :edit_expert_checklists
    }.freeze
    COLUMNS = { :checklist_relations => :expert_checklist }.freeze
    FILTERS = { 'checklists_status' => 'expert_checklist_status',
                'checklists_item' => 'expert_checklist_item' }.freeze

    attr_reader :force

    def self.available?
      connection.table_exists?('checklists')
    end

    def self.connection
      ActiveRecord::Base.connection
    end

    def initialize(options = {})
      @force = options[:force] ? true : false
      @replace = options[:replace] ? true : false
    end

    def blocked?(phase)
      NEEDS_REDMINEUP_GONE.include?(phase) && RedmineExpertChecklists.redmineup_present? && !force
    end

    # What a run would do. Never writes.
    def report
      result = { 'redmineup_installed' => RedmineExpertChecklists.redmineup_present?,
                 'legacy_table' => self.class.available? }
      result.merge!(items_report) if result['legacy_table']
      result['roles'] = roles_to_update.size
      result['queries'] = queries_to_convert.size
      result['projects'] = projects_to_enable.size
      result['settings'] = mapped_settings
      result
    end

    def run(phases)
      phases = Array(phases).map(&:to_s) & PHASES
      done = {}
      phases.each do |phase|
        if blocked?(phase)
          done[phase] = 'blocked'
          next
        end
        done[phase] = send("import_#{phase}")
      end
      stamp unless done.empty?
      done
    end

    private

    def connection
      self.class.connection
    end

    def legacy_column?(name)
      connection.column_exists?(:checklists, name)
    end

    # ---- items -----------------------------------------------------------

    def items_report
      orphans = connection.select_value(
        'SELECT COUNT(*) FROM checklists c LEFT JOIN issues i ON i.id = c.issue_id WHERE i.id IS NULL'
      ).to_i
      blank = connection.select_value(
        "SELECT COUNT(*) FROM checklists WHERE subject IS NULL OR TRIM(subject) = ''"
      ).to_i
      long = connection.select_value(
        "SELECT COUNT(*) FROM checklists WHERE LENGTH(subject) > #{RedmineExpertChecklists::SUBJECT_MAX}"
      ).to_i
      issues = connection.select_value(
        'SELECT COUNT(DISTINCT c.issue_id) FROM checklists c INNER JOIN issues i ON i.id = c.issue_id'
      ).to_i
      {
        'legacy_items' => connection.select_value('SELECT COUNT(*) FROM checklists').to_i,
        'legacy_issues' => issues,
        'orphan_items' => orphans,
        'blank_items' => blank,
        'long_items' => long,
        'issues_to_import' => pending_issue_ids.size,
        'issues_already_imported' => issues - pending_issue_ids.size
      }
    end

    # Legacy issues that exist and have none of our items yet.
    def pending_issue_ids
      @pending_issue_ids ||= connection.select_values(<<~SQL).map(&:to_i)
        SELECT DISTINCT c.issue_id FROM checklists c
        INNER JOIN issues i ON i.id = c.issue_id
        WHERE NOT EXISTS (SELECT 1 FROM #{ExpertChecklistItem.table_name} e WHERE e.issue_id = c.issue_id)
        ORDER BY c.issue_id
      SQL
    end

    def import_items
      return { 'imported' => 0 } unless self.class.available?

      replace_existing if @replace
      imported = 0
      renumbered = 0
      pending_issue_ids.each_slice(BATCH) do |ids|
        ExpertChecklistItem.transaction do
          collisions = connection.select_values(<<~SQL).map(&:to_i)
            SELECT c.id FROM checklists c
            INNER JOIN #{ExpertChecklistItem.table_name} e ON e.id = c.id
            WHERE c.issue_id IN (#{ids.join(',')})
          SQL
          imported += insert_items(ids, collisions, true)
          unless collisions.empty?
            renumbered += insert_items(ids, collisions, false)
          end
        end
      end
      connection.reset_pk_sequence!(ExpertChecklistItem.table_name) if connection.respond_to?(:reset_pk_sequence!)
      @pending_issue_ids = nil
      { 'imported' => imported + renumbered, 'new_ids' => renumbered }
    end

    # keep_ids: insert every row whose id is free with that id (history JSON
    # and API clients refer to it); otherwise insert the colliding rows with new
    # ids. Collisions only happen where both plugins were used side by side.
    def insert_items(issue_ids, collisions, keep_ids)
      falsy = connection.quoted_false
      section = legacy_column?(:is_section) ? "COALESCE(c.is_section, #{falsy})" : falsy
      created = legacy_column?(:created_at) ? 'COALESCE(c.created_at, CURRENT_TIMESTAMP)' : 'CURRENT_TIMESTAMP'
      updated = legacy_column?(:updated_at) ? 'COALESCE(c.updated_at, c.created_at, CURRENT_TIMESTAMP)' : created
      id_filter =
        if collisions.empty?
          keep_ids ? '' : ' AND 1=0'
        else
          " AND c.id #{keep_ids ? 'NOT IN' : 'IN'} (#{collisions.join(',')})"
        end
      columns = 'issue_id, subject, is_done, is_section, position, created_at, updated_at'
      select = "c.issue_id, SUBSTR(TRIM(c.subject), 1, #{RedmineExpertChecklists::SUBJECT_MAX}), " \
               "COALESCE(c.is_done, #{falsy}), #{section}, COALESCE(c.position, 1), #{created}, #{updated}"
      if keep_ids
        columns = "id, #{columns}"
        select = "c.id, #{select}"
      end
      connection.exec_update(<<~SQL)
        INSERT INTO #{ExpertChecklistItem.table_name} (#{columns})
        SELECT #{select} FROM checklists c
        WHERE c.issue_id IN (#{issue_ids.join(',')})
          AND c.subject IS NOT NULL AND TRIM(c.subject) <> ''#{id_filter}
        ORDER BY c.issue_id, c.position, c.id
      SQL
    end

    # Re-import over a rehearsal: only while no project uses our module, so no
    # real data of ours can be lost.
    def replace_existing
      return if EnabledModule.where(:name => RedmineExpertChecklists::MODULE.to_s).exists?

      ExpertChecklistItem.delete_all
      @pending_issue_ids = nil
    end

    # ---- permissions -----------------------------------------------------

    def roles_to_update
      Role.all.to_a.select do |role|
        PERMISSIONS.any? { |legacy, ours| role.permissions.include?(legacy) && !role.permissions.include?(ours) }
      end
    end

    def import_permissions
      roles = roles_to_update
      roles.each do |role|
        PERMISSIONS.each do |legacy, ours|
          role.add_permission!(ours) if role.permissions.include?(legacy) && !role.permissions.include?(ours)
        end
      end
      { 'roles' => roles.size }
    end

    # ---- settings --------------------------------------------------------

    def legacy_settings
      value = Setting.where(:name => 'plugin_redmine_checklists').pluck(:value).first
      return {} if value.blank?

      data = YAML.safe_load(value, :permitted_classes => permitted_yaml_classes, :aliases => true)
      data.is_a?(Hash) ? data.to_h.transform_keys(&:to_s) : {}
    rescue StandardError
      # A format we cannot read: fall back to the two flags by pattern.
      { 'issue_done_ratio' => (value.to_s =~ /issue_done_ratio['"]?:\s*['"]?(1|true)/ ? '1' : '0'),
        'block_issue_closing' => (value.to_s =~ /block_issue_closing['"]?:\s*['"]?(1|true)/ ? '1' : '0') }
    end

    def permitted_yaml_classes
      classes = [Symbol, ActiveSupport::HashWithIndifferentAccess]
      configured = Rails.configuration.active_record.yaml_column_permitted_classes rescue nil
      classes + Array(configured)
    end

    def mapped_settings
      legacy = legacy_settings
      events = Setting.notified_events
      notifications =
        if events.include?('issue_updated') then 'issue_updated'
        elsif events.include?('checklist_updated') then 'always'
        else 'never'
        end
      {
        'notifications' => notifications,
        'done_ratio_from_checklist' => LegacyDiff.truthy?(legacy['issue_done_ratio']) ? '1' : '0',
        'block_issue_closing' => LegacyDiff.truthy?(legacy['block_issue_closing']) ? '1' : '0'
      }
    end

    def import_settings
      mapped = mapped_settings
      Setting.plugin_redmine_expert_checklists = RedmineExpertChecklists.settings.to_h.merge(mapped)
      mapped
    end

    # ---- saved queries ---------------------------------------------------

    def queries_to_convert
      IssueQuery.all.to_a.select do |query|
        (query.column_names || []).any? { |name| COLUMNS.key?(name.to_sym) } ||
          (query.filters || {}).keys.any? { |field| FILTERS.key?(field.to_s) }
      end
    end

    def import_queries
      queries = queries_to_convert
      queries.each do |query|
        if query.column_names
          query.column_names = query.column_names.map { |name| COLUMNS[name.to_sym] || name }
        end
        query.filters = convert_filters(query.filters || {})
        query.save(:validate => false)
      end
      { 'queries' => queries.size }
    end

    # RedmineUP's "is not done/undone" matched issues having an item in the
    # other state, which is ours with the opposite value.
    def convert_filters(filters)
      filters.each_with_object({}) do |(field, filter), converted|
        name = FILTERS[field.to_s]
        if name.nil?
          converted[field] = filter
          next
        end
        filter = filter.to_h.transform_keys(&:to_sym)
        if name == 'expert_checklist_status' && filter[:operator].to_s == '!'
          filter = { :operator => '=', :values => Array(filter[:values]).map { |v| v.to_s == '1' ? '0' : '1' }.uniq }
        end
        converted[name] = filter
      end
    end

    # ---- modules ---------------------------------------------------------

    def projects_to_enable
      enabled = EnabledModule.where(:name => RedmineExpertChecklists::MODULE.to_s).select(:project_id)
      EnabledModule.where(:name => 'issue_tracking').where.not(:project_id => enabled).pluck(:project_id)
    end

    def import_modules
      ids = projects_to_enable
      ids.each { |id| EnabledModule.create!(:project_id => id, :name => RedmineExpertChecklists::MODULE.to_s) }
      defaults = Setting.default_projects_modules
      if defaults.include?('issue_tracking') && !defaults.include?(RedmineExpertChecklists::MODULE.to_s)
        Setting.default_projects_modules = defaults + [RedmineExpertChecklists::MODULE.to_s]
      end
      { 'projects' => ids.size }
    end

    def stamp
      Setting.plugin_redmine_expert_checklists =
        RedmineExpertChecklists.settings.to_h.merge('legacy_import_done_at' => Time.now.strftime('%Y-%m-%d %H:%M'))
    end
  end
end
