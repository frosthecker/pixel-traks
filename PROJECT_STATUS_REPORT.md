# Pixel Traks - Project Status Report

*Generated from codebase inspection on Nov 17, 2026*

---

## Executive Summary

**Pixel Traks** is a Godot 4.x pixel-art farming/survival RPG with procedural world generation, NPC AI with LLM-powered dialogue (Groq), and a behavior-tree based NPC scheduling system. The project is in a **playable prototype state** with core systems implemented but several areas needing polish, expansion, and integration.

---

## Section 1: NPC Intelligence ✅ **Functional - Needs Expansion**

### Current State
- **Behavior Tree System**: Fully implemented in `AI/trees/random_move.tres` with states: Talk, Work, Follow Player, Wander, Idle, Sleep
- **Daily Schedules**: NPCs follow time-based schedules via `apply_schedule.gd` and `npc_biodata.gd` (sleep, work, farm, eat, follow_player, wander, talk)
- **LLM Dialogue**: Groq integration (`groq_service.gd`) with JSON-structured responses, conversation history (6 turns), and interactive choice menus
- **Farmer Work**: John NPC can farm autonomously (plant seeds, chop trees) via `farmer_work.gd` and behavior tree
- **Multiple NPCs**: John, Kaia, Mira, Orin, Seller with unique personalities and dialogue files

### Gaps / TODO
| Priority | Item |
|----------|------|
| High | **More NPC archetypes** - Only "farmer" behavior implemented; need merchants, guards, quest-givers |
| High | **Relationship system** - `relationship_values` exists in `npc_biodata.gd` but unused |
| High | **Memory/Long-term context** - Conversation history limited to 6 turns; no persistent memory across sessions |
| Medium | **NPC-NPC interactions** - NPCs don't interact with each other |
| Medium | **Dynamic schedule adaptation** - Schedules are static; should react to world events (weather, seasons, player actions) |
| Medium | **Pathfinding** - Uses simple raycast-based movement; no A* or navigation mesh for complex terrain |
| Low | **Emotional state system** - `current_mood` exists but not deeply integrated |

---

## Section 2: Procedural Wildlife ✅ **Functional - Needs Polish**

### Current State
- **Procedural Creatures**: Uses `procedural_creatures` addon (C# runtime) with `CreatureActor.tscn`
- **Three Habitats**: Land (quadruped), Water (aquatic), Air (winged) via `creature.gd`
- **Spawning System**: `_spawn_creatures()` in `proc_level.gd` places creatures on valid terrain with clearance checks
- **Preset Support**: Optional JSON presets for cow/rabbit variants
- **Collision Validation**: Creatures validate positions against tilemap each physics frame

### Gaps / TODO
| Priority | Item |
|----------|------|
| High | **Creature AI/Behavior** - Currently only idle/wander random movement; no flocking, hunting, fleeing, territorial behavior |
| High | **Creature Interactions** - No player interaction (petting, feeding, hunting, taming) |
| High | **Lifecycle** - No breeding, aging, death, or population dynamics |
| Medium | **Biome-specific creatures** - All land creatures use same quadruped family; need variety per biome |
| Medium | **Creature drops/loot** - No resources from creatures (meat, hide, feathers, etc.) |
| Medium | **Visual variety** - Limited to preset JSON files; procedural generation could create more unique appearances |
| Low | **Creature sounds/VFX** - No audio or particle effects for creature actions |

---

## Section 3: Farming Improvements ✅ **Core Loop Works - Needs Depth**

### Current State
- **9 Crops**: Beetroot, Cabbage, Carrot, Cauliflower, Potato, Pumpkin, Radish, Wheat (each with growth speed, death max, sell price)
- **Tools**: Hoe (till), Water (hydrate), Seed (plant), Axe (chop trees)
- **Soil System**: Light/Dark dirt layers with terrain-connect for visual borders
- **Day Cycle**: Plants grow when watered (dark dirt present); decay when not
- **NPC Farming**: John autonomously farms via behavior tree
- **Plant Info UI**: Panel shows crop status

### Gaps / TODO
| Priority | Item |
|----------|------|
| High | **Seasons** - No seasonal crop restrictions; all crops grow year-round |
| High | **Crop Quality/Tiers** - No star quality, giant crops, or fertilizer system |
| High | **Sprinklers/Automation** - `MACHINE_UPGRADE_COST` commented out in `data.gd`; sprinklers, scarecrows, fishers defined but not implemented |
| Medium | **Soil Fertility** - No nutrient depletion, crop rotation, or compost |
| Medium | **Farming Tools Upgrade** - No tool upgrades (gold/iridium hoe, watering can, etc.) |
| Medium | **Greenhouse/Indoor Farming** - No structure for year-round growing |
| Medium | **Seed Maker** - No way to convert crops back to seeds |
| Low | **Crop Diseases/Pests** - Only simple "decay" mechanic; no blight, crows, weeds |
| Low | **Farming Skill/XP** - No player progression in farming |

---

## Section 4: Crafting and Economy ⚠️ **Minimal - Major Expansion Needed**

### Current State
- **Inventory**: 14 slots + hotbar, stack sizes per item, money system
- **Selling**: Seller NPC buys crops for money (`sell_all_crops()`)
- **Items**: 11 items defined in `ItemData.json` (tools, resources, crops, fish, egg)
- **Shop**: Basic seller interaction only
- **Building Costs**: `HOUSE_COST` defined (wood only) but no building placement UI

### Gaps / TODO
| Priority | Item |
|----------|------|
| Critical | **Crafting System** - No crafting recipes, stations, or UI at all |
| Critical | **Building System** - House costs defined but no placement/construction mechanics |
| High | **Recipe System** - Need data-driven recipes (JSON) for tools, machines, furniture, food |
| High | **Crafting Stations** - Workbench, furnace, kitchen, loom, etc. |
| High | **Expanded Economy** - Multiple merchants with different inventories, restocking, price fluctuation |
| Medium | **Processing** - Mill (wheat→flour), kitchen (crops→meals), preserves jar, keg |
| Medium | **Fishing Economy** - Fish selling, fish types, fishing rod upgrades |
| Medium | **Shipping Bin** - Passive overnight selling (Stardew-style) |
| Low | **Market/Demand System** - Dynamic prices based on supply/demand |
| Low | **Contracts/Quests** - Delivery quests for extra money |

---

## Section 5: World Generation ✅ **Robust - Good Foundation**

### Current State
- **Noise-based Terrain**: Simplex noise for islands with water/sand/grass biomes
- **Flood-fill Beaches**: Connected sand at edges becomes beaches; enclosed sand stays water
- **Forest Generation**: Noise-based tree placement with density variation, protected zones around entities
- **Island Detection**: Flood-fill finds connected landmasses; places player/NPCs/shop on largest island
- **Entity Placement**: NPCs spaced with min/max distance from player and each other
- **Creature Spawning**: Habitat-aware spawning with clearance checks
- **Skeleton Spawning**: Periodic enemy spawns at distance from player
- **Camera Limits**: Auto-calculated from world dimensions
- **Save Migration**: Legacy saves auto-migrate to new format

### Gaps / TODO
| Priority | Item |
|----------|------|
| High | **Multiple Biomes** - Only grass/sand/water; need forest, desert, snow, swamp, mushroom biomes |
| High | **Structures/POIs** - Ruins, caves, dungeons, abandoned farms, shrines |
| High | **Resource Nodes** - Ore veins, stone quarries, clay pits, geodes |
| Medium | **Rivers/Lakes** - Inland water bodies with bridges |
| Medium | **Roads/Paths** - Connect POIs and NPC homes |
| Medium | **World Size Options** - Configurable small/medium/large worlds |
| Medium | **Seed Input** - Let players enter custom world seeds |
| Low | **Minimap/World Map** - `world_sections.tscn` exists but not fully integrated |
| Low | **Ocean Content** - Islands, shipwrecks, underwater caves |

---

## Section 6: Survival Simulation ⚠️ **Basic - Needs Core Systems**

### Current State
- **Health System**: Player health (10 max), damage immunity, regeneration after delay
- **Day/Night Cycle**: 24-hour cycle (1 real minute = 1 in-game minute), visual transitions
- **Skeleton Enemies**: Periodic spawns, basic combat
- **Tool Durability**: Not implemented (tools don't break)
- **Hunger/Thirst**: Not implemented
- **Stamina**: Not implemented
- **Temperature/Weather**: Not implemented
- **Sleep Mechanic**: NPCs have sleep schedule; player can force day change

### Gaps / TODO
| Priority | Item |
|----------|------|
| Critical | **Hunger/Thirst** - Core survival mechanics missing entirely |
| Critical | **Stamina/Energy** - Limits on tool use, running, combat |
| High | **Weather System** - Rain (auto-waters crops), storms, seasonal effects |
| High | **Temperature** - Cold/heat mechanics, clothing/armor for protection |
| High | **Sleep/Fatigue** - Player must sleep; passing out has consequences |
| Medium | **Tool Durability** - Tools degrade, need repair/replacement |
| Medium | **Sanity/Mental Health** - Horror/isolation mechanics (optional) |
| Medium | **Illness/Status Effects** - Poison, sickness, buffs/debuffs |
| Low | **Hardcore Mode** - Permadeath option |

---

## Section 7: Save System ✅ **Production-Ready**

### Current State
- **3 Save Slots** + Resume (auto-save every 10s)
- **Compressed Storage**: ZSTD compression via `FileAccess.open_compressed`
- **Versioned Format**: Payload version tracking for future migrations
- **Full State Persistence**: Player, world tiles, plants, trees, NPCs, dropped items, world time, inventory, money
- **Meta File**: `save_meta.cfg` tracks slot names, day count, last played timestamp
- **World Deletion**: Confirmation dialog wipes save and restarts fresh world
- **Migration**: Legacy saves auto-generate world then rewrite
- **UI**: `save_load.gd` with save/load/rename/new world modes

### Gaps / TODO
| Priority | Item |
|----------|------|
| Medium | **Cloud Sync** - Steam Cloud / platform save sync |
| Medium | **Save Import/Export** - Backup/restore to file for sharing |
| Medium | **Screenshot Thumbnails** - Visual save slot previews |
| Low | **Auto-save Indicators** - UI feedback when auto-save occurs |
| Low | **Save Corruption Recovery** - Validation and fallback to previous save |

---

## Section 8: Game Feel / Juice, Integration & QA ⚠️ **Mixed - Polish Needed**

### Current State
- **Screen Shake**: On damage (`_shake_camera()`)
- **Hit Flash**: Player turns red on damage
- **Particle Effects**: Leaf particles on tree chop, log drop animation
- **Day Transitions**: Shader-based smooth day/night transitions
- **High Contrast / Reduced Motion**: Accessibility options implemented
- **Settings Persistence**: Video, audio, accessibility settings saved to `user://settings.cfg`
- **Contrast Shader**: Full-screen contrast adjustment for accessibility

### Gaps / TODO
| Priority | Item |
|----------|------|
| High | **Combat Feedback** - Hit pause, knockback, enemy hit flash, damage numbers |
| High | **Tool/Action Feedback** - Sound variety, particle bursts, screen shake on heavy hits |
| High | **UI Juice** - Button press animations, tooltip transitions, inventory drag-drop feel |
| High | **Audio System** - Music layers (day/night/combat), ambient sounds, SFX variety |
| Medium | **Harvest Animation** - Crop pop effect, item fly-to-inventory animation |
| Medium | **Level Up / Progression Feedback** - XP bars, skill unlock notifications |
| Medium | **NPC Reaction Variety** - Emoticons exist but limited usage |
| Medium | **Transition Polish** - Scene transitions, menu open/close animations |
| Low | **Photo Mode** - Hide UI, camera controls for screenshots |
| Low | **Replay System** - Record/playback for bug reports |

### Integration & QA
| Area | Status |
|------|--------|
| **Scene Management** | Two level scenes (`level.tscn`, `proc_level.tscn`) with duplicate code - needs unification |
| **Input System** | Mixed: some hardcoded in player, some in InputMap - needs centralization |
| **Global Autoloads** | Good separation: `SaveGame`, `PlayerInventory`, `WorldTime`, `GroqService`, `JSONData`, `GameSettings` |
| **Testing** | No automated tests found |
| **Error Handling** | Good use of `push_error`/`push_warning` but no crash reporting |
| **Performance** | TileMap serialization uses base64; procedural generation yields frames - acceptable for current scale |
| **Localization** | No i18n system; all text hardcoded in English |

---

## Recommended Development Priority Order

### Phase 1: Core Gameplay Loop (Weeks 1-4)
1. **Hunger/Thirst/Stamina** - Survival foundation
2. **Crafting System + Recipes** - Progression & goals
3. **Building System** - Player expression & progression
4. **Tool Durability + Upgrades** - Resource sink

### Phase 2: World & Content (Weeks 5-8)
5. **Multiple Biomes + Structures** - Exploration incentive
6. **Seasons + Weather** - Variety & farming depth
7. **Creature AI + Interactions** - Living world
8. **Expanded Economy** - Multiple merchants, processing

### Phase 3: NPC & Story (Weeks 9-12)
9. **Relationship System + Quests** - Social gameplay
10. **NPC Memory + Dynamic Schedules** - Deeper simulation
11. **NPC-NPC Interactions** - Emergent storytelling

### Phase 4: Polish & Release Prep (Weeks 13-16)
12. **Game Feel/Juice Pass** - Combat, UI, audio, VFX
13. **Accessibility & Settings Polish** - Full compliance
14. **Performance Optimization** - Large worlds, many entities
15. **QA: Bug Fixes, Balancing, Tutorial** - Ship-ready

---

## Technical Debt & Refactoring Notes

1. **Duplicate Level Code**: `level.gd` and `proc_level.gd` share ~80% identical tool/save logic → extract base class
2. **Hardcoded NPC Names**: `john.gd` is specific; needs generic `NPC` class with data-driven behavior
3. **Magic Numbers**: Many constants scattered (distances, timers, health values) → centralize in `GameSettings` or constants file
4. **Input System**: Mix of `_unhandled_input`, `_process`, InputMap actions → unify
5. **Dialogic Integration**: Tight coupling to Dialogic 2 API; consider abstraction layer
6. **Groq Fallback**: Good fallback chain but no offline/local LLM option (e.g., llama.cpp)
7. **Save Format**: Base64-packed tiles work but not human-readable; consider JSON for debugging

---

## File Structure Reference

```
scripts/
├── npc.gd              # Base NPC (minimal)
├── john.gd             # Main NPC with Groq AI (AI/scripts/john.gd)
├── creature.gd         # Procedural creature wrapper
├── plant.gd            # Crop instance
├── tree.gd             # Choppable tree
├── seller.gd           # Shop NPC
├── level.gd            # Hand-authored level
├── proc_level.gd       # Procedural level (main)
├── world_time.gd       # Day/night cycle
├── save_load.gd        # Save/Load UI
├── settings_menu.gd    # Settings UI
├── groq_service.gd     # LLM integration
├── singleton/
│   ├── save_game.gd    # Save system
│   ├── PlayerInventory.gd
│   ├── JSONData.gd     # Item data loader
│   └── GameSettings.gd # Settings persistence (referenced)
├── AI/
│   ├── tasks/          # Behavior tree actions
│   └── trees/          # .tres behavior trees
├── resources/
│   ├── npc_resource.gd
│   ├── npc_biodata.gd
│   └── plant_res.gd
└── global/
    ├── enums.gd
    └── data.gd         # Plant data, tool animations, costs
```

---

*End of Report*