# Maze arrival and exit elevators

Built in Hotel Oddities, under Workspace.Maze15. Both reuse the lobby elevator cabin and door meshes, anchored and persistent for streaming. The lobby elevator itself is unchanged.

Arrival opening: (589.585, -22.632, -616.210), facing +Z into the hallway. Exit opening: (-586.733, -22.632, 530.819), facing +X. Their adjacent hallway graph points are approximately 2,400.73 studs apart along the shortest graph route. They were selected from boundary candidates with at least 45 studs of connector clearance; these sites have approximately 177 and 250 studs respectively. The graph analysis used 389 nodes and 36 connector rooms; distance through decorated connector interiors is approximate.

The existing Spawn part moved to StartElevator at (589.585, -23.132, -622.210). SpawnSafeZone moved with it and retains its 60 x 11.186 x 60 oriented box. The existing vanish protection, enemy exclusion and safe-zone services continue to use the same tagged instances. This is a relocated box, not a newly introduced circular radius.

Architecture measurements: finished floor Y -22.632; corridor width 14.73; walls use 0.5-stud wood baseboard, 3.5-stud WoodPlanks wainscot, 0.5-stud chair rail, 7.82-stud plaster wallpaper and 0.5-stud crown. Trim color is RGB 86/66/54, wainscot 141/101/80, wallpaper 135/111/67. Wallpaper texture 232876941 tiles at 4 x 4 studs; carpet texture 321324778 also tiles at 4 x 4. Existing pilasters, lantern stations and ceiling lights remain in place. Pilaster meshes are 136061890476948 and 108416159302163; lantern meshes include 100928012610335, 110462692754680 and 87494904045442; ceiling fixtures use 18568498397 and 18568498439.

Openings are 8.2 studs wide and 8.6 high. Wall parts were split in their local axes, preserving material and cloned textures, with matching wood jambs/lintel and a threshold. Eight original wall parts are backed up under ServerStorage.MazeElevatorOriginalWalls. Spawn and zone retain PreviousCFrame attributes. The reproduction script requires a maze without the new elevators; it does not execute during gameplay.

Exit panel order: Blue, Yellow, Red, Green, Purple. Each row has a color strip/name, MISSING or COMPLETE text, and frame-built X/check bars. LOCKED count changes to READY - ENTER when all five specific configured computers are complete. The panel and sliding doors change only on each player's client. The server independently checks exit-cabin entry. Door motion uses the existing sound and tween, with 3.35-stud travel for each maze door. No screen notification, shared progress, post-exit teleport, round reset or victory behavior is added.

Edit-mode pictures were requested. Gameplay, spawning, multiplayer access, streaming and door movement have not been playtested.
