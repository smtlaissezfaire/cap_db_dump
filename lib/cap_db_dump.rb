module CapDbDump
  class << self
    def load
      require File.dirname(__FILE__) + "/cap_db_dump/version"
      require File.dirname(__FILE__) + "/cap_db_dump/recipes"
    end
  end
end
