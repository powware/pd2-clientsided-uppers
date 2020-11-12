ClientsidedUppers = ClientsidedUppers or {}
ClientsidedUppers.default_settings = {
    cooldown_fix = true,
    red = 0.1,
    blue = 1,
    green = 0.5,
    opacity = 1
}
ClientsidedUppers._mod_path = ModPath
ClientsidedUppers._save_path = SavePath
ClientsidedUppers._save_file = ClientsidedUppers._save_path .. "clientsided_uppers.json"

function deep_copy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == "table" then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deep_copy(orig_key)] = deep_copy(orig_value)
        end
        setmetatable(copy, deep_copy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function ClientsidedUppers:Setup()
    if not self.settings then
        self:Load()
        self.SetTweakData()
    end

    self.SetupHooks()
end

function ClientsidedUppers:Load()
    self.settings = deep_copy(self.default_settings)
    local file = io.open(self._save_file, "r")
    if file then
        local data = file:read("*a")
        if data then
            local decoded_data = json.decode(data)

            if decoded_data then
                for key, value in pairs(self.settings) do
                    if decoded_data[key] ~= nil then
                        self.settings[key] = decoded_data[key]
                    end
                end
            end
        end
        file:close()
    end
end

function ClientsidedUppers:Save()
    local file = io.open(self._save_file, "w+")
    if file then
        file:write(json.encode(self.settings))
        file:close()
    end
end

function ClientsidedUppers.SetTweakData()
    if not tweak_data.interaction.clientsided_first_aid_kit or not tweak_data.contour.clientsided_deployable then
        tweak_data.interaction.clientsided_first_aid_kit = deep_copy(tweak_data.interaction.first_aid_kit)
        tweak_data.interaction.clientsided_first_aid_kit.clientsided = true
        tweak_data.interaction.clientsided_first_aid_kit.contour = "clientsided_deployable"
        tweak_data.contour.clientsided_deployable = deep_copy(tweak_data.contour.deployable)
    end

    tweak_data.contour.clientsided_deployable.standard_color =
        Vector3(ClientsidedUppers.settings.red, ClientsidedUppers.settings.green, ClientsidedUppers.settings.blue)

    for key, value in pairs(tweak_data.contour.clientsided_deployable) do
        tweak_data.contour.clientsided_deployable[key] = value * ClientsidedUppers.settings.opacity
    end
end

-- spawns a fak without network sync as a custom asset
function ClientsidedUppers.Spawn(pos, rot, min_distance, upgrade_lvl)
    local unit_name =
        "units/pd2_dlc_old_hoxton/equipment/gen_equipment_first_aid_kit/gen_equipment_first_aid_kit_clientsided"
    local unit = World:spawn_unit(Idstring(unit_name), pos, rot)
    local fak = unit:base()
    fak._damage_reduction_upgrade = upgrade_lvl == 1
    FirstAidKitBase.Add(fak, unit:position(), min_distance)
end

-- removes the closest clientsided FAK from the autorecovery list
-- if the fak is empty it's usage is synchronized
function ClientsidedUppers.Remove(pos)
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

function ClientsidedUppers.SetupHooks()
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

                local upgrade_lvl =
                    managers.player:has_category_upgrade("first_aid_kit", "damage_reduction_upgrade") and 1 or 0
                local auto_recovery =
                    managers.player:has_category_upgrade("first_aid_kit", "first_aid_kit_auto_recovery") and 1 or 0
                local bits =
                    Bitwise:lshift(auto_recovery, FirstAidKitBase.auto_recovery_shift) +
                    Bitwise:lshift(upgrade_lvl, FirstAidKitBase.upgrade_lvl_shift)

                if Network:is_client() then
                    if auto_recovery == 1 then
                        local min_distance = tweak_data.upgrades.values.first_aid_kit.first_aid_kit_auto_recovery[1]
                        ClientsidedUppers.Spawn(pos, rot, min_distance, upgrade_lvl)
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

                managers.enemy:add_delayed_clbk(
                    self._validate_clbk_id,
                    callback(self, self, "_clbk_validate"),
                    Application:time() + 60
                )
            end
        end

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

            if not self._clientsided then
                if managers.network:session() then
                    managers.network:session():send_to_peers_synched("sync_unit_event_id_16", self._unit, "base", 2)
                end
            end
            self:_set_empty()
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
                local fak = ClientsidedUppers.Remove(self._unit:position())
                if fak then
                    if fak._empty then
                        self:sync_usage()
                        return
                    else
                        fak:_set_empty()
                    end
                end
            end

            if self._validate_clbk_id then
                managers.enemy:remove_delayed_clbk(self._validate_clbk_id)

                self._validate_clbk_id = nil
            end

            managers.player:verify_equipment(peer_id, "first_aid_kit")
            self:setup(bits)
        end
    elseif RequiredScript == "lib/units/interactions/interactionext" then
        -- neglect network sync for clientsided faks
        function BaseInteractionExt:set_active(active, sync)
            if active and self:disabled() then
                return
            end

            if self._host_only and not Network:is_server() then
                active = false
            end

            if not active and self._active then
                managers.interaction:remove_unit(self._unit)

                if self._tweak_data.contour_preset or self._tweak_data.contour_preset_selected then
                    if self._contour_id and self._unit:contour() then
                        self._unit:contour():remove_by_id(self._contour_id)
                    end

                    self._contour_id = nil

                    if self._selected_contour_id and self._unit:contour() then
                        self._unit:contour():remove_by_id(self._selected_contour_id)
                    end

                    self._selected_contour_id = nil
                elseif not self._tweak_data.no_contour then
                    managers.occlusion:add_occlusion(self._unit)
                end

                self._is_selected = nil
            elseif active and not self._active then
                managers.interaction:add_unit(self._unit)

                if self._tweak_data.contour_preset then
                    if not self._contour_id then
                        self._contour_id = self._unit:contour():add(self._tweak_data.contour_preset)
                    end
                elseif not self._tweak_data.no_contour then
                    managers.occlusion:remove_occlusion(self._unit)
                end
            end

            self._active = active

            if not self._tweak_data.contour_preset then
                local opacity_value = self:_set_active_contour_opacity()

                self:set_contour("standard_color", opacity_value)
            end

            if not self._tweak_data.clientsided and not self._host_only and sync and managers.network:session() then
                local u_id = self._unit:id()

                if u_id == -1 then
                    local u_data = managers.enemy:get_corpse_unit_data_from_key(self._unit:key())

                    if u_data then
                        u_id = u_data.u_id
                    else
                        debug_pause_unit(
                            self._unit,
                            "[BaseInteractionExt:set_active] could not sync interaction state.",
                            self._unit
                        )

                        return
                    end
                end

                managers.network:session():send_to_peers_synched(
                    "interaction_set_active",
                    self._unit,
                    u_id,
                    active,
                    self.tweak_data,
                    self._unit:contour() and self._unit:contour():is_flashing() or false
                )
            end
        end
    elseif RequiredScript == "lib/units/beings/player/playerdamage" then
        Hooks:PostHook(
            PlayerDamage,
            "init",
            "ClientsidedUppers_PlayerDamage:init",
            function(object, unit)
                if ClientsidedUppers.settings.cooldown_fix then
                    object._uppers_elapsed = -PlayerDamage._UPPERS_COOLDOWN
                end
            end
        )
    elseif RequiredScript == "lib/managers/menumanager" then
        Hooks:Add(
            "LocalizationManagerPostInit",
            "ClientsidedUppers_LocalizationManagerPostInit",
            function(loc)
                loc:load_localization_file(ClientsidedUppers._mod_path .. "loc/english.txt")
            end
        )

        Hooks:Add(
            "MenuManagerInitialize",
            "ClientsidedUppers_MenuManagerInitialize",
            function(menu_manager)
                function MenuCallbackHandler:clientsided_uppers_cooldown_fix_callback(item)
                    ClientsidedUppers.settings.cooldown_fix = item:value() == "on"
                end

                function MenuCallbackHandler:clientsided_uppers_red_callback(item)
                    ClientsidedUppers.settings.red = item:value()
                end

                function MenuCallbackHandler:clientsided_uppers_green_callback(item)
                    ClientsidedUppers.settings.green = item:value()
                end

                function MenuCallbackHandler:clientsided_uppers_blue_callback(item)
                    ClientsidedUppers.settings.blue = item:value()
                end

                function MenuCallbackHandler:clientsided_uppers_opacity_callback(item)
                    ClientsidedUppers.settings.opacity = item:value()
                end

                function MenuCallbackHandler:clientsided_uppers_back_callback(item)
                    ClientsidedUppers.SetTweakData()
                    ClientsidedUppers:Save()
                end

                function MenuCallbackHandler:clientsided_uppers_default_callback(item)
                    MenuHelper:ResetItemsToDefaultValue(item, {["clientsided_uppers_cooldown_fix"] = true}, true)
                    MenuHelper:ResetItemsToDefaultValue(item, {["clientsided_uppers_red"] = true}, 0.1)
                    MenuHelper:ResetItemsToDefaultValue(item, {["clientsided_uppers_green"] = true}, 1)
                    MenuHelper:ResetItemsToDefaultValue(item, {["clientsided_uppers_blue"] = true}, 0.5)
                    MenuHelper:ResetItemsToDefaultValue(item, {["clientsided_uppers_opacity"] = true}, 1)
                end

                MenuHelper:LoadFromJsonFile(
                    ClientsidedUppers._mod_path .. "menu/options.json",
                    ClientsidedUppers,
                    ClientsidedUppers.settings
                )
            end
        )
    end
end

ClientsidedUppers:Setup()
