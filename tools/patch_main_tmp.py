import os
p="scenes/main.gd"
s=open(p).read()
old="hangar_menu.big_ships_requested.connect(func(): big_ship_menu.open())"
new='''hangar_menu.big_ships_requested.connect(func():
		# the interior hangs in the real world, a little above the ship that is being flown, so its windows show the real sky
		var flown := _flown()
		big_ship_menu.set_outside(get_viewport().world_3d, flown.global_transform.translated_local(Vector3(0.0, 120.0, 0.0)))
		big_ship_menu.open())'''
assert old in s
open(p,"w").write(s.replace(old,new,1)); print("patched")
