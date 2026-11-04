require 'digest/md5'

module RedmineExpertChecklists
  # Reads the history RedmineUP Checklists wrote, so it stays readable once that
  # plugin is gone. RedmineUP stored the whole list before and after a change as
  # JSON (JournalDetail attr/checklist): an array of item rows, each possibly
  # wrapped as {"checklist": {...}}. Items are matched by id. Its checklist
  # custom fields stored [{subject, is_done, is_section}] without ids; those
  # items are matched by an MD5 of the subject, as RedmineUP did.
  #
  # Written from the stored format, not from RedmineUP's code.
  module LegacyDiff
    OLD_TEXT_FORMAT = /^\[[ x]\] .+$/

    module_function

    # Item key => snapshot, or nil when the value is not a JSON list (the
    # plain-text format of RedmineUP versions before 3.1.2, or garbage).
    def parse(value, key_by = :id)
      return {} if value.nil? || value.to_s.strip.empty?

      json = JSON.parse(value.to_s)
      json = [json] unless json.is_a?(Array)
      json.each_with_object({}) do |row, map|
        next unless row.is_a?(Hash)

        row = row['checklist'] if row['checklist'].is_a?(Hash)
        subject = row['subject'].to_s
        key = key_by == :subject ? Digest::MD5.hexdigest(subject) : row['id'].to_s
        map[key] = RedmineExpertChecklists.snapshot(subject, truthy?(row['is_done']), truthy?(row['is_section']))
      end
    rescue JSON::ParserError
      nil
    end

    def old_text_format?(value)
      value.is_a?(String) && value.match?(OLD_TEXT_FORMAT)
    end

    def truthy?(value)
      value == true || value.to_s == 'true' || value.to_s == '1'
    end
  end
end
