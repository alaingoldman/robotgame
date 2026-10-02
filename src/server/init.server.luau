-- Mech game server entry point
local MechService = require(script.MechService)

MechService.start()
-- EXO-1 exoskeleton worn on the player's back (ExoService / ExoConfig)
require(script.ExoService).start()
-- EXO-1 showcase statues south of the spawn (built only if the place has none)
require(script.ExoShowcase).ensure()
