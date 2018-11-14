using ApplicationBuilder
cd("/Users/jbieler/.julia/dev/GtkREPL/")

r = s->joinpath("/Users/jbieler/.julia/",s)

build_app_bundle("build_app.jl", appname="GtkREPL",
    resources=[r("dev/GtkREPL/config/default_settings.jl")],
    libraries=[r("packages/Homebrew/l8kUw/deps/usr/Cellar/gtk+3/3.22.30/lib")],
    verbose=true,
)