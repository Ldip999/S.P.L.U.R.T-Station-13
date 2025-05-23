/*
	New methods:
	pulse - sends a pulse into a wire for hacking purposes
	cut - cuts a wire and makes any necessary state changes
	mend - mends a wire and makes any necessary state changes
	canAIControl - 1 if the AI can control the airlock, 0 if not (then check canAIHack to see if it can hack in)
	canAIHack - 1 if the AI can hack into the airlock to recover control, 0 if not. Also returns 0 if the AI does not *need* to hack it.
	hasPower - 1 if the main or backup power are functioning, 0 if not.
	requiresIDs - 1 if the airlock is requiring IDs, 0 if not
	isAllPowerCut - 1 if the main and backup power both have cut wires.
	regainMainPower - handles the effect of main power coming back on.
	loseMainPower - handles the effect of main power going offline. Usually (if one isn't already running) spawn a thread to count down how long it will be offline - counting down won't happen if main power was completely cut along with backup power, though, the thread will just sleep.
	loseBackupPower - handles the effect of backup power going offline.
	regainBackupPower - handles the effect of main power coming back on.
	shock - has a chance of electrocuting its target.
*/

// Wires for the airlock are located in the datum folder, inside the wires datum folder.

#define AIRLOCK_CLOSED	1
#define AIRLOCK_CLOSING	2
#define AIRLOCK_OPEN	3
#define AIRLOCK_OPENING	4
#define AIRLOCK_DENY	5
#define AIRLOCK_EMAG	6

#define AIRLOCK_FRAME_CLOSED "closed"
#define AIRLOCK_FRAME_CLOSING "closing"
#define AIRLOCK_FRAME_OPEN "open"
#define AIRLOCK_FRAME_OPENING "opening"

#define AIRLOCK_LIGHT_BOLTS "bolts"
#define AIRLOCK_LIGHT_EMERGENCY "emergency"
#define AIRLOCK_LIGHT_DENIED "denied"
#define AIRLOCK_LIGHT_CLOSING "closing"
#define AIRLOCK_LIGHT_OPENING "opening"

#define AIRLOCK_LIGHT_POWER 1
#define AIRLOCK_LIGHT_RANGE 2

#define AIRLOCK_POWERON_LIGHT_COLOR "#3aa7c2"
#define AIRLOCK_BOLTS_LIGHT_COLOR "#c22323"
#define AIRLOCK_ACCESS_LIGHT_COLOR "#57e69c"
#define AIRLOCK_EMERGENCY_LIGHT_COLOR "#d1d11d"
#define AIRLOCK_ENGINEERING_LIGHT_COLOR "#fd8719"
#define AIRLOCK_DENY_LIGHT_COLOR "#c22323"

#define AIRLOCK_SECURITY_NONE			0 //Normal airlock				//Wires are not secured
#define AIRLOCK_SECURITY_METAL			1 //Medium security airlock		//There is a simple metal over wires (use welder)
#define AIRLOCK_SECURITY_PLASTEEL_I_S	2 								//Sliced inner plating (use crowbar), jumps to 0
#define AIRLOCK_SECURITY_PLASTEEL_I		3 								//Removed outer plating, second layer here (use welder)
#define AIRLOCK_SECURITY_PLASTEEL_O_S	4 								//Sliced outer plating (use crowbar)
#define AIRLOCK_SECURITY_PLASTEEL_O		5 								//There is first layer of plasteel (use welder)
#define AIRLOCK_SECURITY_PLASTEEL		6 //Max security airlock		//Fully secured wires (use wirecutters to remove grille, that is electrified)

#define AIRLOCK_INTEGRITY_N			 300 // Normal airlock integrity
#define AIRLOCK_INTEGRITY_MULTIPLIER 1.5 // How much reinforced doors health increases
#define AIRLOCK_DAMAGE_DEFLECTION_N  21  // Normal airlock damage deflection
#define AIRLOCK_DAMAGE_DEFLECTION_R  30  // Reinforced airlock damage deflection

#define NOT_ELECTRIFIED 0
#define ELECTRIFIED_PERMANENT -1
#define AI_ELECTRIFY_DOOR_TIME 30

/obj/machinery/door/airlock
	name = "airlock"
	icon = 'icons/obj/doors/airlocks/station/public.dmi'
	icon_state = "closed"
	max_integrity = 300
	var/normal_integrity = AIRLOCK_INTEGRITY_N
	integrity_failure = 0.25
	damage_deflection = AIRLOCK_DAMAGE_DEFLECTION_N
	autoclose = TRUE
	secondsElectrified = NOT_ELECTRIFIED //How many seconds remain until the door is no longer electrified. -1 if it is permanently electrified until someone fixes it.
	assemblytype = /obj/structure/door_assembly
	normalspeed = 1
	explosion_block = 1
	wave_explosion_block = EXPLOSION_BLOCK_WALL
	wave_explosion_multiply = EXPLOSION_DAMPEN_WALL
	hud_possible = list(DIAG_AIRLOCK_HUD)

	interaction_flags_machine = INTERACT_MACHINE_WIRES_IF_OPEN | INTERACT_MACHINE_ALLOW_SILICON | INTERACT_MACHINE_OPEN_SILICON | INTERACT_MACHINE_REQUIRES_SILICON | INTERACT_MACHINE_OPEN

	var/security_level = 0 //How much are wires secured
	var/aiControlDisabled = 0 //If 1, AI control is disabled until the AI hacks back in and disables the lock. If 2, the AI has bypassed the lock. If -1, the control is enabled but the AI had bypassed it earlier, so if it is disabled again the AI would have no trouble getting back in.
	var/hackProof = FALSE // if true, this door can't be hacked by the AI
	var/secondsMainPowerLost = 0 //The number of seconds until power is restored.
	var/secondsBackupPowerLost = 0 //The number of seconds until power is restored.
	var/spawnPowerRestoreRunning = FALSE
	var/lights = TRUE // bolt lights show by default
	var/aiDisabledIdScanner = FALSE
	var/aiHacking = FALSE
	var/closeOtherId //Cyclelinking for airlocks that aren't on the same x or y coord as the target.
	var/obj/machinery/door/airlock/closeOther
	var/justzap = FALSE
	var/obj/item/electronics/airlock/electronics
	var/shockCooldown = FALSE //Prevents multiple shocks from happening
	var/obj/item/doorCharge/charge //If applied, causes an explosion upon opening the door
	var/obj/item/note //Any papers pinned to the airlock
	var/detonated = FALSE
	var/abandoned = FALSE
	var/doorOpen = 'sound/machines/airlock.ogg'
	var/doorClose = 'sound/machines/airlockclose.ogg'
	var/doorDeni = 'sound/machines/deniedbeep.ogg' // i'm thinkin' Deni's
	var/boltUp = 'sound/machines/boltsup.ogg'
	var/boltDown = 'sound/machines/boltsdown.ogg'
	var/noPower = 'sound/machines/doorclick.ogg'
	var/previous_airlock = /obj/structure/door_assembly //what airlock assembly mineral plating was applied to
	var/wiretypepath = /datum/wires/airlock // which set of per round randomized wires this airlock type has.
	var/airlock_material //material of inner filling; if its an airlock with glass, this should be set to "glass"
	var/overlays_file = 'icons/obj/doors/airlocks/station/overlays.dmi'
	var/note_overlay_file = 'icons/obj/doors/airlocks/station/overlays.dmi' //Used for papers and photos pinned to the airlock
	var/cutAiWire = FALSE

	var/cyclelinkeddir = 0
	var/obj/machinery/door/airlock/cyclelinkedairlock
	var/shuttledocked = 0
	var/delayed_close_requested = FALSE // TRUE means the door will automatically close the next time it's opened.

	air_tight = FALSE
	var/prying_so_hard = FALSE

	rad_flags = RAD_PROTECT_CONTENTS | RAD_NO_CONTAMINATE
	rad_insulation = RAD_MEDIUM_INSULATION

	var/static/list/airlock_overlays = list()

	/// sigh
	var/unelectrify_timerid
	var/advactivator_action = FALSE

	/// For those airlocks you might want to have varying "fillings" for, without having to
	/// have an icon file per door with a different filling.
	var/fill_state_suffix = null
	/// For the airlocks that use greyscale lights, set this to the color you want your lights to be.
	var/greyscale_lights_color = null
	/// For the airlocks that use a greyscale accent door color, set this color to the accent color you want it to be.
	var/greyscale_accent_color = null

	var/has_environment_lights = TRUE //Does this airlock emit a light?
	var/light_color_poweron = AIRLOCK_POWERON_LIGHT_COLOR
	var/light_color_bolts = AIRLOCK_BOLTS_LIGHT_COLOR
	var/light_color_access = AIRLOCK_ACCESS_LIGHT_COLOR
	var/light_color_emergency = AIRLOCK_EMERGENCY_LIGHT_COLOR
	var/light_color_engineering = AIRLOCK_ENGINEERING_LIGHT_COLOR
	var/light_color_deny = AIRLOCK_DENY_LIGHT_COLOR
	var/door_light_range = AIRLOCK_LIGHT_RANGE
	var/door_light_power = AIRLOCK_LIGHT_POWER
	///Is this door external? E.g. does it lead to space? Shuttle docking systems bolt doors with this flag.
	var/external = FALSE

/obj/machinery/door/airlock/external
	external = TRUE

/obj/machinery/door/airlock/shuttle
	external = TRUE

/obj/machinery/door/airlock/power_change()
	..()
	update_icon()


/obj/machinery/door/airlock/Initialize(mapload)
	. = ..()
	wires = new wiretypepath(src) //CIT CHANGE - makes it possible for airlocks to have different wire datums
	if(frequency)
		set_frequency(frequency)

	if(closeOtherId != null)
		addtimer(CALLBACK(src, PROC_REF(update_other_id)), 5)
	if(glass)
		airlock_material = "glass"
	if(security_level > AIRLOCK_SECURITY_METAL)
		obj_integrity = normal_integrity * AIRLOCK_INTEGRITY_MULTIPLIER
		max_integrity = normal_integrity * AIRLOCK_INTEGRITY_MULTIPLIER
	else
		obj_integrity = normal_integrity
		max_integrity = normal_integrity
	if(damage_deflection == AIRLOCK_DAMAGE_DEFLECTION_N && security_level > AIRLOCK_SECURITY_METAL)
		damage_deflection = AIRLOCK_DAMAGE_DEFLECTION_R
	prepare_huds()
	for(var/datum/atom_hud/data/diagnostic/diag_hud in GLOB.huds)
		diag_hud.add_to_hud(src)
	diag_hud_set_electrified()

	return INITIALIZE_HINT_LATELOAD

/obj/machinery/door/airlock/LateInitialize()
	. = ..()
	if (cyclelinkeddir)
		cyclelinkairlock()
	if(abandoned)
		var/outcome = rand(1,100)
		switch(outcome)
			if(1 to 9)
				var/turf/here = get_turf(src)
				for(var/turf/closed/T in range(2, src))
					here.PlaceOnTop(T.type)
					qdel(src)
					return
				here.PlaceOnTop(/turf/closed/wall)
				qdel(src)
				return
			if(9 to 11)
				lights = FALSE
				locked = TRUE
			if(12 to 15)
				locked = TRUE
			if(16 to 23)
				welded = TRUE
			if(24 to 30)
				panel_open = TRUE
	update_icon()

/obj/machinery/door/airlock/ComponentInitialize()
	. = ..()
	AddComponent(/datum/component/ntnet_interface)

/obj/machinery/door/airlock/connect_to_shuttle(obj/docking_port/mobile/port, obj/docking_port/stationary/dock, idnum, override=FALSE)
	if(id_tag)
		id_tag = "[idnum][id_tag]"

/obj/machinery/door/airlock/proc/update_other_id()
	for(var/obj/machinery/door/airlock/A in GLOB.airlocks)
		if(A.closeOtherId == closeOtherId && A != src)
			closeOther = A
			break

/obj/machinery/door/airlock/proc/cyclelinkairlock()
	if (cyclelinkedairlock)
		cyclelinkedairlock.cyclelinkedairlock = null
		cyclelinkedairlock = null
	if (!cyclelinkeddir)
		return
	var/limit = world.view
	var/turf/T = get_turf(src)
	var/obj/machinery/door/airlock/FoundDoor
	do
		T = get_step(T, cyclelinkeddir)
		FoundDoor = locate() in T
		if (FoundDoor && FoundDoor.cyclelinkeddir != get_dir(FoundDoor, src))
			FoundDoor = null
		limit--
	while(!FoundDoor && limit)
	if (!FoundDoor)
		log_mapping("[src] at [AREACOORD(src)] failed to find a valid airlock to cyclelink with!")
		return
	FoundDoor.cyclelinkedairlock = src
	cyclelinkedairlock = FoundDoor

/obj/machinery/door/airlock/vv_edit_var(var_name)
	. = ..()
	switch (var_name)
		if (NAMEOF(src, cyclelinkeddir))
			cyclelinkairlock()

/obj/machinery/door/airlock/check_access_ntnet(datum/netdata/data)
	return !requiresID() || ..()

/obj/machinery/door/airlock/ntnet_receive(datum/netdata/data)
	// Check if the airlock is powered and can accept control packets.
	if(!hasPower() || !canAIControl())
		return

	// Check packet access level.
	if(!check_access_ntnet(data))
		return

	// Handle received packet.
	var/command = lowertext(data.data["data"])
	var/command_value = lowertext(data.data["data_secondary"])
	switch(command)
		if("open")
			if(command_value == "on" && !density)
				return

			if(command_value == "off" && density)
				return

			if(density)
				INVOKE_ASYNC(src, PROC_REF(open))
			else
				INVOKE_ASYNC(src, PROC_REF(close))

		if("bolt")
			if(command_value == "on" && locked)
				return

			if(command_value == "off" && !locked)
				return

			if(locked)
				unbolt()
			else
				bolt()

		if("emergency")
			if(command_value == "on" && emergency)
				return

			if(command_value == "off" && !emergency)
				return

			emergency = !emergency
			update_icon()

/obj/machinery/door/airlock/lock()
	bolt()

/obj/machinery/door/airlock/proc/bolt()
	if(locked)
		return
	locked = TRUE
	playsound(src,boltDown,30,0,3)
	audible_message("<span class='italics'>You hear a click from the bottom of the door.</span>", null,  1)
	update_icon()

/obj/machinery/door/airlock/unlock()
	unbolt()

/obj/machinery/door/airlock/proc/unbolt()
	if(!locked)
		return
	locked = FALSE
	playsound(src,boltUp,30,0,3)
	audible_message("<span class='italics'>You hear a click from the bottom of the door.</span>", null,  1)
	update_icon()

/obj/machinery/door/airlock/narsie_act()
	var/turf/T = get_turf(src)
	var/obj/machinery/door/airlock/cult/A
	if(GLOB.cult_narsie)
		var/runed = prob(20)
		if(glass)
			if(runed)
				A = new/obj/machinery/door/airlock/cult/glass(T)
			else
				A = new/obj/machinery/door/airlock/cult/unruned/glass(T)
		else
			if(runed)
				A = new/obj/machinery/door/airlock/cult(T)
			else
				A = new/obj/machinery/door/airlock/cult/unruned(T)
		A.name = name
	else
		A = new /obj/machinery/door/airlock/cult/weak(T)
	qdel(src)

/obj/machinery/door/airlock/ratvar_act() //Airlocks become pinion airlocks that only allow servants
	var/obj/machinery/door/airlock/clockwork/A
	if(glass)
		A = new/obj/machinery/door/airlock/clockwork/brass(get_turf(src))
	else
		A = new/obj/machinery/door/airlock/clockwork(get_turf(src))
	A.name = name
	qdel(src)

/obj/machinery/door/airlock/Destroy()
	QDEL_NULL(wires)
	QDEL_NULL(electronics)
	if(charge)
		qdel(charge)
		charge = null
	if (cyclelinkedairlock)
		if (cyclelinkedairlock.cyclelinkedairlock == src)
			cyclelinkedairlock.cyclelinkedairlock = null
		cyclelinkedairlock = null
	if(id_tag)
		for(var/obj/machinery/doorButtons/D in GLOB.machines)
			D.removeMe(src)
	QDEL_NULL(note)
	for(var/datum/atom_hud/data/diagnostic/diag_hud in GLOB.huds)
		diag_hud.remove_from_hud(src)
	return ..()

/obj/machinery/door/airlock/handle_atom_del(atom/A)
	if(A == note)
		note = null
		update_icon()

/obj/machinery/door/airlock/bumpopen(mob/living/user) //Airlocks now zap you when you 'bump' them open when they're electrified. --NeoFite
	if(!issilicon(usr))
		if(isElectrified())
			if(!justzap)
				if(shock(user, 100))
					justzap = TRUE
					addtimer(VARSET_CALLBACK(src, justzap, FALSE) , 10)
					return
			else
				return
		else if(user.hallucinating() && ishuman(user) && prob(1) && !operating)
			var/mob/living/carbon/human/H = user
			if(H.gloves)
				var/obj/item/clothing/gloves/G = H.gloves
				if(G.siemens_coefficient)//not insulated
					new /datum/hallucination/shock(H)
					return
	if (cyclelinkedairlock)
		if (!shuttledocked && !emergency && !cyclelinkedairlock.shuttledocked && !cyclelinkedairlock.emergency && allowed(user))
			if(cyclelinkedairlock.operating)
				cyclelinkedairlock.delayed_close_requested = TRUE
			else
				addtimer(CALLBACK(cyclelinkedairlock, PROC_REF(close)), 2)
	if(ishuman(user) && prob(5) && src.density)
		var/mob/living/carbon/human/H = user
		if((HAS_TRAIT(H, TRAIT_DUMB)) && Adjacent(user))
			playsound(src.loc, 'sound/effects/bang.ogg', 25, 1)
			if(!istype(H.head, /obj/item/clothing/head/helmet))
				H.visible_message("<span class='danger'>[user] headbutts the airlock.</span>", \
									"<span class='userdanger'>You headbutt the airlock!</span>")
				H.DefaultCombatKnockdown(100)
				H.apply_damage(1, BRUTE, BODY_ZONE_HEAD)
			else
				visible_message("<span class='danger'>[user] headbutts the airlock. Good thing [user] is wearing a helmet.</span>")
	..()

/obj/machinery/door/airlock/proc/isElectrified()
	if(src.secondsElectrified != NOT_ELECTRIFIED)
		return TRUE
	return FALSE

/obj/machinery/door/airlock/proc/canAIControl(mob/user)
	return ((aiControlDisabled != 1) && !isAllPowerCut())

/obj/machinery/door/airlock/proc/canAIHack()
	return ((aiControlDisabled==1) && (!hackProof) && (!isAllPowerCut()));

/obj/machinery/door/airlock/hasPower()
	return ((!secondsMainPowerLost || !secondsBackupPowerLost) && !(machine_stat & NOPOWER))

/obj/machinery/door/airlock/requiresID()
	return !(wires.is_cut(WIRE_IDSCAN) || aiDisabledIdScanner)

/obj/machinery/door/airlock/proc/isAllPowerCut()
	if((wires.is_cut(WIRE_POWER1) || wires.is_cut(WIRE_POWER2)) && (wires.is_cut(WIRE_BACKUP1) || wires.is_cut(WIRE_BACKUP2)))
		return TRUE

/obj/machinery/door/airlock/proc/regainMainPower()
	if(src.secondsMainPowerLost > 0)
		src.secondsMainPowerLost = 0
	update_icon()

/obj/machinery/door/airlock/proc/handlePowerRestore()
	var/cont = TRUE
	while (cont)
		sleep(10)
		if(QDELETED(src))
			return
		cont = FALSE
		if(secondsMainPowerLost>0)
			if(!wires.is_cut(WIRE_POWER1) && !wires.is_cut(WIRE_POWER2))
				secondsMainPowerLost -= 1
				updateDialog()
			cont = TRUE
		if(secondsBackupPowerLost>0)
			if(!wires.is_cut(WIRE_BACKUP1) && !wires.is_cut(WIRE_BACKUP2))
				secondsBackupPowerLost -= 1
				updateDialog()
			cont = TRUE
	spawnPowerRestoreRunning = FALSE
	updateDialog()
	update_icon()

/obj/machinery/door/airlock/proc/loseMainPower()
	if(secondsMainPowerLost <= 0)
		secondsMainPowerLost = 60
		if(secondsBackupPowerLost < 10)
			secondsBackupPowerLost = 10
	if(!spawnPowerRestoreRunning)
		spawnPowerRestoreRunning = TRUE
	INVOKE_ASYNC(src, PROC_REF(handlePowerRestore))
	update_icon()

/obj/machinery/door/airlock/proc/loseBackupPower()
	if(src.secondsBackupPowerLost < 60)
		src.secondsBackupPowerLost = 60
	if(!spawnPowerRestoreRunning)
		spawnPowerRestoreRunning = TRUE
	INVOKE_ASYNC(src, PROC_REF(handlePowerRestore))
	update_icon()

/obj/machinery/door/airlock/proc/regainBackupPower()
	if(src.secondsBackupPowerLost > 0)
		src.secondsBackupPowerLost = 0
	update_icon()

// shock user with probability prb (if all connections & power are working)
// returns TRUE if shocked, FALSE otherwise
// The preceding comment was borrowed from the grille's shock script
/obj/machinery/door/airlock/proc/shock(mob/living/user, prb)
	if(!istype(user) || !hasPower())		// unpowered, no shock
		return FALSE
	if(shockCooldown > world.time)
		return FALSE	//Already shocked someone recently?
	if(!prob(prb))
		return FALSE //you lucked out, no shock for you
	do_sparks(5, TRUE, src)
	var/check_range = TRUE
	if(electrocute_mob(user, get_area(src), src, 1, check_range))
		shockCooldown = world.time + 10
		return TRUE
	else
		return FALSE

/obj/machinery/door/airlock/update_icon(state=0, override=0)
	if(operating && !override)
		return
	switch(state)
		if(0)
			if(density)
				state = AIRLOCK_CLOSED
			else
				state = AIRLOCK_OPEN
			icon_state = ""
		if(AIRLOCK_OPEN, AIRLOCK_CLOSED)
			icon_state = ""
		if(AIRLOCK_DENY, AIRLOCK_OPENING, AIRLOCK_CLOSING, AIRLOCK_EMAG)
			icon_state = "nonexistenticonstate" //MADNESS
	set_airlock_overlays(state)

/obj/machinery/door/airlock/proc/set_airlock_overlays(state)
	var/mutable_appearance/frame_overlay
	var/mutable_appearance/filling_overlay
	var/mutable_appearance/lights_overlay
	var/mutable_appearance/panel_overlay
	var/mutable_appearance/weld_overlay
	var/mutable_appearance/damag_overlay
	var/mutable_appearance/sparks_overlay
	var/mutable_appearance/note_overlay
	var/notetype = note_type()

	switch(state)
		if(AIRLOCK_CLOSED)
			frame_overlay = get_airlock_overlay("closed", icon)
			if(airlock_material)
				filling_overlay = get_airlock_overlay("[airlock_material]_closed", overlays_file)
			else
				filling_overlay = get_airlock_overlay("fill_closed", icon)
			if(panel_open)
				if(security_level)
					panel_overlay = get_airlock_overlay("panel_closed_protected", overlays_file)
				else
					panel_overlay = get_airlock_overlay("panel_closed", overlays_file)
			if(welded)
				weld_overlay = get_airlock_overlay("welded", overlays_file)
			if(obj_integrity < integrity_failure * max_integrity)
				damag_overlay = get_airlock_overlay("sparks_broken", overlays_file, ABOVE_LIGHTING_LAYER, ABOVE_LIGHTING_PLANE)
			else if(obj_integrity < (0.75 * max_integrity))
				damag_overlay = get_airlock_overlay("sparks_damaged", overlays_file, ABOVE_LIGHTING_LAYER, ABOVE_LIGHTING_PLANE)
			if(lights && hasPower())

				if(locked)
					lights_overlay = get_airlock_overlay("lights_bolts", overlays_file, ABOVE_LIGHTING_LAYER, ABOVE_LIGHTING_PLANE)
				else if(emergency)
					lights_overlay = get_airlock_overlay("lights_emergency", overlays_file, ABOVE_LIGHTING_LAYER, ABOVE_LIGHTING_PLANE)
				else
					lights_overlay = get_airlock_overlay("lights_poweron", overlays_file, ABOVE_LIGHTING_LAYER, ABOVE_LIGHTING_PLANE)
					light_color = LIGHT_COLOR_BLUE
			if(note)
				note_overlay = get_airlock_overlay(notetype, note_overlay_file)

		if(AIRLOCK_DENY)
			if(!hasPower())
				return
			frame_overlay = get_airlock_overlay("closed", icon)
			if(airlock_material)
				filling_overlay = get_airlock_overlay("[airlock_material]_closed", overlays_file)
			else
				filling_overlay = get_airlock_overlay("fill_closed", icon)
			if(panel_open)
				if(security_level)
					panel_overlay = get_airlock_overlay("panel_closed_protected", overlays_file)
				else
					panel_overlay = get_airlock_overlay("panel_closed", overlays_file)
			if(obj_integrity < integrity_failure * max_integrity)
				damag_overlay = get_airlock_overlay("sparks_broken", overlays_file, ABOVE_LIGHTING_LAYER, ABOVE_LIGHTING_PLANE)
			else if(obj_integrity < (0.75 * max_integrity))
				damag_overlay = get_airlock_overlay("sparks_damaged", overlays_file, ABOVE_LIGHTING_LAYER, ABOVE_LIGHTING_PLANE)
			if(welded)
				weld_overlay = get_airlock_overlay("welded", overlays_file)
			lights_overlay = get_airlock_overlay("lights_denied", overlays_file, ABOVE_LIGHTING_LAYER, ABOVE_LIGHTING_PLANE)
			if(note)
				note_overlay = get_airlock_overlay(notetype, note_overlay_file)

		if(AIRLOCK_EMAG)
			frame_overlay = get_airlock_overlay("closed", icon)
			sparks_overlay = get_airlock_overlay("sparks", overlays_file, ABOVE_LIGHTING_LAYER, ABOVE_LIGHTING_PLANE)
			if(airlock_material)
				filling_overlay = get_airlock_overlay("[airlock_material]_closed", overlays_file)
			else
				filling_overlay = get_airlock_overlay("fill_closed", icon)
			if(panel_open)
				if(security_level)
					panel_overlay = get_airlock_overlay("panel_closed_protected", overlays_file)
				else
					panel_overlay = get_airlock_overlay("panel_closed", overlays_file)
			if(obj_integrity < integrity_failure * max_integrity)
				damag_overlay = get_airlock_overlay("sparks_broken", overlays_file, ABOVE_LIGHTING_LAYER, ABOVE_LIGHTING_PLANE)
			else if(obj_integrity < (0.75 * max_integrity))
				damag_overlay = get_airlock_overlay("sparks_damaged", overlays_file, ABOVE_LIGHTING_LAYER, ABOVE_LIGHTING_PLANE)
			if(welded)
				weld_overlay = get_airlock_overlay("welded", overlays_file)
			if(note)
				note_overlay = get_airlock_overlay(notetype, note_overlay_file)

		if(AIRLOCK_CLOSING)
			frame_overlay = get_airlock_overlay("closing", icon)
			if(airlock_material)
				filling_overlay = get_airlock_overlay("[airlock_material]_closing", overlays_file)
			else
				filling_overlay = get_airlock_overlay("fill_closing", icon)
			if(lights && hasPower())
				lights_overlay = get_airlock_overlay("lights_closing", overlays_file, ABOVE_LIGHTING_LAYER, ABOVE_LIGHTING_PLANE)
			if(panel_open)
				if(security_level)
					panel_overlay = get_airlock_overlay("panel_closing_protected", overlays_file)
				else
					panel_overlay = get_airlock_overlay("panel_closing", overlays_file)
			if(note)
				note_overlay = get_airlock_overlay("[notetype]_closing", note_overlay_file)

		if(AIRLOCK_OPEN)
			frame_overlay = get_airlock_overlay("open", icon)
			if(airlock_material)
				filling_overlay = get_airlock_overlay("[airlock_material]_open", overlays_file)
			else
				filling_overlay = get_airlock_overlay("fill_open", icon)
			if(panel_open)
				if(security_level)
					panel_overlay = get_airlock_overlay("panel_open_protected", overlays_file)
				else
					panel_overlay = get_airlock_overlay("panel_open", overlays_file)
			if(obj_integrity < (0.75 * max_integrity))
				damag_overlay = get_airlock_overlay("sparks_open", overlays_file, ABOVE_LIGHTING_LAYER, ABOVE_LIGHTING_PLANE)
			if(note)
				note_overlay = get_airlock_overlay("[notetype]_open", note_overlay_file)

		if(AIRLOCK_OPENING)
			frame_overlay = get_airlock_overlay("opening", icon)
			if(airlock_material)
				filling_overlay = get_airlock_overlay("[airlock_material]_opening", overlays_file)
			else
				filling_overlay = get_airlock_overlay("fill_opening", icon)
			if(lights && hasPower())
				lights_overlay = get_airlock_overlay("lights_opening", overlays_file, ABOVE_LIGHTING_LAYER, ABOVE_LIGHTING_PLANE)
			if(panel_open)
				if(security_level)
					panel_overlay = get_airlock_overlay("panel_opening_protected", overlays_file)
				else
					panel_overlay = get_airlock_overlay("panel_opening", overlays_file)
			if(note)
				note_overlay = get_airlock_overlay("[notetype]_opening", note_overlay_file)

	cut_overlays()
	add_overlay(frame_overlay)
	add_overlay(filling_overlay)
	if(lights_overlay)
		add_overlay(lights_overlay)
		var/mutable_appearance/lights_vis = mutable_appearance(lights_overlay.icon, lights_overlay.icon_state)
		add_overlay(lights_vis)
	add_overlay(panel_overlay)
	add_overlay(weld_overlay)
	add_overlay(sparks_overlay)
	if(damag_overlay)
		add_overlay(damag_overlay)
		var/mutable_appearance/damage_vis = mutable_appearance(damag_overlay.icon, damag_overlay.icon_state)
		add_overlay(damage_vis)
	add_overlay(note_overlay)
	check_unres()

/proc/get_airlock_overlay(icon_state, icon_file, targetlayer = FLOAT_LAYER, targetplane = FLOAT_PLANE)
	var/obj/machinery/door/airlock/A
	pass(A)	//suppress unused warning
	var/list/airlock_overlays = A.airlock_overlays
	var/iconkey = "[icon_state][icon_file]"
	if((!(. = airlock_overlays[iconkey])))
		. = airlock_overlays[iconkey] = mutable_appearance(icon_file, icon_state, targetlayer, targetplane)

/obj/machinery/door/airlock/proc/check_unres() //unrestricted sides. This overlay indicates which directions the player can access even without an ID
	if(hasPower() && unres_sides)
		if(unres_sides & NORTH)
			var/image/I = image(icon='icons/obj/doors/airlocks/station/overlays.dmi', icon_state="unres_n") //layer=src.layer+1
			I.pixel_y = 32
			set_light(l_range = 2, l_power = 1)
			add_overlay(I)
		if(unres_sides & SOUTH)
			var/image/I = image(icon='icons/obj/doors/airlocks/station/overlays.dmi', icon_state="unres_s") //layer=src.layer+1
			I.pixel_y = -32
			set_light(l_range = 2, l_power = 1)
			add_overlay(I)
		if(unres_sides & EAST)
			var/image/I = image(icon='icons/obj/doors/airlocks/station/overlays.dmi', icon_state="unres_e") //layer=src.layer+1
			I.pixel_x = 32
			set_light(l_range = 2, l_power = 1)
			add_overlay(I)
		if(unres_sides & WEST)
			var/image/I = image(icon='icons/obj/doors/airlocks/station/overlays.dmi', icon_state="unres_w") //layer=src.layer+1
			I.pixel_x = -32
			set_light(l_range = 2, l_power = 1)
			add_overlay(I)
	else
		if(lights && hasPower())
			if(locked)
				set_light(1, 0.1, "#0000FF")
			else if(emergency)
				set_light(1, 0.1, "#FFFF00")
			else
				set_light(0)
		else
			set_light(0)

/obj/machinery/door/airlock/update_overlays()
	. = ..()
	var/pre_light_range = 0
	var/pre_light_power = 0
	var/pre_light_color = ""
	var/lights_overlay = ""

	var/frame_state
	var/light_state
	switch(airlock_state)
		if(AIRLOCK_CLOSED)
			frame_state = AIRLOCK_FRAME_CLOSED
			if(locked)
				light_state = AIRLOCK_LIGHT_BOLTS
				lights_overlay = "lights_bolts"
				pre_light_color = light_color_bolts
			else if(emergency)
				light_state = AIRLOCK_LIGHT_EMERGENCY
				lights_overlay = "lights_emergency"
				pre_light_color = light_color_emergency
			else
				lights_overlay = "lights_poweron"
				pre_light_color = light_color_poweron
		if(AIRLOCK_DENY)
			frame_state = AIRLOCK_FRAME_CLOSED
			light_state = AIRLOCK_LIGHT_DENIED
			lights_overlay = "lights_denied"
			pre_light_color = light_color_deny
		if(AIRLOCK_EMAG)
			frame_state = AIRLOCK_FRAME_CLOSED
		if(AIRLOCK_CLOSING)
			frame_state = AIRLOCK_FRAME_CLOSING
			light_state = AIRLOCK_LIGHT_CLOSING
			lights_overlay = "lights_closing"
			pre_light_color = light_color_access
		if(AIRLOCK_OPEN)
			frame_state = AIRLOCK_FRAME_OPEN
			if(locked)
				lights_overlay = "lights_bolts_open"
				pre_light_color = light_color_bolts
			else if(emergency)
				lights_overlay = "lights_emergency_open"
				pre_light_color = light_color_emergency
			else
				lights_overlay = "lights_poweron_open"
				pre_light_color = light_color_poweron
		if(AIRLOCK_OPENING)
			frame_state = AIRLOCK_FRAME_OPENING
			light_state = AIRLOCK_LIGHT_OPENING
			lights_overlay = "lights_opening"
			pre_light_color = light_color_access

	. += get_airlock_overlay(frame_state, icon, targetlayer = FLOAT_LAYER, targetplane = FLOAT_PLANE)
	if(airlock_material)
		. += get_airlock_overlay("[airlock_material]_[frame_state]", overlays_file, targetlayer = FLOAT_LAYER, targetplane = FLOAT_PLANE)
	else
		. += get_airlock_overlay("fill_[frame_state + fill_state_suffix]", icon, targetlayer = FLOAT_LAYER, targetplane = FLOAT_PLANE)

	if(greyscale_lights_color && !light_state)
		lights_overlay += "_greyscale"

	if(lights && hasPower())
		. += get_airlock_overlay("lights_[light_state]", overlays_file, targetlayer = FLOAT_LAYER, targetplane = FLOAT_PLANE)
		pre_light_range = door_light_range
		pre_light_power = door_light_power
		if(has_environment_lights)
			set_light(pre_light_range, pre_light_power, pre_light_color, TRUE)
			// if(multi_tile)
			// 	filler.set_light(pre_light_range, pre_light_power, pre_light_color)
	else
		lights_overlay = ""

	var/mutable_appearance/lights_appearance = mutable_appearance(overlays_file, lights_overlay, FLOAT_LAYER, src, ABOVE_LIGHTING_PLANE)

	if(greyscale_lights_color && !light_state)
		lights_appearance.color = greyscale_lights_color

	// if(multi_tile)
	// 	lights_appearance.dir = dir

	. += lights_appearance

	if(greyscale_accent_color)
		. += get_airlock_overlay("[frame_state]_accent", overlays_file, targetlayer = FLOAT_LAYER, targetplane = FLOAT_PLANE)

	if(panel_open)
		. += get_airlock_overlay("panel_[frame_state][security_level ? "_protected" : null]", overlays_file, targetlayer = FLOAT_LAYER, targetplane = FLOAT_PLANE)
	if(frame_state == AIRLOCK_FRAME_CLOSED && welded)
		. += get_airlock_overlay("welded", overlays_file, targetlayer = FLOAT_LAYER, targetplane = FLOAT_PLANE)

	if(airlock_state == AIRLOCK_EMAG)
		. += get_airlock_overlay("sparks", overlays_file, targetlayer = FLOAT_LAYER, targetplane = FLOAT_PLANE)

	if(hasPower())
		if(frame_state == AIRLOCK_FRAME_CLOSED)
			if(obj_integrity < integrity_failure * max_integrity)
				. += get_airlock_overlay("sparks_broken", overlays_file, targetlayer = FLOAT_LAYER, targetplane = FLOAT_PLANE)
			else if(obj_integrity < (0.75 * max_integrity))
				. += get_airlock_overlay("sparks_damaged", overlays_file, targetlayer = FLOAT_LAYER, targetplane = FLOAT_PLANE)
		else if(frame_state == AIRLOCK_FRAME_OPEN)
			if(obj_integrity < (0.75 * max_integrity))
				. += get_airlock_overlay("sparks_open", overlays_file, targetlayer = FLOAT_LAYER, targetplane = FLOAT_PLANE)

	if(hasPower() && unres_sides)
		for(var/heading in list(NORTH,SOUTH,EAST,WEST))
			if(!(unres_sides & heading))
				continue
			var/mutable_appearance/floorlight = mutable_appearance('icons/obj/doors/airlocks/station/overlays.dmi', "unres_[heading]", FLOAT_LAYER, src, ABOVE_LIGHTING_PLANE)
			switch (heading)
				if (NORTH)
					floorlight.pixel_x = 0
					floorlight.pixel_y = 32
				if (SOUTH)
					floorlight.pixel_x = 0
					floorlight.pixel_y = -32
				if (EAST)
					floorlight.pixel_x = 32
					floorlight.pixel_y = 0
				if (WEST)
					floorlight.pixel_x = -32
					floorlight.pixel_y = 0
			. += floorlight

/obj/machinery/door/airlock/do_animate(animation)
	switch(animation)
		if("opening")
			update_icon(AIRLOCK_OPENING)
		if("closing")
			update_icon(AIRLOCK_CLOSING)
		if("deny")
			if(!machine_stat)
				update_icon(AIRLOCK_DENY)
				playsound(src,doorDeni,50,0,3)
				sleep(6)
				update_icon(AIRLOCK_CLOSED)

/obj/machinery/door/airlock/examine(mob/user)
	. = ..()
	if(obj_flags & EMAGGED)
		. += "<span class='warning'>Its access panel is smoking slightly.</span>"
	if(charge && !panel_open && in_range(user, src))
		. += "<span class='warning'>The maintenance panel seems haphazardly fastened.</span>"
	if(charge && panel_open)
		. += "<span class='warning'>Something is wired up to the airlock's electronics!</span>"
	if(note)
		if(!in_range(user, src))
			. += "There's a [note.name] pinned to the front. You can't read it from here."
		else
			. += "There's a [note.name] pinned to the front..."
			. += note.examine(user)

	if(panel_open)
		switch(security_level)
			if(AIRLOCK_SECURITY_NONE)
				. += "Its wires are exposed!"
			if(AIRLOCK_SECURITY_METAL)
				. += "Its wires are hidden behind a welded metal cover."
			if(AIRLOCK_SECURITY_PLASTEEL_I_S)
				. += "There is some shredded plasteel inside."
			if(AIRLOCK_SECURITY_PLASTEEL_I)
				. += "Its wires are behind an inner layer of plasteel."
			if(AIRLOCK_SECURITY_PLASTEEL_O_S)
				. += "There is some shredded plasteel inside."
			if(AIRLOCK_SECURITY_PLASTEEL_O)
				. += "There is a welded plasteel cover hiding its wires."
			if(AIRLOCK_SECURITY_PLASTEEL)
				. += "There is a protective grille over its panel."
	else if(security_level)
		if(security_level == AIRLOCK_SECURITY_METAL)
			. += "It looks a bit stronger."
		else
			. += "It looks very robust."

	if(hasSiliconAccessInArea(user) && !(machine_stat & BROKEN))
		. += "<span class='notice'>Shift-click [src] to [ density ? "open" : "close"] it.</span>"
		. += "<span class='notice'>Ctrl-click [src] to [ locked ? "raise" : "drop"] its bolts.</span>"
		. += "<span class='notice'>Alt-click [src] to [ secondsElectrified ? "un-electrify" : "permanently electrify"] it.</span>"
		. += "<span class='notice'>Ctrl-Shift-click [src] to [ emergency ? "disable" : "enable"] emergency access.</span>"

/obj/machinery/door/airlock/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	. = ..()

	if(hasSiliconAccessInArea(user))
		LAZYSET(context[SCREENTIP_CONTEXT_LMB], INTENT_ANY, "Open interface")
		LAZYSET(context[SCREENTIP_CONTEXT_SHIFT_LMB], INTENT_ANY, density ? "Open" : "Close")
		LAZYSET(context[SCREENTIP_CONTEXT_CTRL_LMB], INTENT_ANY, locked ? "Unbolt" : "Bolt")
		LAZYSET(context[SCREENTIP_CONTEXT_ALT_LMB], INTENT_ANY, secondsElectrified ? "Un-electrify" : "Electrify")
		LAZYSET(context[SCREENTIP_CONTEXT_CTRL_SHIFT_LMB], INTENT_ANY, emergency ? "Disable emergency access" : "Enable emergency access")
		. = CONTEXTUAL_SCREENTIP_SET

	if(istype(held_item, /obj/item/stack/sheet/plasteel))
		LAZYSET(context[SCREENTIP_CONTEXT_LMB], INTENT_ANY, "Reinforce")
		return CONTEXTUAL_SCREENTIP_SET

	switch (held_item?.tool_behaviour)
		if (TOOL_CROWBAR)
			if (panel_open)
				if (security_level == AIRLOCK_SECURITY_PLASTEEL_O_S || security_level == AIRLOCK_SECURITY_PLASTEEL_I_S)
					LAZYSET(context[SCREENTIP_CONTEXT_LMB], INTENT_ANY, "Remove shielding")
					return CONTEXTUAL_SCREENTIP_SET
				else if (should_try_removing_electronics())
					LAZYSET(context[SCREENTIP_CONTEXT_LMB], INTENT_ANY, "Remove electronics")
					return CONTEXTUAL_SCREENTIP_SET

			// Not always contextually true, but is contextually false in ways that make gameplay interesting.
			// For example, trying to pry open an airlock, only for the bolts to be down and the lights off.
			LAZYSET(context[SCREENTIP_CONTEXT_LMB], INTENT_ANY, "Pry open")

			return CONTEXTUAL_SCREENTIP_SET
		if (TOOL_WELDER)
			LAZYSET(context[SCREENTIP_CONTEXT_LMB], INTENT_HARM, "Weld shut")

			if (panel_open)
				switch (security_level)
					if (AIRLOCK_SECURITY_METAL, AIRLOCK_SECURITY_PLASTEEL_I, AIRLOCK_SECURITY_PLASTEEL_O)
						LAZYSET(context[SCREENTIP_CONTEXT_LMB], INTENT_HARM, "Cut shielding")
						return CONTEXTUAL_SCREENTIP_SET

			LAZYSET(context[SCREENTIP_CONTEXT_LMB], INTENT_ANY, "Repair")
			return CONTEXTUAL_SCREENTIP_SET

	return .

/obj/machinery/door/airlock/attack_ai(mob/user)
	if(!src.canAIControl(user))
		if(src.canAIHack())
			src.hack(user)
			return
		else
			to_chat(user, "<span class='warning'>Airlock AI control has been blocked with a firewall. Unable to hack.</span>")
	if(obj_flags & EMAGGED)
		to_chat(user, "<span class='warning'>Unable to interface: Airlock is unresponsive.</span>")
		return
	if(detonated)
		to_chat(user, "<span class='warning'>Unable to interface. Airlock control panel damaged.</span>")
		return

	ui_interact(user)

/obj/machinery/door/airlock/proc/hack(mob/user)
	set waitfor = 0
	if(!aiHacking)
		aiHacking = TRUE
		to_chat(user, "Airlock AI control has been blocked. Beginning fault-detection.")
		sleep(50)
		if(src.canAIControl(user))
			to_chat(user, "Alert cancelled. Airlock control has been restored without our assistance.")
			aiHacking = FALSE
			return
		else if(!src.canAIHack())
			to_chat(user, "Connection lost! Unable to hack airlock.")
			aiHacking = FALSE
			return
		to_chat(user, "Fault confirmed: airlock control wire disabled or cut.")
		sleep(20)
		to_chat(user, "Attempting to hack into airlock. This may take some time.")
		sleep(200)
		if(src.canAIControl(user))
			to_chat(user, "Alert cancelled. Airlock control has been restored without our assistance.")
			aiHacking = FALSE
			return
		else if(!src.canAIHack())
			to_chat(user, "Connection lost! Unable to hack airlock.")
			aiHacking = FALSE
			return
		to_chat(user, "Upload access confirmed. Loading control program into airlock software.")
		sleep(170)
		if(src.canAIControl(user))
			to_chat(user, "Alert cancelled. Airlock control has been restored without our assistance.")
			aiHacking = FALSE
			return
		else if(!src.canAIHack())
			to_chat(user, "Connection lost! Unable to hack airlock.")
			aiHacking = FALSE
			return
		to_chat(user, "Transfer complete. Forcing airlock to execute program.")
		sleep(50)
		//disable blocked control
		src.aiControlDisabled = 2
		to_chat(user, "Receiving control information from airlock.")
		sleep(10)
		//bring up airlock dialog
		aiHacking = FALSE
		if(user)
			src.attack_ai(user)

/obj/machinery/door/airlock/attack_animal(mob/user)
	. = ..()
	if(isElectrified())
		shock(user, 100)

/obj/machinery/door/airlock/attack_paw(mob/user)
	return attack_hand(user)

/obj/machinery/door/airlock/on_attack_hand(mob/user, act_intent = user.a_intent, unarmed_attack_flags)
	if(!(issilicon(user) || IsAdminGhost(user)))
		if(isElectrified())
			if(shock(user, 100))
				return
	return ..()

/obj/machinery/door/airlock/attempt_wire_interaction(mob/user)
	if(security_level)
		to_chat(user, "<span class='warning'>Wires are protected!</span>")
		return WIRE_INTERACTION_FAIL
	return ..()

/obj/machinery/door/airlock/Topic(href, href_list, var/nowindow = 0)
	// If you add an if(..()) check you must first remove the var/nowindow parameter.
	// Otherwise it will runtime with this kind of error: null.Topic()
	if(!nowindow)
		..()
	if(!usr.canUseTopic(src) && !IsAdminGhost(usr))
		return
	add_fingerprint(usr)

	if((in_range(src, usr) && isturf(loc)) && panel_open)
		usr.set_machine(src)

	add_fingerprint(usr)
	if(!nowindow)
		updateUsrDialog()
	else
		updateDialog()


/obj/machinery/door/airlock/attackby(obj/item/C, mob/user, params)
	if(!issilicon(user) && !IsAdminGhost(user))
		if(isElectrified())
			if(shock(user, 75))
				return
	add_fingerprint(user)

	if(panel_open)
		switch(security_level)
			if(AIRLOCK_SECURITY_NONE)
				if(istype(C, /obj/item/stack/sheet/metal))
					var/obj/item/stack/sheet/metal/S = C
					if(S.get_amount() < 2)
						to_chat(user, "<span class='warning'>You need at least 2 metal sheets to reinforce [src].</span>")
						return
					to_chat(user, "<span class='notice'>You start reinforcing [src].</span>")
					if(do_after(user, 20, TRUE, target = src))
						if(!panel_open || !S.use(2))
							return
						user.visible_message("<span class='notice'>[user] reinforces \the [src] with metal.</span>",
											"<span class='notice'>You reinforce \the [src] with metal.</span>")
						security_level = AIRLOCK_SECURITY_METAL
						update_icon()
					return
				else if(istype(C, /obj/item/stack/sheet/plasteel))
					var/obj/item/stack/sheet/plasteel/S = C
					if(S.get_amount() < 2)
						to_chat(user, "<span class='warning'>You need at least 2 plasteel sheets to reinforce [src].</span>")
						return
					to_chat(user, "<span class='notice'>You start reinforcing [src].</span>")
					if(do_after(user, 20, 1, target = src))
						if(!panel_open || !S.use(2))
							return
						user.visible_message("<span class='notice'>[user] reinforces \the [src] with plasteel.</span>",
											"<span class='notice'>You reinforce \the [src] with plasteel.</span>")
						security_level = AIRLOCK_SECURITY_PLASTEEL
						modify_max_integrity(normal_integrity * AIRLOCK_INTEGRITY_MULTIPLIER)
						damage_deflection = AIRLOCK_DAMAGE_DEFLECTION_R
						update_icon()
					return
			if(AIRLOCK_SECURITY_METAL)
				if(C.tool_behaviour == TOOL_WELDER)
					if(!C.tool_start_check(user, amount=2))
						return
					to_chat(user, "<span class='notice'>You begin cutting the panel's shielding...</span>")
					if(C.use_tool(src, user, 40, volume=50, amount = 2))
						if(!panel_open)
							return
						user.visible_message("<span class='notice'>[user] cuts through \the [src]'s shielding.</span>",
										"<span class='notice'>You cut through \the [src]'s shielding.</span>",
										"<span class='italics'>You hear welding.</span>")
						security_level = AIRLOCK_SECURITY_NONE
						spawn_atom_to_turf(/obj/item/stack/sheet/metal, user.loc, 2)
						update_icon()
					return
			if(AIRLOCK_SECURITY_PLASTEEL_I_S)
				if(C.tool_behaviour == TOOL_CROWBAR)
					to_chat(user, "<span class='notice'>You start removing the inner layer of shielding...</span>")
					if(C.use_tool(src, user, 40, volume=100))
						if(!panel_open)
							return
						if(security_level != AIRLOCK_SECURITY_PLASTEEL_I_S)
							return
						user.visible_message("<span class='notice'>[user] remove \the [src]'s shielding.</span>",
											"<span class='notice'>You remove \the [src]'s inner shielding.</span>")
						security_level = AIRLOCK_SECURITY_NONE
						modify_max_integrity(normal_integrity)
						damage_deflection = AIRLOCK_DAMAGE_DEFLECTION_N
						spawn_atom_to_turf(/obj/item/stack/sheet/plasteel, user.loc, 1)
						update_icon()
					return
			if(AIRLOCK_SECURITY_PLASTEEL_I)
				if(C.tool_behaviour == TOOL_WELDER)
					if(!C.tool_start_check(user, amount=2))
						return
					to_chat(user, "<span class='notice'>You begin cutting the inner layer of shielding...</span>")
					if(C.use_tool(src, user, 40, volume=50, amount=2))
						if(!panel_open)
							return
						user.visible_message("<span class='notice'>[user] cuts through \the [src]'s shielding.</span>",
										"<span class='notice'>You cut through \the [src]'s shielding.</span>",
										"<span class='italics'>You hear welding.</span>")
						security_level = AIRLOCK_SECURITY_PLASTEEL_I_S
					return
			if(AIRLOCK_SECURITY_PLASTEEL_O_S)
				if(C.tool_behaviour == TOOL_CROWBAR)
					to_chat(user, "<span class='notice'>You start removing outer layer of shielding...</span>")
					if(C.use_tool(src, user, 40, volume=100))
						if(!panel_open)
							return
						if(security_level != AIRLOCK_SECURITY_PLASTEEL_O_S)
							return
						user.visible_message("<span class='notice'>[user] remove \the [src]'s shielding.</span>",
											"<span class='notice'>You remove \the [src]'s shielding.</span>")
						security_level = AIRLOCK_SECURITY_PLASTEEL_I
						spawn_atom_to_turf(/obj/item/stack/sheet/plasteel, user.loc, 1)
					return
			if(AIRLOCK_SECURITY_PLASTEEL_O)
				if(C.tool_behaviour == TOOL_WELDER)
					if(!C.tool_start_check(user, amount=2))
						return
					to_chat(user, "<span class='notice'>You begin cutting the outer layer of shielding...</span>")
					if(C.use_tool(src, user, 40, volume=50, amount=2))
						if(!panel_open)
							return
						user.visible_message("<span class='notice'>[user] cuts through \the [src]'s shielding.</span>",
										"<span class='notice'>You cut through \the [src]'s shielding.</span>",
										"<span class='italics'>You hear welding.</span>")
						security_level = AIRLOCK_SECURITY_PLASTEEL_O_S
					return
			if(AIRLOCK_SECURITY_PLASTEEL)
				if(C.tool_behaviour == TOOL_WIRECUTTER)
					if(src.hasPower() && src.shock(user, 60)) // Protective grille of wiring is electrified
						return
					to_chat(user, "<span class='notice'>You start cutting through the outer grille.</span>")
					if(C.use_tool(src, user, 10, volume=100))
						if(!panel_open)
							return
						user.visible_message("<span class='notice'>[user] cut through \the [src]'s outer grille.</span>",
											"<span class='notice'>You cut through \the [src]'s outer grille.</span>")
						security_level = AIRLOCK_SECURITY_PLASTEEL_O
					return
	if(C.tool_behaviour == TOOL_SCREWDRIVER)
		if(panel_open && detonated)
			to_chat(user, "<span class='warning'>[src] has no maintenance panel!</span>")
			return
		panel_open = !panel_open
		to_chat(user, "<span class='notice'>You [panel_open ? "open":"close"] the maintenance panel of the airlock.</span>")
		C.play_tool_sound(src)
		src.update_icon()
	else if(C.tool_behaviour == TOOL_WIRECUTTER && note)
		user.visible_message("<span class='notice'>[user] cuts down [note] from [src].</span>", "<span class='notice'>You remove [note] from [src].</span>")
		C.play_tool_sound(src)
		note.forceMove(get_turf(user))
		note = null
		update_icon()
	else if(is_wire_tool(C) && panel_open)
		attempt_wire_interaction(user)
		return
	else if(istype(C, /obj/item/pai_cable))
		var/obj/item/pai_cable/cable = C
		cable.plugin(src, user)
	else if(istype(C, /obj/item/airlock_painter))
		change_paintjob(C, user)
	else if(istype(C, /obj/item/doorCharge))
		if(!panel_open || security_level)
			to_chat(user, "<span class='warning'>The maintenance panel must be open to apply [C]!</span>")
			return
		if(obj_flags & EMAGGED)
			return
		if(charge && !detonated)
			to_chat(user, "<span class='warning'>There's already a charge hooked up to this door!</span>")
			return
		if(detonated)
			to_chat(user, "<span class='warning'>The maintenance panel is destroyed!</span>")
			return
		to_chat(user, "<span class='warning'>You apply [C]. Next time someone opens the door, it will explode.</span>")
		panel_open = FALSE
		update_icon()
		user.transferItemToLoc(C, src, TRUE)
		charge = C
	else if(istype(C, /obj/item/paper) || istype(C, /obj/item/photo))
		if(note)
			to_chat(user, "<span class='warning'>There's already something pinned to this airlock! Use wirecutters to remove it.</span>")
			return
		if(!user.transferItemToLoc(C, src))
			to_chat(user, "<span class='warning'>For some reason, you can't attach [C]!</span>")
			return
		user.visible_message("<span class='notice'>[user] pins [C] to [src].</span>", "<span class='notice'>You pin [C] to [src].</span>")
		note = C
		update_icon()
	else
		return ..()


/obj/machinery/door/airlock/try_to_weld(obj/item/W, mob/user)
	if(!W.tool_behaviour == TOOL_WELDER)
		return
	if(!operating && density)
		if(user.a_intent != INTENT_HELP)
			if(!W.tool_start_check(user, amount=0))
				return
			user.visible_message("[user] is [welded ? "unwelding":"welding"] the airlock.", \
							"<span class='notice'>You begin [welded ? "unwelding":"welding"] the airlock...</span>", \
							"<span class='italics'>You hear welding.</span>")
			if(W.use_tool(src, user, 40, volume=50, extra_checks = CALLBACK(src, PROC_REF(weld_checks), W, user)))
				welded = !welded
				user.visible_message("[user.name] has [welded? "welded shut":"unwelded"] [src].", \
									"<span class='notice'>You [welded ? "weld the airlock shut":"unweld the airlock"].</span>")
				update_icon()
		else
			if(obj_integrity < max_integrity)
				if(!W.tool_start_check(user, amount=0))
					return
				user.visible_message("[user] is welding the airlock.", \
								"<span class='notice'>You begin repairing the airlock...</span>", \
								"<span class='italics'>You hear welding.</span>")
				if(W.use_tool(src, user, 40, volume=50, extra_checks = CALLBACK(src, PROC_REF(weld_checks), W, user)))
					obj_integrity = max_integrity
					machine_stat &= ~BROKEN
					user.visible_message("[user.name] has repaired [src].", \
										"<span class='notice'>You finish repairing the airlock.</span>")
					update_icon()
			else
				to_chat(user, "<span class='notice'>The airlock doesn't need repairing.</span>")

/obj/machinery/door/airlock/proc/weld_checks(obj/item/W, mob/user)
	if(!W.tool_behaviour == TOOL_WELDER)
		return
	return !operating && density

/// Returns if a crowbar would remove the airlock electronics
/obj/machinery/door/airlock/proc/should_try_removing_electronics()
	if (security_level != 0)
		return FALSE

	if (!panel_open)
		return FALSE

	if (obj_flags & EMAGGED)
		return TRUE

	if (!density)
		return FALSE

	if (!welded)
		return FALSE

	if (hasPower())
		return FALSE

	if (locked)
		return FALSE

	return TRUE

/obj/machinery/door/airlock/try_to_crowbar(obj/item/I, mob/living/user)
	var/beingcrowbarred = null
	if(I.tool_behaviour == TOOL_CROWBAR)
		beingcrowbarred = 1
	else
		beingcrowbarred = 0
	if(panel_open && charge)
		to_chat(user, "<span class='notice'>You carefully start removing [charge] from [src]...</span>")
		if(!I.use_tool(src, user, 150, volume=50))
			to_chat(user, "<span class='warning'>You slip and [charge] detonates!</span>")
			charge.ex_act(EXPLODE_DEVASTATE)
			user.DefaultCombatKnockdown(60)
			return
		user.visible_message("<span class='notice'>[user] removes [charge] from [src].</span>", \
							"<span class='notice'>You gently pry out [charge] from [src] and unhook its wires.</span>")
		charge.forceMove(get_turf(user))
		charge = null
		return
	if(beingcrowbarred && should_try_removing_electronics() && !operating)
		user.visible_message(span_notice("[user] removes the electronics from the airlock assembly."), \
			span_notice("You start to remove electronics from the airlock assembly..."))
		if(I.use_tool(src, user, 40, volume=100))
			deconstruct(TRUE, user)
			return
	else if(hasPower())
		to_chat(user, "<span class='warning'>The airlock's motors resist your efforts to force it!</span>")
	else if(locked)
		to_chat(user, "<span class='warning'>The airlock's bolts prevent it from being forced!</span>")
	else if(!welded && !operating)
		if(!beingcrowbarred) //being fireaxe'd
			var/obj/item/fireaxe/axe = I
			if(!axe.wielded)
				to_chat(user, "<span class='warning'>You need to be wielding \the [axe] to do that!</span>")
				return
			INVOKE_ASYNC(src, (density ? PROC_REF(open) : PROC_REF(close)), 2)
		else
			INVOKE_ASYNC(src, (density ? PROC_REF(open) : PROC_REF(close)), 2)

	if(I.tool_behaviour == TOOL_CROWBAR)
		if(!I.can_force_powered)
			return
		if(hasPower() && isElectrified())
			shock(user,100)//it's like sticking a forck in a power socket
			return

		if(!density)//already open
			return

		if(locked)
			to_chat(user, "<span class='warning'>The bolts are down, it won't budge!</span>")
			return

		if(welded)
			to_chat(user, "<span class='warning'>It's welded, it won't budge!</span>")
			return

		var/time_to_open = 5
		if(hasPower() && !prying_so_hard)
			time_to_open = 50
			playsound(src, 'sound/machines/airlock_alien_prying.ogg',100,1) //is it aliens or just the CE being a dick?
			prying_so_hard = TRUE
			if(do_after(user, time_to_open,target = src))
				open(2)
				if(density && !open(2))
					to_chat(user, "<span class='warning'>Despite your attempts, [src] refuses to open.</span>")
			prying_so_hard = FALSE

/obj/machinery/door/airlock/open(forced=0)
	if( operating || welded || locked )
		return FALSE
	if(!forced)
		if(!hasPower() || wires.is_cut(WIRE_OPEN))
			return FALSE
	if(charge && !detonated)
		panel_open = TRUE
		update_icon(AIRLOCK_OPENING)
		visible_message("<span class='warning'>[src]'s panel is blown off in a spray of deadly shrapnel!</span>")
		charge.forceMove(drop_location())
		charge.ex_act(EXPLODE_DEVASTATE)
		detonated = 1
		charge = null
		for(var/mob/living/carbon/human/H in orange(2,src))
			H.adjust_fire_stacks(20)
			H.IgniteMob() //Guaranteed knockout and ignition for nearby people
			H.apply_damage(40, BRUTE, BODY_ZONE_CHEST)
		return
	if(forced < 2)
		if(obj_flags & EMAGGED)
			return FALSE
		use_power(50)
		playsound(src, doorOpen, 30, 1)
		if(src.closeOther != null && istype(src.closeOther, /obj/machinery/door/airlock/) && !src.closeOther.density)
			src.closeOther.close()
	else
		playsound(src.loc, 'sound/machines/airlockforced.ogg', 30, 1)

	if(autoclose)
		autoclose_in(normalspeed ? 150 : 15)

	if(!density)
		return TRUE
	operating = TRUE
	update_icon(AIRLOCK_OPENING, 1)
	sleep(1)
	set_opacity(0)
	update_freelook_sight()
	sleep(4)
	density = FALSE
	air_update_turf(TRUE)
	sleep(1)
	layer = OPEN_DOOR_LAYER
	update_icon(AIRLOCK_OPEN, 1)
	operating = FALSE
	if(delayed_close_requested)
		delayed_close_requested = FALSE
		addtimer(CALLBACK(src, PROC_REF(close)), 1)
	return TRUE


/obj/machinery/door/airlock/close(forced=0)
	if(operating || welded || locked)
		return
	if(density)
		return TRUE
	if(!forced)
		if(!hasPower() || wires.is_cut(WIRE_BOLTS))
			return
	if(safe)
		for(var/atom/movable/M in get_turf(src))
			if(M.density && M != src) //something is blocking the door
				autoclose_in(60)
				return

	if(forced < 2)
		if(obj_flags & EMAGGED)
			return
		use_power(50)
		playsound(src.loc, doorClose, 30, 1)
	else
		playsound(src.loc, 'sound/machines/airlockforced.ogg', 30, 1)

	var/obj/structure/window/killthis = (locate(/obj/structure/window) in get_turf(src))
	if(killthis)
		killthis.ex_act(EXPLODE_HEAVY)//Smashin windows

	operating = TRUE
	update_icon(AIRLOCK_CLOSING, 1)
	layer = CLOSED_DOOR_LAYER
	if(air_tight)
		density = TRUE
		air_update_turf(TRUE)
	sleep(1)
	if(!air_tight)
		density = TRUE
		air_update_turf(TRUE)
	sleep(4)
	if(!safe)
		crush()
	if(visible && !glass)
		set_opacity(1)
	update_freelook_sight()
	sleep(1)
	update_icon(AIRLOCK_CLOSED, 1)
	operating = FALSE
	delayed_close_requested = FALSE
	if(safe)
		CheckForMobs()
	return TRUE

/obj/machinery/door/airlock/proc/prison_open()
	if(obj_flags & EMAGGED)
		return
	log_admin("[key_name(usr)] emagged [src] at [AREACOORD(src)]")
	locked = FALSE
	src.open()
	locked = TRUE
	return

// gets called when a player uses an airlock painter on this airlock
/obj/machinery/door/airlock/proc/change_paintjob(obj/item/airlock_painter/painter, mob/user)
	if((!in_range(src, user) && loc != user) || !painter.can_use(user)) // user should be adjacent to the airlock, and the painter should have a toner cartridge that isn't empty
		return

	// reads from the airlock painter's `available paintjob` list. lets the player choose a paint option, or cancel painting
	var/current_paintjob = tgui_input_list(user, "Paintjob for this airlock", "Customize", sort_list(painter.available_paint_jobs))
	if(isnull(current_paintjob)) // if the user clicked cancel on the popup, return
		return

	var/airlock_type = painter.available_paint_jobs["[current_paintjob]"] // get the airlock type path associated with the airlock name the user just chose
	var/obj/machinery/door/airlock/airlock = airlock_type // we need to create a new instance of the airlock and assembly to read vars from them
	var/obj/structure/door_assembly/assembly = initial(airlock.assemblytype)

	if(airlock_material == "glass" && initial(assembly.noglass)) // prevents painting glass airlocks with a paint job that doesn't have a glass version, such as the freezer
		to_chat(user, span_warning("This paint job can only be applied to non-glass airlocks."))
		return

	// applies the user-chosen airlock's icon, overlays and assemblytype to the src airlock
	painter.use_paint(user)
	icon = initial(airlock.icon)
	overlays_file = initial(airlock.overlays_file)
	assemblytype = initial(airlock.assemblytype)
	update_icon()

/obj/machinery/door/airlock/CanAStarPass(obj/item/card/id/ID, to_dir, atom/movable/caller)
	//Airlock is passable if it is open (!density), bot has access, and is not bolted shut or powered off)
	return !density || (check_access(ID) && !locked && hasPower())

/obj/machinery/door/airlock/emag_act(mob/user)
	. = ..()
	if(operating || !density || !hasPower() || obj_flags & EMAGGED)
		return
	operating = TRUE
	update_icon(AIRLOCK_EMAG, 1)
	log_admin("[key_name(usr)] emagged [src] at [AREACOORD(src)]")
	addtimer(CALLBACK(src, PROC_REF(open_sesame)), 6)
	return TRUE

/obj/machinery/door/airlock/proc/open_sesame()
	operating = FALSE
	if(!open())
		update_icon(AIRLOCK_CLOSED, 1)
	obj_flags |= EMAGGED
	lights = FALSE
	locked = TRUE
	loseMainPower()
	loseBackupPower()

/obj/machinery/door/airlock/attack_alien(mob/living/carbon/alien/humanoid/user)
	add_fingerprint(user)
	if(isElectrified())
		shock(user, 100) //Mmm, fried xeno!
		return
	if(!density) //Already open
		return
	if(locked || welded) //Extremely generic, as aliens only understand the basics of how airlocks work.
		to_chat(user, "<span class='warning'>[src] refuses to budge!</span>")
		return
	user.visible_message("<span class='warning'>[user] begins prying open [src].</span>",\
						"<span class='noticealien'>You begin digging your claws into [src] with all your might!</span>",\
						"<span class='warning'>You hear groaning metal...</span>")
	var/time_to_open = 5
	if(hasPower())
		time_to_open = 50 //Powered airlocks take longer to open, and are loud.
		playsound(src, 'sound/machines/airlock_alien_prying.ogg', 100, 1)


	if(do_after(user, time_to_open, target = src))
		if(density && !open(2)) //The airlock is still closed, but something prevented it opening. (Another player noticed and bolted/welded the airlock in time!)
			to_chat(user, "<span class='warning'>Despite your efforts, [src] managed to resist your attempts to open it!</span>")

/obj/machinery/door/airlock/hostile_lockdown(mob/origin, aicontrolneeded = TRUE)
	// Must be powered and have working AI wire.
	if((aicontrolneeded && canAIControl(src) && !machine_stat) || !aicontrolneeded)
		locked = FALSE //For airlocks that were bolted open.
		safe = FALSE //DOOR CRUSH
		close()
		bolt() //Bolt it!
		set_electrified(ELECTRIFIED_PERMANENT)  //Shock it!
		if(origin)
			LAZYADD(shockedby, "\[[TIME_STAMP("hh:mm:ss", FALSE)]\] [key_name(origin)]")


/obj/machinery/door/airlock/disable_lockdown(aicontrolneeded = TRUE)
	// Must be powered and have working AI wire.
	if((aicontrolneeded && canAIControl(src) && !machine_stat) || !aicontrolneeded)
		unbolt()
		set_electrified(NOT_ELECTRIFIED)
		open()
		safe = TRUE


/obj/machinery/door/airlock/obj_break(damage_flag)
	if(!(flags_1 & BROKEN) && !(flags_1 & NODECONSTRUCT_1))
		machine_stat |= BROKEN
		if(!panel_open)
			panel_open = TRUE
		wires.cut_all()
		update_icon()

/obj/machinery/door/airlock/proc/remove_electrify()
	secondsElectrified = NOT_ELECTRIFIED
	unelectrify_timerid = null
	diag_hud_set_electrified()

/obj/machinery/door/airlock/proc/set_electrified(seconds, mob/user)
	secondsElectrified = seconds
	if(unelectrify_timerid)
		deltimer(unelectrify_timerid)
		unelectrify_timerid = null
	if(secondsElectrified != ELECTRIFIED_PERMANENT)
		unelectrify_timerid = addtimer(CALLBACK(src, PROC_REF(remove_electrify)), secondsElectrified SECONDS, TIMER_STOPPABLE)
	diag_hud_set_electrified()

	if(user)
		var/message
		switch(secondsElectrified)
			if(ELECTRIFIED_PERMANENT)
				message = "permanently shocked"
			if(NOT_ELECTRIFIED)
				message = "unshocked"
			else
				message = "temp shocked for [secondsElectrified] seconds"
		LAZYADD(shockedby, text("\[[TIME_STAMP("hh:mm:ss", FALSE)]\] [key_name(user)] - ([uppertext(message)])"))
		log_combat(user, src, message)
		//add_hiddenprint(user)

/obj/machinery/door/airlock/take_damage(damage_amount, damage_type = BRUTE, damage_flag = 0, sound_effect = 1, attack_dir)
	. = ..()
	if(obj_integrity < (0.75 * max_integrity))
		update_icon()

/obj/machinery/door/airlock/proc/prepare_deconstruction_assembly(obj/structure/door_assembly/assembly)
	assembly.heat_proof_finished = heat_proof //tracks whether there's rglass in
	assembly.set_anchored(TRUE)
	assembly.glass = glass
	assembly.state = AIRLOCK_ASSEMBLY_NEEDS_ELECTRONICS
	assembly.created_name = name
	assembly.previous_assembly = previous_airlock
	assembly.update_name()
	assembly.update_icon()
	assembly.update_appearance()

/obj/machinery/door/airlock/deconstruct(disassembled = TRUE, mob/user)
	if(!(flags_1 & NODECONSTRUCT_1))
		var/obj/structure/door_assembly/A
		if(assemblytype)
			A = new assemblytype(src.loc)
		else
			A = new /obj/structure/door_assembly(loc)
			//If you come across a null assemblytype, it will produce the default assembly instead of disintegrating.
		prepare_deconstruction_assembly(A)

		if(!disassembled)
			if(A)
				A.obj_integrity = A.max_integrity * 0.5
		else if(obj_flags & EMAGGED)
			if(user)
				to_chat(user, "<span class='warning'>You discard the damaged electronics.</span>")
		else
			if(user)
				to_chat(user, "<span class='notice'>You remove the airlock electronics.</span>")

			var/obj/item/electronics/airlock/ae
			if(!electronics)
				ae = new/obj/item/electronics/airlock( src.loc )
				gen_access()
				if(req_one_access.len)
					ae.one_access = 1
					ae.accesses = src.req_one_access
				else
					ae.accesses = src.req_access
			else
				ae = electronics
				electronics = null
				ae.forceMove(drop_location())
	qdel(src)

/obj/machinery/door/airlock/rcd_vals(mob/user, obj/item/construction/rcd/the_rcd)
	switch(the_rcd.mode)
		if(RCD_DECONSTRUCT)
			if(security_level != AIRLOCK_SECURITY_NONE && the_rcd.canRturf != TRUE)
				to_chat(user, "<span class='notice'>[src]'s reinforcement needs to be removed first.</span>")
				return FALSE
			return list("mode" = RCD_DECONSTRUCT, "delay" = 50, "cost" = 32)
	return FALSE

/obj/machinery/door/airlock/rcd_act(mob/user, obj/item/construction/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_DECONSTRUCT)
			to_chat(user, "<span class='notice'>You deconstruct the airlock.</span>")
			qdel(src)
			return TRUE
	return FALSE

/obj/machinery/door/airlock/proc/note_type() //Returns a string representing the type of note pinned to this airlock
	if(!note)
		return
	else if(istype(note, /obj/item/paper))
		return "note"
	else if(istype(note, /obj/item/photo))
		return "photo"

/obj/machinery/door/airlock/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "AiAirlock", name)
		ui.open()
	return TRUE

/obj/machinery/door/airlock/ui_status(mob/user)
	. = ..()
	if (!issilicon(user) && hasSiliconAccessInArea(user))
		. = UI_INTERACTIVE

/obj/machinery/door/airlock/can_interact(mob/user)
	. = ..()
	if (!issilicon(user) && hasSiliconAccessInArea(user))
		return TRUE

/obj/machinery/door/airlock/ui_data()
	var/list/data = list()

	var/list/power = list()
	power["main"] = secondsMainPowerLost ? 0 : 2 // boolean
	power["main_timeleft"] = secondsMainPowerLost
	power["backup"] = secondsBackupPowerLost ? 0 : 2 // boolean
	power["backup_timeleft"] = secondsBackupPowerLost
	data["power"] = power

	data["shock"] = secondsElectrified == NOT_ELECTRIFIED ? 2 : 0
	data["shock_timeleft"] = secondsElectrified
	data["id_scanner"] = !aiDisabledIdScanner
	data["emergency"] = emergency // access
	data["locked"] = locked // bolted
	data["lights"] = lights // bolt lights
	data["safe"] = safe // safeties
	data["speed"] = normalspeed // safe speed
	data["welded"] = welded // welded
	data["opened"] = !density // opened

	var/list/wire = list()
	wire["main_1"] = !wires.is_cut(WIRE_POWER1)
	wire["main_2"] = !wires.is_cut(WIRE_POWER2)
	wire["backup_1"] = !wires.is_cut(WIRE_BACKUP1)
	wire["backup_2"] = !wires.is_cut(WIRE_BACKUP2)
	wire["shock"] = !wires.is_cut(WIRE_SHOCK)
	wire["id_scanner"] = !wires.is_cut(WIRE_IDSCAN)
	wire["bolts"] = !wires.is_cut(WIRE_BOLTS)
	wire["lights"] = !wires.is_cut(WIRE_LIGHT)
	wire["safe"] = !wires.is_cut(WIRE_SAFETY)
	wire["timing"] = !wires.is_cut(WIRE_TIMING)

	data["wires"] = wire
	return data

/obj/machinery/door/airlock/ui_act(action, params)
	if(..())
		return
	if(params["ic_advactivator"])
		advactivator_action = TRUE
	if(!user_allowed(usr))
		return
	switch(action)
		if("disrupt-main")
			if(!secondsMainPowerLost)
				loseMainPower()
				update_icon()
			else
				to_chat(usr, "<span class='warning'>Main power is already offline.</span>")
			. = TRUE
		if("disrupt-backup")
			if(!secondsBackupPowerLost)
				loseBackupPower()
				update_icon()
			else
				to_chat(usr, "<span class='warning'>Backup power is already offline.</span>")
			. = TRUE
		if("shock-restore")
			shock_restore(usr)
			. = TRUE
		if("shock-temp")
			shock_temp(usr)
			. = TRUE
		if("shock-perm")
			shock_perm(usr)
			. = TRUE
		if("idscan-toggle")
			aiDisabledIdScanner = !aiDisabledIdScanner
			. = TRUE
		if("emergency-toggle")
			toggle_emergency(usr)
			. = TRUE
		if("bolt-toggle")
			toggle_bolt(usr)
			. = TRUE
		if("light-toggle")
			lights = !lights
			update_icon()
			. = TRUE
		if("safe-toggle")
			safe = !safe
			. = TRUE
		if("speed-toggle")
			normalspeed = !normalspeed
			. = TRUE
		if("open-close")
			user_toggle_open(usr)
			. = TRUE
	advactivator_action = FALSE

/obj/machinery/door/airlock/proc/user_allowed(mob/user)
	return (hasSiliconAccessInArea(user) && canAIControl(user)) || IsAdminGhost(user) || advactivator_action

/obj/machinery/door/airlock/proc/shock_restore(mob/user)
	if(!user_allowed(user))
		return
	if(wires.is_cut(WIRE_SHOCK))
		to_chat(user, "Can't un-electrify the airlock - The electrification wire is cut.")
	else if(isElectrified())
		set_electrified(0)

/obj/machinery/door/airlock/proc/shock_temp(mob/user)
	if(!user_allowed(user))
		return
	if(wires.is_cut(WIRE_SHOCK))
		to_chat(user, "The electrification wire has been cut")
	else
		LAZYADD(shockedby, "\[[TIME_STAMP("hh:mm:ss", FALSE)]\] [key_name(user)]")
		log_combat(user, src, "electrified")
		set_electrified(AI_ELECTRIFY_DOOR_TIME)

/obj/machinery/door/airlock/proc/shock_perm(mob/user)
	if(!user_allowed(user))
		return
	if(wires.is_cut(WIRE_SHOCK))
		to_chat(user, "The electrification wire has been cut")
	else
		LAZYADD(shockedby, text("\[[TIME_STAMP("hh:mm:ss", FALSE)]\] [key_name(user)]"))
		log_combat(user, src, "electrified")
		set_electrified(ELECTRIFIED_PERMANENT)

/obj/machinery/door/airlock/proc/toggle_bolt(mob/user)
	if(!user_allowed(user))
		return
	if(wires.is_cut(WIRE_BOLTS))
		to_chat(user, "<span class='warning'>The door bolt drop wire is cut - you can't toggle the door bolts.</span>")
		return
	if(locked)
		if(!hasPower())
			to_chat(user, "<span class='warning'>The door has no power - you can't raise the door bolts.</span>")
		else
			unbolt()
	else
		bolt()

/obj/machinery/door/airlock/proc/toggle_emergency(mob/user)
	if(!user_allowed(user))
		return
	emergency = !emergency
	update_icon()

/obj/machinery/door/airlock/proc/user_toggle_open(mob/user)
	if(!user_allowed(user))
		return
	if(welded)
		to_chat(user, text("The airlock has been welded shut!"))
	else if(locked)
		to_chat(user, text("The door bolts are down!"))
	else if(!density)
		close()
	else
		open()

#undef AIRLOCK_CLOSED
#undef AIRLOCK_CLOSING
#undef AIRLOCK_OPEN
#undef AIRLOCK_OPENING
#undef AIRLOCK_DENY
#undef AIRLOCK_EMAG

#undef AIRLOCK_LIGHT_BOLTS
#undef AIRLOCK_LIGHT_EMERGENCY
#undef AIRLOCK_LIGHT_DENIED
#undef AIRLOCK_LIGHT_CLOSING
#undef AIRLOCK_LIGHT_OPENING

#undef AIRLOCK_LIGHT_POWER
#undef AIRLOCK_LIGHT_RANGE

#undef AIRLOCK_POWERON_LIGHT_COLOR
#undef AIRLOCK_BOLTS_LIGHT_COLOR
#undef AIRLOCK_ACCESS_LIGHT_COLOR
#undef AIRLOCK_EMERGENCY_LIGHT_COLOR
#undef AIRLOCK_DENY_LIGHT_COLOR

#undef AIRLOCK_SECURITY_NONE
#undef AIRLOCK_SECURITY_METAL
#undef AIRLOCK_SECURITY_PLASTEEL_I_S
#undef AIRLOCK_SECURITY_PLASTEEL_I
#undef AIRLOCK_SECURITY_PLASTEEL_O_S
#undef AIRLOCK_SECURITY_PLASTEEL_O
#undef AIRLOCK_SECURITY_PLASTEEL

#undef AIRLOCK_INTEGRITY_N
#undef AIRLOCK_INTEGRITY_MULTIPLIER
#undef AIRLOCK_DAMAGE_DEFLECTION_N
#undef AIRLOCK_DAMAGE_DEFLECTION_R

#undef NOT_ELECTRIFIED
#undef ELECTRIFIED_PERMANENT
#undef AI_ELECTRIFY_DOOR_TIME
