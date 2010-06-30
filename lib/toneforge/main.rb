require 'gtk2'

require 'toneforge/resources'

module Toneforge
  def self.main
    builder = Gtk::Builder.new
    builder.add_from_file(Resources.find 'ui.glade')
    window = builder.get_object('wnd_main')
    
    window.signal_connect("destroy") do
      Gtk.main_quit
    end

    window.show_all

    Gtk.main
  end
end

