begin
  require 'jeweler'
  
  Jeweler::Tasks.new do |gemspec|
    gemspec.name        = "the-perfect-gem"
    gemspec.summary     = "Summarize your gem"
    gemspec.description = "Describe your gem"
    gemspec.email       = "scott@railsnewbie.com"
    gemspec.homepage    = "http://github.com/smtlaissezfaire/the-perfect-gem"
    gemspec.authors     = ["Scott Taylor"]
  end
rescue LoadError
  puts "Jeweler not available. Install it with: sudo gem install technicalpickles-jeweler -s http://gems.github.com"
end
