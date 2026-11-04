module RedmineExpertChecklists
  # The value of the "Checklist" issue list column. to_s is what CSV and PDF
  # exports print (core formats unknown objects with to_s): RedmineUP's
  # "[+] done" / "[-] open" lines, sections as plain lines, CRLF separated.
  # The HTML list cell is drawn by QueriesHelperPatch.
  class ListValue
    attr_reader :items

    def initialize(items)
      @items = items
    end

    def to_s
      items.map(&:to_export_line).join("\r\n")
    end

    def empty?
      items.empty?
    end
  end
end
