#!/usr/bin/env ruby
##
## Converts a Timing CSV export into a format that can be imported straight into Harvest.
##
## Copyright (©) 2018  Gabriel Somoza
## You should have received a copy of the GNU General Public License
## along with this program. If not, see <http://www.gnu.org/licenses/>.

def usage()
  puts "Usage: #{$0} [path] [first-name] [last-name]"
  puts ""
  puts "  path\t\tPath to a CSV export from Timing."
  puts "  first-name\tFirst name of the user this timesheet belongs to."
  puts "  first-name\tLast name of the user this timesheet belongs to."
  puts ""
end

if ARGV.count < 3
  usage
  return
end

require 'csv'

path = File.absolute_path(ARGV[0])
unless File.exists?(path)
  puts "Could not find file at: #{path}"
  return 1
end

headers_parsed = false
$cols = {
  :duration => {
    :index => nil,
    :format => nil
  },
  :date => {
    :index => nil,
    :format => :iso
  },
  :end_date => {
    :index => nil
  },
  :client => {
    :index => nil
  },
  :project => {
    :index => nil
  },
  :task => {
    :index => nil
  },
  :notes => {
    :index => nil
  }
}

module Cols
  module Headers
    def Headers.map(row)
      # first delete columns we don't need
      $cols[:end_date][:index] = row.find_index("End Date")
      row.delete_at($cols[:end_date][:index])
      # then add new columns
      row << "Client"
      row << "First name"
      row << "Last name"

      # then get indexes
      $cols[:duration][:index] = row.find_index("Duration")
      $cols[:date][:index] = row.find_index("Start Date")
      $cols[:project][:index] = row.find_index("Project")
      $cols[:client][:index] = row.find_index("Client")
      $cols[:task][:index] = row.find_index("Task Title")
      $cols[:notes][:index] = row.find_index("Notes")

      # rename some headers
      row[$cols[:date][:index]] = 'Date'
      row[$cols[:duration][:index]] = 'Hours'
      row[$cols[:task][:index]] = 'Task'
    end
  end # Headers

  module Duration
    def Duration.detect_format(duration)
      if $cols[:duration][:format].nil?
        duration = duration.to_s
        $cols[:duration][:format] = case true
          when duration.include?(':')
            :default
          when duration.include?('s') || duration.include?('m') || duration.include?('h')
            :hms
          else
            :decimal
        end
      end
      $cols[:duration][:format]
    end

    def Duration.map(row)
      val = row[$cols[:duration][:index]]
      row[$cols[:duration][:index]] = case detect_format(val)
        when :decimal
          (val.to_f / 3600.0).round(2)
      end
    end
  end # duration

  module Date
    def Date.map(row)
      dt = row[$cols[:date][:index]]
      row[$cols[:date][:index]] = DateTime::iso8601(dt).to_date.iso8601
    end
  end # Date

  module Project
    def Project.map(row)
      separator = '▸'
      crumbs = row[$cols[:project][:index]].split(separator).map(&:strip)
      row[$cols[:client][:index]] = crumbs.first
      row[$cols[:project][:index]] = crumbs.last
    end
  end # Project

  module Notes
    def Notes.map(row)
      label = "[T]" # to easily identify hours that were imported from Timing
      val = row[$cols[:notes][:index]]
      row[$cols[:notes][:index]] = val.nil? ? label : val + " " + label
    end
  end
end

CSV.foreach(path) do |row|
  row.shift # remove columns we don't need
  unless headers_parsed
    Cols::Headers.map(row)
    puts CSV.generate_line(row)
    headers_parsed = true
    next
  end

  # the following column operations must be symmetrical to the ones during header parsing
  row.delete_at($cols[:end_date][:index]) # we don't need it
  row << nil
  row << ARGV[1] # first name
  row << ARGV[2] # last name

  Cols::Duration.map(row)
  Cols::Date.map(row)
  Cols::Project.map(row)
  Cols::Notes.map(row)

  puts CSV.generate_line(row)
end
