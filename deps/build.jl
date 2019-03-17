# add unregistered pacakages
using Pkg
Pkg.add(PackageSpec(url="https://github.com/jonathanBieler/GtkExtensions.jl.git", rev="master"))
Pkg.add(PackageSpec(url="https://github.com/jonathanBieler/RemoteGtkREPL.jl.git", rev="master"))
Pkg.add(PackageSpec(url="https://github.com/jonathanBieler/JuliaWordsUtils.jl.git", rev="master"))
Pkg.add(PackageSpec(url="https://github.com/jonathanBieler/GtkTextUtils.jl.git", rev="master"))