using GtkREPL, Gtk

Base.@ccallable function julia_main(ARGS::Vector{String})::Cint
    
    GtkREPL.gtkrepl()    
    c = Condition()
    signal_connect(GtkREPL.main_window, :destroy) do widget
        notify(c)
    end
    wait(c)

end

