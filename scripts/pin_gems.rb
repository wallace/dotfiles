# Save this as pin_gems.rb
require "bundler"
specs = Bundler.load.specs.sort_by(&:name)

new_gemfile = File.readlines("Gemfile").map do |line|
  if line =~ /^\s*gem\s+["'](.*?)["']/
    gem_name = $1
    spec = specs.find { |s| s.name == gem_name }
    if spec
      line.sub(/gem\s+["'](.*?)["'](,\s*(.*))?/) do
        rest = Regexp.last_match(2) || ""
        %(gem "#{Regexp.last_match(1)}", "#{spec.version}"#{rest})
      end
    else
      line
    end
  else
    line
  end
end

File.write("Gemfile", new_gemfile.join)
puts "Updated Gemfile with pinned versions!"
