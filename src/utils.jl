function style_css(w::Gtk.GtkWidget, provider::GtkCssProvider)
    sc = Gtk.G_.style_context(w)
    push!(sc, provider, 600)
end
style_css(w::Gtk.GtkWidget, css::String) = style_css(w, GtkCssProvider(data=css))

index(notebook::Gtk.GtkNotebook) = Gtk.GAccessor.current_page(notebook) + 1
index(notebook::Gtk.GtkNotebook, i::Integer) = Gtk.GAccessor.current_page(notebook, i-1)
index(notebook::Gtk.GtkNotebook, child::Gtk.GtkWidget) = pagenumber(notebook, child) + 1

## TODO this could be in Gtk.jl

nonmutable(buffer::GtkTextBuffer, it::Gtk.GLib.MutableTypes.Mutable{GtkTextIter}) =
    GtkTextIter(buffer, char_offset(it))

nonmutable(buffer::GtkTextBuffer, it::GtkTextIter) = it

get_tab(notebook::Gtk.GtkNotebook, page_num::Int) = Gtk.GAccessor.nth_page(notebook, page_num-1)

#get_tab(notebook::Gtk.GtkNotebook, page_num::Int) = convert(Gtk.GtkWidget, ccall((:gtk_notebook_get_nth_page,Gtk.libgtk), Ptr{Gtk.GObject},
#    (Ptr{Gtk.GObject}, Cint),notebook, page_num-1))
    

