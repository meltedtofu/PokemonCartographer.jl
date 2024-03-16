using Documenter
using PokemonCartographer

function sanitizefile(filelines)
    content = ""
    skips = 0
    for line in filelines
        if skips > 0
            skips -= 1
            continue
        elseif contains(line, "<!-- START HTML -->")
            content *= "```@raw html\n"
        elseif contains(line, "<!-- REPLACE")
            _, replace_value, _ = split(line, r"\{\{|\}\}")
            content *= "$replace_value\n"
            skips += 1
        else
            content *= "$line\n"
        end
    end
    content
end

function readmeifchanged()
    indexpath = joinpath(@__DIR__, "src", "index.md")
    readme = readlines(open(joinpath(@__DIR__, "..", "README.md")))
    indexmd = isfile(indexpath) ? readlines(open(indexpath)) : ""
    if readme != indexmd
        write(indexpath, sanitizefile(readme))
    end
end

readmeifchanged()

DocMeta.setdocmeta!(PokemonCartographer, :DocTestSetup, :(using PokemonCartographer, PokemonCartographer.Nav); recursive=true)

makedocs(sitename = "PokemonCartographer.jl",
         format = Documenter.HTML(repolink="github.com/meltedtofu/PokemonCartographer.jl.git", edit_link=nothing),
         modules = [PokemonCartographer,
                    PokemonCartographer.Nav,
                    PokemonCartographer.Worker,
                    ],
         remotes = nothing,
         pages = [
             "Overview" => "index.md",
             "code.md",
         ])

if "DOCUMENTER_KEY" in keys(ENV)
    deploydocs( repo = "github.com/meltedtofu/PokemonCartographer.jl.git")
end
