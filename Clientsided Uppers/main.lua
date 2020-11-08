ClientsidedUppers = ClientsidedUppers or {}
ClientsidedUppers._client_sided_faks = {}
ClientsidedUppers._used_client_sided_faks = {}
ClientsidedUppers.__index = ClientsidedUppers

-- adds a clientsided FAK to the auto_recovery list
function ClientsidedUppers.Add(pos, min_distance, upgrade_lvl)
	local fak = {}
	setmetatable(fak, FirstAidKitBase)
	fak._empty = false
	fak._damage_reduction_upgrade = upgrade_lvl == 1
	fak._clientsided = true
	table.insert(
		FirstAidKitBase.List,
		{
			obj = fak,
			pos = pos,
			min_distance = min_distance
		}
	)
end

-- removes the closest clientsided FAK from the autorecovery list
-- if the fak is empty it's usage is synchronized
function ClientsidedUppers.Remove(fak)
	local pos = fak._unit:position()
	local closest_dst = -1
	local closest = 0
	local closest_fak = nil
	for i, o in pairs(FirstAidKitBase.List) do
		local dst = mvector3.distance(pos, o.pos)

		if o.obj._clientsided and (dst <= closest_dst or closest_dst == -1) then
			closest_dst = dst
			closest = i
			closest_fak = o.obj
		end
	end

	if closest >= 1 then
		table.remove(FirstAidKitBase.List, closest)
	end

	return closest_fak
end

function ClientsidedUppers.Hooks()
	if RequiredScript == "lib/units/beings/player/playerequipment" then
		-- as a client instead of only sending a request to place a FAK
		-- also add a clientsided FAK to the auto_recovery list
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
						ClientsidedUppers.Add(pos, min_distance, upgrade_lvl)
					end

					managers.network:session():send_to_host("place_deployable_bag", "FirstAidKitBase", pos, rot, bits)
				else
					local unit = FirstAidKitBase.spawn(pos, rot, bits, managers.network:session():local_peer():id())
				end

				return true
			end

			return false
		end
	elseif RequiredScript == "lib/units/equipment/first_aid_kit/firstaidkitbase" then
		-- retrieves the closest fitting FAK for auto_recovery
		-- if no synchronized FAK is fitting take the closest fitting clientsided FAK
		-- if no clientsided FAK is fitting return nil
		function FirstAidKitBase.GetFirstAidKit(pos)
			local closest_dst = -1
			local closest_fak = nil
			local closest_clientsided_dst = -1
			local closest_clientsided_fak = nil
			for i, o in pairs(FirstAidKitBase.List) do
				local dst = mvector3.distance(pos, o.pos)

				if not o.obj._empty and dst <= o.min_distance then
					if not o.obj._clientsided and (dst <= closest_dst or closest_dst == -1) then
						closest_dst = dst
						closest_fak = o.obj
					elseif o.obj._clientsided and (dst <= closest_clientsided_dst or closest_clientsided_dst == -1) then
						closest_clientsided_dst = dst
						closest_clientsided_fak = o.obj
					end
				end
			end
			return closest_fak and closest_fak or closest_clientsided_fak
		end

		-- takes synchronized and clientsided FAKs
		-- for clientsided FAKs it doesn't synchronize it's usage yet
		-- they just get flagged as empty to be processed when they are synchronized
		function FirstAidKitBase:take(unit)
			if self._empty then
				return
			end

			unit:character_damage():band_aid_health()

			if self._damage_reduction_upgrade then
				managers.player:activate_temporary_upgrade("temporary", "first_aid_damage_reduction")
			end

			if self._clientsided then
				managers.chat:_receive_message(
					ChatManager.GAME,
					"SYSTEM",
					"Clientsided Uppers saved your life.",
					tweak_data.system_chat_color
				)
				self._empty = true
			else
				if managers.network:session() then
					managers.network:session():send_to_peers_synched("sync_unit_event_id_16", self._unit, "base", 2)
				end

				self:_set_empty()
			end
		end
		-- the syncrhonization part of taking a FAK stripped from the take function
		function FirstAidKitBase:sync_usage()
			if managers.network:session() then
				managers.network:session():send_to_peers_synched("sync_unit_event_id_16", self._unit, "base", 2)
			end

			self:_set_empty()
		end
		-- when the incoming FAK to be synchronized is owned by us we remove it's clientsided counterpart
		-- when it was already used clientsided we synchronize it's usage
		function FirstAidKitBase:sync_setup(bits, peer_id)
			if Network:is_client() and peer_id == managers.network:session():local_peer():id() then
				local fak = ClientsidedUppers.Remove(self)
				if fak and fak._empty then
					self:sync_usage()
					return
				end
			end

			if self._validate_clbk_id then
				managers.enemy:remove_delayed_clbk(self._validate_clbk_id)

				self._validate_clbk_id = nil
			end

			managers.player:verify_equipment(peer_id, "first_aid_kit")
			self:setup(bits)
		end
	end
end

ClientsidedUppers.Hooks()
