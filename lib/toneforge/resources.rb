module Toneforge
  class Resources
    def self.find relative_path
      File.join(*[File.dirname(__FILE__), 'res'].concat([*relative_path]))
    end
  end
end

