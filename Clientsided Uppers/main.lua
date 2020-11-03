ClientsidedUppers = ClientsidedUppers or {}
ClientsidedUppers._client_sided_faks = {}
ClientsidedUppers._used_client_sided_faks = {}
ClientsidedUppers.__index = ClientsidedUppers

function ClientsidedUppers:Add(pos, rot, bits, min_distance, upgrade_lvl)
	local fak = {}
	setmetatable(fak, self)
	fak.pos = pos
	fak.rot = rot
	fak.bits = bits
	fak.min_distance = min_distance
	fak.upgrade_lvl = upgrade_lvl

	table.insert(ClientsidedUppers._client_sided_faks, fak)
end

function ClientsidedUppers.Remove(pos)
	local closest_dst = -1
	local closest = 0
	for i, fak in pairs(ClientsidedUppers._client_sided_faks) do
		local dst = mvector3.distance(pos, fak.pos)

		if dst < closest_dst or closest_dst == -1 then
			closest_dst = dst
			closest = i
		end
	end
	if closest >= 1 then
		table.remove(ClientsidedUppers._client_sided_faks, closest)
	end
end

function ClientsidedUppers.GetFirstAidKit(pos)
	local closest_dst = -1
	local closest = nil
	for i, fak in pairs(ClientsidedUppers._client_sided_faks) do
		local dst = mvector3.distance(pos, fak.pos)

		if dst <= fak.min_distance and dst < closest_dst then
			closest_dst = dst
			closest = fak
		end
	end

	return closest
end

function ClientsidedUppers.AddUsed(fak)
	table.insert(ClientsidedUppers._used_client_sided_faks, fak)
end

function ClientsidedUppers.RemoveUsed(pos)
	local closest_dst = -1
	local closest = 0
	for i, fak in pairs(ClientsidedUppers._used_client_sided_faks) do
		local dst = mvector3.distance(pos, fak.pos)

		if dst < closest_dst or closest_dst == -1 then
			closest_dst = dst
			closest = i
		end
		if dst <= 5 then
			table.remove(ClientsidedUppers._used_client_sided_faks, i)
		end
	end
	if closest >= 1 then
		table.remove(ClientsidedUppers._used_client_sided_faks, closest)
	end
end

function ClientsidedUppers.GetUsedFirstAidKit(pos)
	local closest_dst = -1
	local closest = nil
	for i, fak in pairs(ClientsidedUppers._used_client_sided_faks) do
		local dst = mvector3.distance(pos, fak.pos)

		if dst < closest_dst or closest_dst == -1 then
			closest_dst = dst
			closest = fak
		end
	end

	return closest
end

function ClientsidedUppers:Take(unit)
	ClientsidedUppers.Remove(self.pos)
	ClientsidedUppers.AddUsed(self)

	unit:character_damage():band_aid_health()

	managers.chat:_receive_message(
		ChatManager.GAME,
		"ClientsidedUppers",
		"took clientsided FAK",
		tweak_data.system_chat_color
	)

	if self.upgrade_lvl == 1 then
		managers.player:activate_temporary_upgrade("temporary", "first_aid_damage_reduction")
	end
end

function ClientsidedUppers:SyncUsage(unit)
	if managers.network:session() then
		managers.network:session():send_to_peers_synched("sync_unit_event_id_16", unit, "base", 2)
	end

	unit:_set_empty()
end

function ClientsidedUppers.Hooks()
	if RequiredScript == "lib/units/beings/player/playerequipment" then
		function PlayerEquipment:use_first_aid_kit()
			local ray = self:valid_shape_placement("first_aid_kit")

			if ray then
				local pos = ray.position
				local rot = self:_m_deploy_rot()
				rot = Rotation(rot:yaw(), 0, 0)

				PlayerStandard.say_line(self, "s12")
				managers.statistics:use_first_aid()

				local upgrade_lvl = managers.player:has_category_upgrade("first_aid_kit", "damage_reduction_upgrade") and 1 or 0
				local auto_recovery =
					managers.player:has_category_upgrade("first_aid_kit", "first_aid_kit_auto_recovery") and 1 or 0
				local bits =
					Bitwise:lshift(auto_recovery, FirstAidKitBase.auto_recovery_shift) +
					Bitwise:lshift(upgrade_lvl, FirstAidKitBase.upgrade_lvl_shift)

				if Network:is_client() then
					if auto_recovery == 1 then
						local min_distance = tweak_data.upgrades.values.first_aid_kit.first_aid_kit_auto_recovery[1]
						ClientsidedUppers:Add(pos, rot, bits, min_distance, upgrade_lvl)
					end

					managers.network:session():send_to_host("place_deployable_bag", "FirstAidKitBase", pos, rot, bits)
				else
					local unit = FirstAidKitBase.spawn(pos, rot, bits, managers.network:session():local_peer():id())
				end

				return true
			end

			return false
		end
	elseif RequiredScript == "lib/units/beings/player/playerdamage" then
		function PlayerDamage:_check_bleed_out(can_activate_berserker, ignore_movement_state)
			if self:get_real_health() == 0 and not self._check_berserker_done then
				if self._unit:movement():zipline_unit() then
					self._bleed_out_blocked_by_zipline = true

					return
				end

				if not ignore_movement_state and self._unit:movement():current_state():bleed_out_blocked() then
					self._bleed_out_blocked_by_movement_state = true

					return
				end

				local time = Application:time()

				if not self._block_medkit_auto_revive and time > self._uppers_elapsed + self._UPPERS_COOLDOWN then
					local auto_recovery_kit = FirstAidKitBase.GetFirstAidKit(self._unit:position())

					if auto_recovery_kit then
						auto_recovery_kit:take(self._unit)
						self._unit:sound():play("pickup_fak_skill")

						self._uppers_elapsed = time

						return
					else
						local client_sided_fak = ClientsidedUppers.GetFirstAidKit(self._unit:position())
						if client_sided_fak then
							client_sided_fak:Take(self._unit)
							self._unit:sound():play("pickup_fak_skill")

							self._uppers_elapsed = time
							return
						end
					end
				end

				if can_activate_berserker and not self._check_berserker_done then
					local has_berserker_skill = managers.player:has_category_upgrade("temporary", "berserker_damage_multiplier")

					if has_berserker_skill and not self._disable_next_swansong then
						managers.hud:set_teammate_condition(
							HUDManager.PLAYER_PANEL,
							"mugshot_swansong",
							managers.localization:text("debug_mugshot_downed")
						)
						managers.player:activate_temporary_upgrade("temporary", "berserker_damage_multiplier")

						self._current_state = nil
						self._check_berserker_done = true

						if
							alive(self._interaction:active_unit()) and
								not self._interaction:active_unit():interaction():can_interact(self._unit)
						 then
							self._unit:movement():interupt_interact()
						end

						self._listener_holder:call("on_enter_swansong")
					end

					self._disable_next_swansong = nil
				end

				self._hurt_value = 0.2
				self._damage_to_hot_stack = {}

				managers.environment_controller:set_downed_value(0)
				SoundDevice:set_rtpc("downed_state_progression", 0)

				if not self._check_berserker_done or not can_activate_berserker then
					self._revives = Application:digest_value(Application:digest_value(self._revives, false) - 1, true)
					self._check_berserker_done = nil

					managers.environment_controller:set_last_life(Application:digest_value(self._revives, false) <= 1)

					if Application:digest_value(self._revives, false) == 0 then
						self._down_time = 0
					end

					self._bleed_out = true
					self._current_state = nil

					managers.player:set_player_state("bleed_out")

					self._critical_state_heart_loop_instance = self._unit:sound():play("critical_state_heart_loop")
					self._slomo_sound_instance = self._unit:sound():play("downed_slomo_fx")
					self._bleed_out_health =
						Application:digest_value(
						tweak_data.player.damage.BLEED_OUT_HEALTH_INIT *
							managers.player:upgrade_value("player", "bleed_out_health_multiplier", 1),
						true
					)

					self:_drop_blood_sample()
					self:on_downed()
				end
			elseif not self._said_hurt and self:get_real_health() / self:_max_health() < 0.2 then
				self._said_hurt = true

				PlayerStandard.say_line(self, "g80x_plu")
			end
		end
	elseif RequiredScript == "lib/units/equipment/first_aid_kit/firstaidkitbase" then
		function FirstAidKitBase.Add(obj, pos, min_distance)
			local used_fak = ClientsidedUppers.GetUsedFirstAidKit(pos)

			if used_fak then
				used_fak:SyncUsage(obj._unit)
				ClientsidedUppers.RemoveUsed(pos)
			else
				ClientsidedUppers.Remove(pos)
			end

			table.insert(
				FirstAidKitBase.List,
				{
					obj = obj,
					pos = pos,
					min_distance = min_distance
				}
			)
		end
	end
end

ClientsidedUppers.Hooks()
