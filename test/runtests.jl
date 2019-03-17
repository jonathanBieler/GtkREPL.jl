using GtkREPL
using Test


GtkREPL.gtkrepl()

@testset "Console" begin 
    c = GtkREPL.main_window.console_manager[1]
    @assert c.prompt_position == length(c.prompt)+1
    @assert GtkREPL.command(c) == ""

    GtkREPL.command(c,"x=2")
    @assert GtkREPL.command(c) == "x=2"
    @assert c.prompt_position == length(c.prompt)+1

    GtkREPL.on_return(c,GtkREPL.command(c))
    sleep(0.1)
    @assert GtkREPL.command(c) == ""
    @assert c.prompt_position == 20
end
