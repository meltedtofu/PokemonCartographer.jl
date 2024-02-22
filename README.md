# Pokémon Cartographer

Create a map and navmesh of Pokémon games by stumbling around the world and observing the game state.

| **Documentation**    | **Build Status**        | **Coverage** |
|:--------------------:|:-----------------------:|:------------:|
| [DEV](https://meltedtofu.com/PokemonCartographer.jl) | [![](https://github.com/meltedtofu/PokemonCartographer.jl/workflows/Runtests/badge.svg)](https://github.com/meltedtofu/PokemonCartographer.jl/actions?query=workflows/CI) | [![codecov](https://codecov.io/gh/meltedtofu/PokemonCartographer.jl/graph/badge.svg?token=1WB1313288)](https://codecov.io/gh/meltedtofu/PokemonCartographer.jl) |

## How it works

1. Initialize the globe with a single location (the starting location).
2. Pick a random place on the globe.
3. Find a route from the current location to the selected location.
4. Go there.
5. Once you arrive, bounce around.
6. Record all of the spaces you visit along the way.
7. When time is up return your discovered spaces.
8. Go back to (2).
9. Bonus points running this in parallel batches with Distributed.