require 'gtk2'

require 'toneforge/resources'

module Toneforge
  def self.main
    builder = Gtk::Builder.new
    builder.add_from_file(Resources.find 'ui.glade')
    window = builder.get_object('wnd_main')
    volume = builder.get_object('adj_volume')
    amp_label = builder.get_object('lbl_amp')
    
    window.signal_connect("destroy") do
      Gtk.main_quit
    end
    
    volume.signal_connect("value-changed") do
      amp_label.set_text(format('%.1f%%', volume.value))
    end

    window.show_all

    Gtk.main
  end
end

