#!/usr/bin/env python3
"""Authors Sol's five big ships (bridge with seated crew, captain's bay, corridors, crew rooms, airlock), checks them, draws floor plans and
writes src/bigship/big_ship_data.gd.

  python3 tools/gen_big_ships.py            # all ships: check, draw docs/big_ships/<id>_plan.png, write the .gd
  python3 tools/gen_big_ships.py meridian   # one ship (check and draw only)

Every ship is its own plan: the bridge, the captain's bay and the way the rooms hang off the corridors differ from ship to ship."""
import math
import os
import sys

import shipfit as fit
import shipkit
from shipkit import Plan

PI = math.pi
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def finish(p, npcs):
    """Furnish every room that is not hand-furnished, find the spawn spot (nearest free floor to p.spawn), place the standing crew."""
    for room in list(p.rooms):
        if room not in p._handmade:
            fit.furnish(p, room)
    room = next(rid for rid, r in p.rooms.items() if r[0] <= p.spawn[0] < r[0] + r[2] and r[1] <= p.spawn[1] < r[1] + r[3])
    spot = p.free_spot(room, (p.spawn[0], p.spawn[1]), keep_door=0.8)
    p.spawn = (spot[0], spot[1], p.spawn[2])
    p.anchors[room].append((spot[0], spot[1], "spawn"))
    for (room, role, near) in npcs:
        p.npc_auto(room, role, near)
    return p


def bridge_extras(p, room, centre, size=(3.0, 2.0)):
    """A low dais under the captain's chair and a rug strip."""
    p.piece(room, "dais", centre[0], centre[1], size[0], 0.12, size[1], "steel", False, 0.0)


# =============================================================================================== 1. MERIDIAN
def meridian():
    """A long-haul freighter. One 27 m spine runs from the bridge down to a 20 m cargo hold; crew rooms hang off it either side."""
    p = Plan("meridian", "Meridian", ceiling_y=2.9, seed=11)
    p._handmade = {"bridge"}
    p.room("bridge", -7, -42, 14, 7, "bridge", "Bridge")
    p.room("spine", -1.2, -34.8, 2.4, 26.8, "corridor", "Spine corridor")
    p.room("captain_bay", -7, -34.8, 5.6, 5.8, "captain", "Captain's bay")
    p.room("galley", 1.4, -34.8, 5.6, 6.8, "galley", "Galley")
    p.room("quarters_a", -7, -28.8, 5.6, 6.8, "quarters", "Crew quarters A")
    p.room("mess", 1.4, -27.8, 5.6, 6.8, "mess", "Mess")
    p.room("medical", -7, -21.8, 5.6, 6.8, "medical", "Sick bay")
    p.room("quarters_b", 1.4, -20.8, 5.6, 6.8, "quarters", "Crew quarters B")
    p.room("workshop", -7, -14.8, 5.6, 6.8, "workshop", "Workshop")
    p.room("armoury", 1.4, -13.8, 5.6, 5.8, "armoury", "Armoury")
    p.room("cargo_hold", -10, -7.8, 20, 22, "cargo", "Cargo hold")
    p.room("aft_passage", -1.2, 14.4, 2.4, 6.0, "corridor", "Aft passage")
    p.room("engineering", -8, 20.6, 16, 11, "engineering", "Engineering")
    p.room("airlock_s", 10.2, 0.0, 3.4, 4.0, "airlock", "Starboard airlock")
    p.room("airlock_p", -13.6, 0.0, 3.4, 4.0, "airlock", "Port airlock")
    p.link("bridge", "spine", 0, 1.8)
    p.link("bridge", "captain_bay", -4.2)
    p.link("captain_bay", "spine", -32.0)
    p.link("spine", "galley", -31.5)
    p.link("galley", "mess", 4.2)
    p.link("spine", "mess", -24.4)
    p.link("spine", "quarters_a", -25.4)
    p.link("spine", "medical", -18.4)
    p.link("spine", "quarters_b", -17.4)
    p.link("spine", "workshop", -11.4)
    p.link("spine", "armoury", -10.9)
    p.link("spine", "cargo_hold", 0, 2.0)
    p.link("cargo_hold", "aft_passage", 0, 1.8)
    p.link("aft_passage", "engineering", 0, 1.8)
    p.link("cargo_hold", "airlock_s", 2.0, kind="airlock_inner")
    p.link("airlock_p", "cargo_hold", 2.0, kind="airlock_inner")
    p.outer_door("airlock_s", "right", 2.0)
    p.outer_door("airlock_p", "left", 2.0)
    for c in (-4.5, 0.0, 4.5):
        p.window("bridge", "nose", c, 3.6, 0.9, 1.3)
    p.window("bridge", "left", -39.0, 2.4)
    p.window("bridge", "right", -39.0, 2.4)
    for room, side, c in (("captain_bay", "left", -32.0), ("quarters_a", "left", -25.4), ("medical", "left", -18.4), ("workshop", "left", -11.4),
                          ("galley", "right", -31.4), ("mess", "right", -24.4), ("quarters_b", "right", -17.4), ("armoury", "right", -10.9)):
        p.window(room, side, c, 1.6, 1.0, 0.8)
    # bridge: pilot and copilot at the nose, navigation and engineering to port, tactical and comms to starboard, the captain on a dais behind a holo table
    p.seat("bridge", "pilot", "pilot", -2.0, -40.0, 0.0)
    p.seat("bridge", "copilot", "copilot", 2.0, -40.0, 0.0)
    p.seat("bridge", "navigator", "navigator", -5.6, -38.0, PI / 2, exit_side="back")
    p.seat("bridge", "engineer", "engineer", -5.6, -36.2, PI / 2, exit_side="back")
    p.seat("bridge", "tactical", "tactical", 5.6, -38.0, -PI / 2, exit_side="back")
    p.seat("bridge", "comms", "comms", 5.6, -36.2, -PI / 2, exit_side="back")
    p.seat("bridge", "captain", "captain", 0.0, -37.3, 0.0, mat="red_fabric", console=False)
    bridge_extras(p, "bridge", (0.0, -37.3), (3.2, 2.0))
    fit.holo_table(p, "bridge", 0.0, -39.0, 2.4, 1.2)
    fit.rug(p, "bridge", 0.0, -34.0, 3.0, 0.8, "carpet")
    p.spawn = (0.0, -31.5, 0.0)
    return finish(p, [("galley", "cook", None), ("mess", "deckhand", None), ("mess", "deckhand", (5.5, -22.5)), ("medical", "medic", None), ("workshop", "mechanic", None),
                      ("engineering", "engineer", (-3.0, 26.0)), ("engineering", "engineer", (4.0, 24.0)), ("cargo_hold", "loadmaster", (3.0, 6.0)), ("armoury", "quartermaster", None)])


# =============================================================================================== 2. TALON
def talon():
    """A heavy VTOL gunship: the captain's bay is the room right behind the flight deck; two flank gangways run down either side of the troop bay."""
    p = Plan("talon", "Talon", ceiling_y=2.6, seed=22)
    p._handmade = {"bridge"}
    p.room("bridge", -5, -20, 10, 7, "bridge", "Flight deck")
    p.room("captain_bay", -4, -12.8, 8, 4.8, "captain", "Captain's bay")
    p.room("ops", -5, -7.8, 10, 6, "ops", "Ops deck")
    p.room("armoury", -11.2, -7.8, 6, 6, "armoury", "Armoury")
    p.room("comms", 5.2, -7.8, 6, 6, "comms", "Comms and EW")
    p.room("troop_bay", -5, -1.6, 10, 14, "troop", "Troop bay")
    p.room("port_gangway", -7.4, -1.6, 2.2, 14, "corridor", "Port gangway")
    p.room("starboard_gangway", 5.2, -1.6, 2.2, 14, "corridor", "Starboard gangway")
    p.room("engineering", -12.8, -1.6, 5.2, 8, "engineering", "Engineering")
    p.room("med_bay", 7.6, -1.6, 5.2, 8, "medical", "Med bay")
    p.room("stores", -12.8, 6.6, 5.2, 5.8, "storage", "Stores")
    p.room("brig", 7.6, 6.6, 5.2, 5.8, "brig", "Brig")
    p.room("ramp_lock", -2.5, 12.6, 5.0, 3.2, "airlock", "Ramp lock")
    p.link("bridge", "captain_bay", 2.0)
    p.link("captain_bay", "ops", -2.0)
    p.link("ops", "armoury", -4.8)
    p.link("ops", "comms", -4.8)
    p.link("ops", "troop_bay", 0, 2.0)
    p.link("armoury", "port_gangway", -6.3)
    p.link("comms", "starboard_gangway", 6.3)
    p.link("troop_bay", "port_gangway", 3.0)
    p.link("troop_bay", "starboard_gangway", 3.0)
    p.link("engineering", "port_gangway", 2.4)
    p.link("stores", "port_gangway", 9.6)
    p.link("starboard_gangway", "med_bay", 2.4)
    p.link("starboard_gangway", "brig", 9.6)
    p.link("troop_bay", "ramp_lock", 0, 2.0, kind="airlock_inner")
    p.outer_door("ramp_lock", "tail", 0.0, 3.0)
    for c in (-2.6, 2.6):
        p.window("bridge", "nose", c, 4.0, 0.9, 1.3)
    p.window("bridge", "left", -16.5, 2.4)
    p.window("bridge", "right", -16.5, 2.4)
    p.window("armoury", "left", -4.8, 1.4, 1.0, 0.7)
    p.window("comms", "right", -4.8, 1.4, 1.0, 0.7)
    p.window("engineering", "left", 2.4, 1.6, 1.0, 0.7)
    p.window("med_bay", "right", 2.4, 1.6, 1.0, 0.7)
    p.window("stores", "left", 9.6, 1.4, 1.0, 0.7)
    p.window("brig", "right", 9.6, 0.8, 1.2, 0.5)
    # flight deck in three rows: pilots, weapons and sensors, then engineer and comms, with the commander's perch at the back behind a plot table
    p.seat("bridge", "pilot", "pilot", -1.6, -18.5, 0.0)
    p.seat("bridge", "copilot", "copilot", 1.6, -18.5, 0.0)
    p.seat("bridge", "weapons", "weapons", -3.4, -16.6, 0.0, exit_side="left")
    p.seat("bridge", "sensors", "sensors", 3.4, -16.6, 0.0, exit_side="right")
    p.seat("bridge", "engineer", "engineer", -3.4, -14.6, 0.0, exit_side="left")
    p.seat("bridge", "comms", "comms", 3.4, -14.6, 0.0, exit_side="right")
    p.seat("bridge", "captain", "captain", 0.0, -14.7, 0.0, mat="red_fabric", console=False)
    bridge_extras(p, "bridge", (0.0, -14.7), (2.4, 1.6))
    fit.holo_table(p, "bridge", 0.0, -16.0, 2.2, 1.1)
    # door gunners, one each side of the troop bay, firing out of the flank windows
    p.seat("troop_bay", "gunner_port", "gunner", -3.7, 0.6, PI / 2, exit_side="back")
    p.seat("troop_bay", "gunner_starboard", "gunner", 3.7, 0.6, -PI / 2, exit_side="back")
    p.spawn = (0.0, -4.8, 0.0)
    return finish(p, [("ops", "intel officer", (-3.0, -5.0)), ("armoury", "armourer", None), ("comms", "signals", None), ("troop_bay", "marine", (-3.0, 6.0)),
                      ("troop_bay", "marine", (3.0, 7.0)), ("troop_bay", "marine", (-3.0, 9.0)), ("engineering", "engineer", None), ("med_bay", "medic", None),
                      ("stores", "quartermaster", None), ("port_gangway", "crewman", (-6.3, 6.0))])


# =============================================================================================== 3. ARGENT
def argent():
    """A merchant liner. A long gangway leads from the bridge down to a garden atrium; two passenger corridors run aft and join at the stern."""
    p = Plan("argent", "Argent", ceiling_y=3.0, seed=33)
    p._handmade = {"bridge"}
    p.room("bridge", -8, -40, 16, 8, "bridge", "Bridge")
    p.room("fore_walk", -1.5, -31.8, 3, 10, "corridor", "Gangway")
    p.room("atrium", -8, -21.6, 16, 14, "atrium", "Atrium")
    p.room("captain_study", -14.2, -21.6, 6, 6.6, "captain", "Captain's study")
    p.room("captain_bay", -14.2, -14.8, 6, 7.2, "captain", "Captain's bay")
    p.room("lounge", 8.2, -21.6, 7, 14, "lounge", "Passenger lounge")
    p.room("port_corridor", -7.5, -7.4, 2.4, 22, "corridor", "Port corridor")
    p.room("starboard_corridor", 5.1, -7.4, 2.4, 22, "corridor", "Starboard corridor")
    p.room("mess", -4.9, -7.4, 9.8, 12, "mess", "Dining hall")
    p.room("medbay", -4.9, 4.8, 9.8, 6, "medical", "Medical bay")
    p.room("cargo_bay", -4.9, 11.0, 9.8, 3.6, "storage", "Baggage hold")
    for i, z in enumerate((-7.4, -2.2, 3.0, 8.2)):
        p.room("cabin_p%d" % (i + 1), -13.0, z, 5.3, 5.0, "quarters", "Port cabin %d" % (i + 1))
        p.room("cabin_s%d" % (i + 1), 7.7, z, 5.3, 5.0, "quarters", "Starboard cabin %d" % (i + 1))
    p.room("stern_hall", -7.5, 14.8, 15, 4, "corridor", "Stern hall")
    p.room("engineering", -6, 19.0, 12, 9, "engineering", "Engineering")
    p.room("airlock_s", 7.7, 14.8, 3.0, 4.0, "airlock", "Starboard airlock")
    p.room("airlock_p", -10.7, 14.8, 3.0, 4.0, "airlock", "Port airlock")
    p.link("bridge", "fore_walk", 0, 1.8)
    p.link("fore_walk", "atrium", 0, 2.0)
    p.link("atrium", "captain_study", -18.3)
    p.link("captain_study", "captain_bay", -11.2)
    p.link("atrium", "lounge", -14.6)
    p.link("atrium", "port_corridor", -6.3)
    p.link("atrium", "starboard_corridor", 6.3)
    p.link("atrium", "mess", 0, 2.0)
    p.link("port_corridor", "mess", -1.4)
    p.link("mess", "starboard_corridor", -1.4)
    p.link("mess", "medbay", 0, 2.0)
    p.link("medbay", "cargo_bay", 0, 2.0)
    p.link("port_corridor", "medbay", 7.8)
    for i, z in enumerate((-7.4, -2.2, 3.0, 8.2)):
        p.link("cabin_p%d" % (i + 1), "port_corridor", z + 2.5)
        p.link("starboard_corridor", "cabin_s%d" % (i + 1), z + 2.5)
    p.link("port_corridor", "stern_hall", -6.3)
    p.link("starboard_corridor", "stern_hall", 6.3)
    p.link("cargo_bay", "stern_hall", 0, 2.0)
    p.link("stern_hall", "engineering", 0, 2.0)
    p.link("stern_hall", "airlock_s", 16.8, kind="airlock_inner")
    p.link("airlock_p", "stern_hall", 16.8, kind="airlock_inner")
    p.outer_door("airlock_s", "right", 16.8)
    p.outer_door("airlock_p", "left", 16.8)
    for c in (-5.0, 0.0, 5.0):
        p.window("bridge", "nose", c, 4.0, 0.9, 1.4)
    p.window("bridge", "left", -37.0, 2.6)
    p.window("bridge", "right", -37.0, 2.6)
    p.window("captain_study", "left", -18.3, 2.6, 0.9, 1.2)
    p.window("captain_bay", "left", -11.2, 2.6, 0.9, 1.2)
    p.window("lounge", "right", -14.6, 5.0, 0.8, 1.4)
    p.window("lounge", "nose", 11.7, 3.4, 0.9, 1.4)
    for i, z in enumerate((-7.4, -2.2, 3.0, 8.2)):
        p.window("cabin_p%d" % (i + 1), "left", z + 2.5, 1.4, 1.0, 0.8)
        p.window("cabin_s%d" % (i + 1), "right", z + 2.5, 1.4, 1.0, 0.8)
    # bridge: helm up front, navigation and comms to port, tactical and engineering to starboard, the captain on a dais behind the holo table
    p.seat("bridge", "pilot", "pilot", -2.4, -38.6, 0.0)
    p.seat("bridge", "copilot", "copilot", 2.4, -38.6, 0.0)
    p.seat("bridge", "navigator", "navigator", -6.6, -37.0, PI / 2, exit_side="back")
    p.seat("bridge", "comms", "comms", -6.6, -34.6, PI / 2, exit_side="back")
    p.seat("bridge", "tactical", "tactical", 6.6, -37.0, -PI / 2, exit_side="back")
    p.seat("bridge", "engineer", "engineer", 6.6, -34.6, -PI / 2, exit_side="back")
    p.seat("bridge", "captain", "captain", 0.0, -35.0, 0.0, mat="red_fabric", console=False)
    bridge_extras(p, "bridge", (0.0, -35.0), (3.4, 2.2))
    fit.holo_table(p, "bridge", 0.0, -37.0, 2.6, 1.3)
    p.spawn = (0.0, -28.0, 0.0)
    return finish(p, [("atrium", "steward", (4.0, -14.0)), ("atrium", "passenger", (-4.0, -12.0)), ("lounge", "passenger", None), ("lounge", "bartender", (14.0, -10.0)),
                      ("mess", "chef", None), ("medbay", "doctor", None), ("engineering", "engineer", None), ("cargo_bay", "porter", None), ("captain_study", "first officer", None)])


# =============================================================================================== 4. HALO
def halo():
    """A ring ship. A square ring corridor runs round the hull; the bridge, the reactor hall and the rest of the ship sit inside it."""
    p = Plan("halo", "Halo", ceiling_y=3.2, seed=44)
    p._handmade = {"bridge", "core"}
    p.room("bridge", -9, -18, 18, 7, "bridge", "Bridge")
    p.room("nw_arm", -18, -18, 8.8, 3.2, "corridor", "North-west arm")
    p.room("ne_arm", 9.2, -18, 8.8, 3.2, "corridor", "North-east arm")
    p.room("west_arm", -18, -14.6, 3.2, 29.2, "corridor", "West arm")
    p.room("east_arm", 14.8, -14.6, 3.2, 29.2, "corridor", "East arm")
    p.room("south_arm", -18, 14.8, 36, 3.2, "corridor", "South arm")
    p.room("captain_bay", -14.6, -14.6, 5.4, 7.0, "captain", "Captain's bay")
    p.room("chart_room", 9.2, -14.6, 5.4, 7.0, "observation", "Chart room")
    p.room("core", -9, -10.8, 18, 14, "core", "Reactor hall")
    p.room("quarters_a", -14.6, -7.4, 5.4, 5.6, "quarters", "Crew quarters A")
    p.room("quarters_b", -14.6, -1.6, 5.4, 4.8, "quarters", "Crew quarters B")
    p.room("mess", 9.2, -7.4, 5.4, 5.6, "mess", "Mess")
    p.room("medical", 9.2, -1.6, 5.4, 4.8, "medical", "Medical")
    p.room("cargo_hold", -14.6, 3.4, 15.6, 11.2, "cargo", "Cargo hold")
    p.room("shuttle_bay", 1.2, 3.4, 13.4, 11.2, "hangar", "Shuttle bay")
    p.room("airlock", -3, 18.2, 6, 3.0, "airlock", "Airlock")
    p.link("nw_arm", "bridge", -16.4)
    p.link("bridge", "ne_arm", -16.4)
    p.link("nw_arm", "west_arm", -16.4)
    p.link("ne_arm", "east_arm", 16.4)
    p.link("west_arm", "south_arm", -16.4)
    p.link("east_arm", "south_arm", 16.4)
    p.link("bridge", "captain_bay", -12.8)
    p.link("bridge", "chart_room", -12.8)
    p.link("nw_arm", "captain_bay", -12.0)
    p.link("ne_arm", "chart_room", 12.0)
    p.link("bridge", "core", -3.2, 1.4)
    p.link("bridge", "core", 3.2, 1.4)
    p.link("core", "quarters_a", -4.6)
    p.link("core", "quarters_b", 0.8)
    p.link("quarters_a", "west_arm", -4.6)
    p.link("quarters_b", "west_arm", 0.8)
    p.link("core", "mess", -4.6)
    p.link("core", "medical", 0.8)
    p.link("mess", "east_arm", -4.6)
    p.link("medical", "east_arm", 0.8)
    p.link("core", "cargo_hold", -4.0, 1.8)
    p.link("core", "shuttle_bay", 5.0, 1.8)
    p.link("cargo_hold", "shuttle_bay", 9.0, 2.0)
    p.link("cargo_hold", "west_arm", 9.0)
    p.link("shuttle_bay", "east_arm", 9.0)
    p.link("cargo_hold", "south_arm", -7.0, 1.8)
    p.link("shuttle_bay", "south_arm", 7.0, 1.8)
    p.link("south_arm", "airlock", 0.0, 2.0, kind="airlock_inner")
    p.outer_door("airlock", "tail", 0.0)
    for c in (-6.0, 0.0, 6.0):
        p.window("bridge", "nose", c, 4.4, 0.9, 1.5)
    p.window("nw_arm", "nose", -13.0, 3.4, 0.9, 1.4)
    p.window("ne_arm", "nose", 13.0, 3.4, 0.9, 1.4)
    p.window("west_arm", "left", 0.0, 3.0, 0.9, 1.4)
    p.window("east_arm", "right", 0.0, 3.0, 0.9, 1.4)
    p.window("south_arm", "tail", -10.0, 3.4, 0.9, 1.4)
    p.window("south_arm", "tail", 10.0, 3.4, 0.9, 1.4)
    # bridge: helm up front, the rest of the crew in two banks facing a central holo table, the captain behind it
    p.seat("bridge", "pilot", "pilot", -1.8, -16.4, 0.0)
    p.seat("bridge", "copilot", "copilot", 1.8, -16.4, 0.0)
    p.seat("bridge", "navigator", "navigator", -6.0, -14.2, -PI / 2, exit_side="back")
    p.seat("bridge", "sensors", "sensors", -6.0, -12.4, -PI / 2, exit_side="back")
    p.seat("bridge", "tactical", "tactical", 6.0, -14.2, PI / 2, exit_side="back")
    p.seat("bridge", "engineer", "engineer", 6.0, -12.4, PI / 2, exit_side="back")
    p.seat("bridge", "captain", "captain", 0.0, -12.6, 0.0, mat="red_fabric", console=False)
    bridge_extras(p, "bridge", (0.0, -12.6), (2.6, 1.8))
    fit.holo_table(p, "bridge", 0.0, -14.6, 2.4, 1.4)
    fit.furnish(p, "core")
    p.spawn = (0.0, -9.0, 0.0)
    return finish(p, [("core", "reactor tech", (-4.0, 0.0)), ("core", "reactor tech", (4.0, -6.0)), ("mess", "cook", None), ("medical", "medic", None), ("shuttle_bay", "pilot", (6.0, 10.0)),
                      ("cargo_hold", "loadmaster", None), ("chart_room", "navigator", None), ("west_arm", "crewman", (-16.4, 6.0)), ("east_arm", "crewman", (16.4, -6.0))])


# =============================================================================================== 5. KESTREL
def kestrel():
    """A survey corvette. The bridge opens on an observation lounge and the captain's bay; a gallery of labs leads to a single aft corridor."""
    p = Plan("kestrel", "Kestrel", ceiling_y=2.8, seed=55)
    p._handmade = {"bridge"}
    p.room("bridge", -6, -28, 12, 7, "bridge", "Bridge")
    p.room("captain_bay", 6.2, -28, 7, 7, "captain", "Captain's bay")
    p.room("observation", -13.2, -28, 7, 7, "observation", "Observation lounge")
    p.room("gallery", -6, -20.8, 12, 10, "atrium", "Survey gallery")
    p.room("lab_a", -13.2, -20.8, 7, 5, "lab", "Geology lab")
    p.room("lab_b", -13.2, -15.6, 7, 4.8, "lab", "Biology lab")
    p.room("greenhouse", 6.2, -20.8, 7, 10, "greenhouse", "Greenhouse")
    p.room("aft_corridor", -1.5, -10.6, 3.0, 22, "corridor", "Aft corridor")
    p.room("crew_quarters", -8.9, -10.6, 7.2, 7, "quarters", "Crew quarters")
    p.room("wardroom", -8.9, -3.4, 7.2, 6, "mess", "Wardroom")
    p.room("workshop", -8.9, 2.8, 7.2, 8.6, "workshop", "Instrument workshop")
    p.room("medical", 1.7, -10.6, 7.2, 7, "medical", "Sick bay")
    p.room("storage", 1.7, -3.4, 7.2, 6, "storage", "Sample store")
    p.room("engineering", 1.7, 2.8, 7.2, 8.6, "engineering", "Engineering")
    p.room("stern_lock", -3, 11.6, 6, 4, "airlock", "Probe lock")
    p.link("bridge", "captain_bay", -26.5)
    p.link("observation", "bridge", -26.5)
    p.link("bridge", "gallery", 0, 2.0)
    p.link("observation", "lab_a", -9.7)
    p.link("lab_a", "gallery", -18.3)
    p.link("lab_b", "gallery", -13.2)
    p.link("lab_a", "lab_b", -9.7)
    p.link("gallery", "greenhouse", -15.8)
    p.link("captain_bay", "greenhouse", 9.7)
    p.link("gallery", "aft_corridor", 0, 1.8)
    p.link("crew_quarters", "aft_corridor", -7.1)
    p.link("wardroom", "aft_corridor", -0.4)
    p.link("workshop", "aft_corridor", 7.1)
    p.link("aft_corridor", "medical", -7.1)
    p.link("aft_corridor", "storage", -0.4)
    p.link("aft_corridor", "engineering", 7.1)
    p.link("aft_corridor", "stern_lock", 0, 1.8, kind="airlock_inner")
    p.outer_door("stern_lock", "tail", 0.0)
    for c in (-3.5, 0.0, 3.5):
        p.window("bridge", "nose", c, 4.2 if c else 2.2, 0.9, 1.3)
    p.window("observation", "nose", -9.7, 4.6, 0.6, 1.8)
    p.window("observation", "left", -24.5, 3.0, 0.6, 1.8)
    p.window("captain_bay", "nose", 9.7, 3.0, 0.9, 1.1)
    p.window("captain_bay", "right", -24.5, 2.6, 0.9, 1.1)
    p.window("greenhouse", "right", -15.8, 5.0, 0.7, 1.7)
    p.window("lab_a", "left", -18.3, 2.4, 1.0, 0.8)
    p.window("lab_b", "left", -13.2, 2.4, 1.0, 0.8)
    p.window("crew_quarters", "left", -7.1, 1.6, 1.0, 0.8)
    p.window("workshop", "left", 7.1, 1.6, 1.0, 0.8)
    p.window("medical", "right", -7.1, 1.6, 1.0, 0.8)
    p.window("engineering", "right", 7.1, 1.6, 1.0, 0.8)
    # bridge: a shallow theatre: helm in front, science stations to port, comms and engineering to starboard, the captain in the middle at the back
    p.seat("bridge", "pilot", "pilot", -1.8, -26.4, 0.0)
    p.seat("bridge", "copilot", "copilot", 1.8, -26.4, 0.0)
    p.seat("bridge", "science", "science", -4.6, -24.6, PI / 2, exit_side="back")
    p.seat("bridge", "sensors", "sensors", -4.6, -22.8, PI / 2, exit_side="back")
    p.seat("bridge", "comms", "comms", 4.6, -24.6, -PI / 2, exit_side="back")
    p.seat("bridge", "engineer", "engineer", 4.6, -22.8, -PI / 2, exit_side="back")
    p.seat("bridge", "captain", "captain", 0.0, -23.4, 0.0, mat="red_fabric", console=False)
    bridge_extras(p, "bridge", (0.0, -23.4), (2.6, 1.8))
    fit.holo_table(p, "bridge", 0.0, -25.0, 2.0, 1.1)
    p.spawn = (0.0, -18.0, 0.0)
    return finish(p, [("gallery", "researcher", (-3.0, -15.0)), ("gallery", "researcher", (3.0, -13.0)), ("lab_a", "geologist", None), ("lab_b", "biologist", None),
                      ("greenhouse", "botanist", None), ("observation", "astronomer", None), ("wardroom", "cook", None), ("workshop", "technician", None),
                      ("engineering", "engineer", None), ("medical", "medic", None)])


SHIPS = {"meridian": meridian, "talon": talon, "argent": argent, "halo": halo, "kestrel": kestrel}


def main(argv):
    wanted = argv[1:] or list(SHIPS)
    plans = {}
    failed = False
    for sid in wanted:
        plan = SHIPS[sid]()
        problems = plan.validate()
        seats = len(plan.seats)
        print("%-9s %2d rooms %2d doors %3d pieces %d seats %d crew" % (sid, len(plan.rooms), len(plan.portals), len(plan.furniture), seats, len(plan.npcs)))
        for w in plan.warnings:
            print("   warning:", w)
        for problem in problems:
            print("   PROBLEM:", problem)
            failed = True
        out_dir = os.path.join(ROOT, "docs", "big_ships")
        os.makedirs(out_dir, exist_ok=True)
        shipkit.draw_plan(plan, os.path.join(out_dir, "%s_plan.png" % sid))
        plans[sid] = plan
    if failed:
        print("not writing the data file: fix the problems above")
        return 1
    if len(wanted) == len(SHIPS):
        data = {sid: plans[sid].to_gd_dict() for sid in SHIPS}
        text = ("# GENERATED by tools/gen_big_ships.py from tools/shipkit.py: do not edit by hand, change the generator and run it again.\n"
                "extends RefCounted\n## The five big ships' interiors as plain data: rooms, doors, seats, furniture, windows and standing crew (see BigShipPlan).\n\n"
                "const SHIPS := " + shipkit.gd_literal(data) + "\n")
        path = os.path.join(ROOT, "src", "bigship", "big_ship_data.gd")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, "w").write(text)
        print("wrote", os.path.relpath(path, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
