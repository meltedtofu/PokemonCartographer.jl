# Battle
Bail early if in a battle? And try again? Or just retry immediately without going through the jobs system?

Can we just disable all battles?
Should be doable with pret but I have no clue how.
This would drastically simplify the logic and decouple my work here from the upcoming PokemonBattle project.
I know that Scott (of Scott's Thoughts) has a way to disable wild encounters in particular regions of the map.
This will probably give some clues.

Apparently there is a "debug_mode" in pokemon that if enabled allows skipping wild battles by holding B.
Just set Bit 1 of 0xd732.
Fascinating!
Do this one next.
Tried it with "BLUEMONS.gb".
Still getting wild pokemon.
Unclear if this is a mythical thing or I'm missing something about the process.
Moving on for now.
Returning early if a battle is detected.

# Progress
Connected components?
I think the ultimate goal is to have all of the locations provided by the roms connected to each other.

A simpler metric: "How many important locations are connected?".
I think the first pass at this would just be the start of the game and every gym leader.
(Blaine and surge are going to be last because I don’t do HMs yet)

## How to visualize progress?
Pretty sure this is going to require some manual work ahead of time.
With the Navmesh I can build a table with the number of tiles found in each location.

From here I can then compare to the number of total tiles.

This will need to be extracted from the map data.
Either manually by counting or by modifying my previous navmesh parser to count the number of walkable tiles.
Even then I will have to modify it to ge “number of reachable tiles”.

This feels like cheating.
But then again, I’m using it to communicate with humans who already have this knowledge.
The info is not feeding in to the agents.

# Intelligence

## Use Navmesh
Use knowledge from previous runs to increase search radius
Need to find the “edges” of the map.
Then chart a course from “here” to “there” and start bumping around.

## Continual searching
Right now the search happens in one batch. "For every save do the search. Then exit."

There needs to be an outer loop which is aiming for a completion metric (see the "Progress" section above).
This loop should then dynamically generate new jobs based on the results of previous jobs.

This will require some sort of "scoreboard" for the saves and roms that exist.
“How much of the map was provided by each job?”.
If basically none -> drop it from the subsequent runs.
If high -> add multiple copies.

# HMs
Surf, Cut, and Strength are mandatory for navigating the game fully.
How to check where these are needed?
I could easily just write an agent that blindly uses cut on every single space on the map.

Surf is a little trickier since it is a state change: "can I begin surfing here?". and then "am I still surfing after I moved?".

Strength is the trickiest because it is changing the map.
I think for the time being I should disable all of the strength things.