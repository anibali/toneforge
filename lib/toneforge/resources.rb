module Toneforge
  class Resources
    # Find a resource file. Pass multiple arguments to access subdirectories,
    # like <tt>Resources.find('images', 'icon.png')</tt>.
    def self.find relative_path
      File.join(*[File.dirname(__FILE__), 'res'].concat([*relative_path]))
    end
  end
end

