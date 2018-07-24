# put important things in a module for safety
module GtkREPLWorker

    using Reexport
    @reexport using RemoteGtkREPL

    gtkrepl_port = parse(Int,ARGS[1])
    global const  id = parse(Int,ARGS[2])
    port, server = RemoteGtkREPL.start_server()

    global const gtkrepl = connect(gtkrepl_port)

end

#ploting stuff
function gadfly()
    @eval begin
        RemoteGtkREPL.gadfly()

        export figure
        import Base: show, display

        show(io::IO,p::Gadfly.Plot) = write(io,"Gadfly.Plot(...)")
        function display(p::Gadfly.Plot)
            remotecall_fetch(display,GtkREPLWorker.gtkrepl,p)
            nothing
        end

        figure() = remotecall_fetch(RemoteGtkREPL.eval_command_remotely,GtkREPLWorker.gtkrepl,"figure()",Main)
        figure(i::Integer) = remotecall_fetch(RemoteGtkREPL.eval_command_remotely,GtkREPLWorker.gtkrepl,"figure($i)",Main)
    end
end

# finally register ourself to gtkrepl
RemoteGtkREPL.remotecall_fetch(include_string, GtkREPLWorker.gtkrepl,"
    eval(GtkREPL,:(
        add_remote_console_cb($(GtkREPLWorker.id), $(GtkREPLWorker.port))
    ))
")

@schedule begin
    isinteractive() && sleep(0.1)
    if !isdefined(:watch_stdio_task)

        global const stdout = STDOUT
        global const stderr = STDERR

        read_stdout, wr = redirect_stdout()
        watch_stdio_task = @schedule RemoteGtkREPL.watch_stream(read_stdout, GtkREPLWorker.gtkrepl, GtkREPLWorker.id)

        #read_stderr, wre = redirect_stderr()
        #watch_stderr_task = @schedule watch_stream(read_stderr,stdout_buffer)
    end
end
