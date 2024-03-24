var documenterSearchIndex = {"docs":
[{"location":"code/#Code","page":"Code","title":"Code","text":"","category":"section"},{"location":"code/","page":"Code","title":"Code","text":"Here lie all of the docstrings in the PokemonCartographer.jl codebase.","category":"page"},{"location":"code/","page":"Code","title":"Code","text":"Modules = [PokemonCartographer,\n           PokemonCartographer.Nav,\n          ]","category":"page"},{"location":"code/#PokemonCartographer.explore-Tuple{}","page":"Code","title":"PokemonCartographer.explore","text":"Create a Navmesh by playing the game.\n\nStarting with a list of roms and save states, spawn a worker for each pair and merge the resulting navmeshes.\n\n\n\n\n\n","category":"method"},{"location":"code/#PokemonCartographer.genbatch-Tuple{Vector{String}, Int64, Int64, MetaGraphsNext.MetaGraph{C, Graphs.SimpleGraphs.SimpleDiGraph{C}, PokemonCartographer.Nav.Position, Nothing, PokemonCartographer.Nav.Direction, Nothing} where C, Vector{PokemonCartographer.Nav.Position}}","page":"Code","title":"PokemonCartographer.genbatch","text":"Generate a batch of jobs to run\n\n\n\n\n\n","category":"method"},{"location":"code/#PokemonCartographer.Nav.randomincomplete-Tuple{MetaGraphsNext.MetaGraph{C, Graphs.SimpleGraphs.SimpleDiGraph{C}, PokemonCartographer.Nav.Position, Nothing, PokemonCartographer.Nav.Direction, Nothing} where C, Vector{PokemonCartographer.Nav.Position}}","page":"Code","title":"PokemonCartographer.Nav.randomincomplete","text":"Select a random, incomplete vertex in the navmesh. Incomplete vertices have less than four outedges - e.g. Up, Down, Left, Right.\n\n\n\n\n\n","category":"method"},{"location":"#Pokémon-Cartographer","page":"Overview","title":"Pokémon Cartographer","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"Create a map and navmesh of Pokémon games by stumbling around the world and observing the game state.","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"Documentation Build Status Coverage\nDEV (Image: ) (Image: codecov)","category":"page"},{"location":"#How-it-works","page":"Overview","title":"How it works","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"Initialize the globe with a single location (the starting location).\nPick a random place on the globe.\nFind a route from the current location to the selected location.\nGo there.\nOnce you arrive, bounce around.\nRecord all of the spaces you visit along the way.\nWhen time is up return your discovered spaces.\nGo back to (2).\nBonus points running this in parallel batches with Distributed.","category":"page"},{"location":"#BLUEMONS.GB","page":"Overview","title":"BLUEMONS.GB","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"To bootstrap an AI and decouple \"explore the world\" from \"play the game\" this project runs on top of the BLUEMONS.GB rom; a debug version of Pokémon Blue (sha1: 5b1456177671b79b263c614ea0e7cc9ac542e9c4). In this version of the game, you start with a party that has an Exeggutor which has all of the required HMs and can hold B to bypass any trainers.","category":"page"}]
}
