# Save this as pin_gems.rb
require "bundler"
specs = Bundler.load.specs.sort_by(&:name)

new_gemfile = File.readlines("Gemfile").map do |line|
  if line =~ /^\s*gem\s+["'](.*?)["']/
    gem_name = $1
    spec = specs.find { |s| s.name == gem_name }
    if spec
      line.sub(/gem\s+["'](.*?)["'](,\s*(.*))?/, "gem \"\\1\", \"#{spec.version}\"\\2")
    else
      line
    end
  else
    line
  end
end

File.write("Gemfile", new_gemfile.join)
puts "Updated Gemfile with pinned versions!"
