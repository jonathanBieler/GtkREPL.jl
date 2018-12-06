using GtkREPL, Gtk

builddir = "/Applications/GtkREPL.app/Contents/Libraries/"
hb_root = "/Users/jbieler/.julia/packages/Homebrew/l8kUw/deps/usr/"

if get(ENV, "COMPILING_APPLE_BUNDLE", "false") == "true"

    #overwrite library paths in Gtk so they are relative
    gtk_libs = [
        :libgdk,
        :libgdk_pixbuf,
        :libgio,
        :libglib,
        :libgobject,
        :libgtk,
    ]

    splitfile(f) = split(f,"usr/")[2]#remove the first part of the path

    filenames = splitfile.([Core.eval(GtkREPL.Gtk,l) for l in gtk_libs])
    libs = Dict(zip(gtk_libs,filenames))
    
    for (l,f) in libs
        Core.eval(Gtk, :($l = joinpath($builddir,$f)))
        Core.eval(Gtk.GLib, :($l = joinpath($builddir,$f)))
        
        @assert isfile( joinpath(builddir,f) )
    end

    function __init__bindeps__()

        mkpath(joinpath(builddir,"share"))
        if "XDG_DATA_DIRS" in keys(ENV)
            ENV["XDG_DATA_DIRS"] *= ":" * joinpath(builddir,"share")
        else
            ENV["XDG_DATA_DIRS"] = joinpath(builddir,"share")
        end
        ENV["GDK_PIXBUF_MODULEDIR"] = joinpath(builddir, "lib/gdk-pixbuf-2.0/2.10.0/loaders")
        ENV["GDK_PIXBUF_MODULE_FILE"] = joinpath(builddir, "lib/gdk-pixbuf-2.0/2.10.0/loaders.cache")
        @assert isfile(joinpath(builddir, "lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"))
        run(`/Applications/GtkREPL.app/Contents/MacOS/gdk-pixbuf-query-loaders --update-cache`)#I move it to MacOS in before build
    end

    Gtk.__init__bindeps__() = __init__bindeps__()
    Gtk.GLib.__init__bindeps__() = __init__bindeps__()
    Gtk.__init__bindeps__()

    #Gtk.__init__bindeps__() = nothing
    #Gtk.GLib.__init__bindeps__() = nothing
    #__init__bindeps__()

end

Base.@ccallable function julia_main(ARGS::Vector{String})::Cint
    GtkREPL.gtkrepl()
    c = Condition()
    signal_connect(GtkREPL.main_window, :destroy) do widget
        notify(c)
    end
    wait(c)
end
