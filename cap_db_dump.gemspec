Gem::Specification.new do |s|
  s.name        = 'cap_db_dump'
  s.version     = '1.2.0'
  s.date        = '2012-09-06'
  s.summary     = "cap_db_dump"
  s.description = "Capistrano tasks for dumping your mysql database + transfering to your local machine"
  s.authors     = ["Scott Taylor"]
  s.email       = 'scott@railsnewbie.com'
  s.files       = Dir.glob("recipes/**/*.rb")
  s.homepage    =
    'https://github.com/smtlaissezfaire/cap_db_dump'
end