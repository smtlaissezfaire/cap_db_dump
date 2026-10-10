Gem::Specification.new do |s|
  s.name = 'cap_db_dump'
  s.version = '1.3.3'
  s.date = '2026-10-10'
  s.summary = "cap_db_dump"
  s.description = "Capistrano tasks for dumping your mysql database + transfering to your local machine"
  s.authors = ["Scott Taylor"]
  s.email = 'scott@railsnewbie.com'
  s.files = Dir.glob("lib/**/*.rb")
  s.homepage = 'https://github.com/smtlaissezfaire/cap_db_dump'

  s.add_dependency 'capistrano', '~> 2.15.10'
  s.add_dependency 'net-ssh', '~> 7.2.3'
end