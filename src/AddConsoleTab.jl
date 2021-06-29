mutable struct AddConsoleTab <: GtkScrolledWindow
    handle::Ptr{Gtk.GObject}
    textview::GtkTextView
    worker_idx::Int

    function AddConsoleTab(main_window)
        vbox = GtkBox(:v)
        sc = GtkScrolledWindow(vbox)
        
        b = GtkButton("Add Console")
        b.expand[Bool] = false
        signal_connect(add_console_button_press_cb, b, "button-press-event", 
        Cint, (Ptr{Gtk.GdkEvent},), false, main_window)
        push!(vbox, b)

        buffer = GtkTextBuffer()
        textview = GtkTextView(buffer)
        textview.editable[Bool] = false
        push!(vbox, textview)

        n = new(sc.handle, textview, -1)#invalid index so we don't think it's a Console
        Gtk.gobject_move_ref(n, sc)
    end
end

function add_plus_button(console_mng::ConsoleManager)
    tab = AddConsoleTab(console_mng.main_window)
    push!(console_mng, tab)
    Gtk.GAccessor.tab_label_text(console_mng, tab, "+")
end

@guarded (INTERRUPT) function add_console_button_press_cb(widgetptr::Ptr, eventptr::Ptr, user_data)
    button = convert(GtkButton, widgetptr)
    main_window = user_data 
    add_remote_console(main_window, main_window.console_manager.top_module)
    return INTERRUPT
end

function on_console_mng_switch_page(cm::ConsoleManager, tab::AddConsoleTab)
    #
    b = tab.textview.buffer[GtkTextBuffer]
    t = String[]
    for i = 1:length(cm)
        c = get_tab(cm, i)
        if typeof(c) <: Console
            push!(t," ID: $(c.worker_idx) \t Port: $(c.worker_port) \t Status: $(c.busy)\n")
        end
    end
    b.text[String] = string("Consoles:\n",t...)

end
