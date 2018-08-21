mutable struct REPLWindow <: GtkWindow

    handle::Ptr{Gtk.GObject}
    console_manager
    statusBar

    function REPLWindow()

        w = GtkWindow("GtkREPL.jl - v$(VERSION)",800,600)
        
        signal_connect(main_window_key_press_cb,w, "key-press-event", Cint, (Ptr{Gtk.GdkEvent},), false)
        signal_connect(main_window_quit_cb, w, "delete-event", Cint, (Ptr{Gtk.GdkEvent},), false)

        GtkExtensions.style_css(w,"window, view, textview, buffer, text {
            font-family: Monaco, Consolas, Courier, monospace;
            margin:0px;
            font-size:$(fontsize)px;
          }"
        )
        
        n = new(w.handle)
        Gtk.gobject_move_ref(n, w)
    end

end

function init!(w::REPLWindow,console_mng,c)

    main_window.console_manager = console_mng
    main_window.statusBar = GtkStatusbar()
    setproperty!(main_window.statusBar,:margin,2)
    GtkExtensions.text(main_window.statusBar,"Julia $VERSION")

    main_window |> 
        ((mainVbox = GtkBox(:v)) |>
            console_mng |>
            main_window.statusBar
        )

    init!(c)
    showall(main_window)
end

console_manager(main_window::T) where T<:GtkWindow = main_window.console_manager
on_command_done(main_window::T) where T<:GtkWindow = nothing #entry point for external process

@guarded (PROPAGATE) function main_window_key_press_cb(widgetptr::Ptr, eventptr::Ptr, user_data)
    event = convert(Gtk.GdkEvent, eventptr)
    main_window = convert(GtkWindow, widgetptr)

    return PROPAGATE
end

@guarded (PROPAGATE) function main_window_quit_cb(widgetptr::Ptr,eventptr::Ptr, user_data)
    main_window = convert(GtkWindow, widgetptr)
    return PROPAGATE
end
