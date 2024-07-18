-- when spawning a clientsided FAK, the tweak_data is set to "clientsided"
-- we use this to set _clientsided = true
function FirstAidKitBase:init(unit)
    UnitBase.init(self, unit, false)

    self._unit = unit

    self._unit:sound_source():post_event("ammo_bag_drop")

    if self.tweak_data == "clientsided" then
        self._clientsided = true
    end

    if not self._clientsided and Network:is_client() then
        self._validate_clbk_id = "first_aid_kit_validate" .. tostring(unit:key())

        managers.enemy:add_delayed_clbk(self._validate_clbk_id, callback(self, self, "_clbk_validate"),
            Application:time() + 60)
    end
end

-- retrieves the closest fitting FAK for auto_recovery
-- if no synchronized FAK is fitting take the closest fitting clientsided FAK
-- if no clientsided FAK is fitting return nil
function FirstAidKitBase.GetFirstAidKit(pos)
    local closest_dst = -1
    local closest_fak = nil
    for i, o in pairs(FirstAidKitBase.List) do
        local dst = mvector3.distance(pos, o.pos)

        if not o.obj._empty and dst <= o.min_distance and (dst <= closest_dst or closest_dst == -1) then
            closest_dst = dst
            closest_fak = o.obj
        end
    end

    return closest_fak
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
        if ClientsidedUppers.settings.notify then
            ClientsidedUppers.Notify()
        end

        self._empty = true

        if self._removal_needed then
            self._linked_fak:sync_usage()
        end

        ClientsidedUppers.RemoveFromUppers(self)

        self:delete_clientsided()
    else
        self:sync_usage()
    end
end

-- the syncrhonization part of taking a FAK stripped from the take function
function FirstAidKitBase:sync_usage()
    self:_set_empty()

    self._unit:set_visible(false)
    self._unit:interaction():set_active(false)

    if managers.network:session() then
        managers.network:session():send_to_peers_synched("sync_unit_event_id_16", self._unit, "base", 2)
    end
end

-- when the incoming FAK to be synchronized is owned by us we remove it's clientsided counterpart
-- when it was already used clientsided we synchronize it's usage
function FirstAidKitBase:sync_setup(bits, peer_id)
    if Network:is_client() and peer_id == managers.network:session():local_peer():id() then
        local fak = ClientsidedUppers.Remove(self._unit:position())
        if fak then
            local interaction = fak._unit:interaction()
            if interaction and interaction._tweak_data_at_interact_start == interaction.tweak_data then -- when clientsided FAK is being interacted with
                fak._removal_needed = true
                fak._linked_fak = self
            else
                fak:delete_clientsided()
            end
        else
            self:sync_usage()
        end
    end

    if self._validate_clbk_id then
        managers.enemy:remove_delayed_clbk(self._validate_clbk_id)

        self._validate_clbk_id = nil
    end

    managers.player:verify_equipment(peer_id, "first_aid_kit")
    self:setup(bits)
end

function FirstAidKitBase:delete_clientsided()
    if self._unit:interaction() then
        self._unit:interaction():destroy()
    end

    if alive(self._unit) then
        World:delete_unit(self._unit)
    end
end
