using GtkREPL
using Test


GtkREPL.gtkrepl()

@testset "Console" begin 
    c = GtkREPL.main_window.console_manager[1]
    @test c.prompt_position == length(c.prompt)+1
    @test GtkREPL.command(c) == ""

    GtkREPL.command(c,"x=2")
    @test GtkREPL.command(c) == "x=2"
    @test c.prompt_position == length(c.prompt)+1

    GtkREPL.on_return(c,GtkREPL.command(c))
    #sleep(0.1)
    #@test GtkREPL.command(c) == ""
    #@test c.prompt_position == 20
end
