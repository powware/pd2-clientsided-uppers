ClientsidedUppers = ClientsidedUppers or {}
ClientsidedUppers.default_settings = {
    cooldown_fix = true,
    notify = false,
    custom_contour = true,
    red = 0.1,
    green = 0.4,
    blue = 1,
    opacity = 1,
    override_selected = true
}
ClientsidedUppers._mod_path = ModPath
ClientsidedUppers._options_menu_file = ClientsidedUppers._mod_path .. "menu/options.json"
ClientsidedUppers._save_path = SavePath
ClientsidedUppers._save_file = ClientsidedUppers._save_path .. "clientsided_uppers.json"
ClientsidedUppers.List = {}

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

function round(num, numDecimalPlaces)
    local mult = 10 ^ (numDecimalPlaces or 0)
    return math.floor(num * mult + 0.5) / mult
end

-- setup mod
function ClientsidedUppers:Setup()
    if not self.settings then
        self:Load()
        self.CreateContourColor()
    end

    self.SetupHooks()
end

-- load settings from file
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

-- save settings to file
function ClientsidedUppers:Save()
    local file = io.open(self._save_file, "w+")
    if file then
        file:write(json.encode(self.settings))
        file:close()
    end
end

-- combines the parts of the color from the settings
function ClientsidedUppers.CreateContourColor()
    ClientsidedUppers._contour_color =
        Vector3(ClientsidedUppers.settings.red, ClientsidedUppers.settings.green, ClientsidedUppers.settings.blue)
end

-- notify that a clientsided FAK was taken
function ClientsidedUppers.Notify()
    managers.chat:_receive_message(
        ChatManager.GAME,
        "SYSTEM",
        "Clientsided FirstAidKit was consumed.",
        tweak_data.system_chat_color
    )
end

-- spawns a fak without network sync as a custom asset
function ClientsidedUppers.Spawn(pos, rot, min_distance, auto_recovery, upgrade_lvl)
    local unit_name =
        "units/pd2_dlc_old_hoxton/equipment/gen_equipment_first_aid_kit/gen_equipment_first_aid_kit_clientsided"
    local unit = World:spawn_unit(Idstring(unit_name), pos, rot)
    local fak = unit:base()
    local pos = unit:position()
    fak._damage_reduction_upgrade = upgrade_lvl == 1

    ClientsidedUppers.Add(fak, pos)

    if auto_recovery == 1 then
        fak._min_distance = min_distance

        FirstAidKitBase.Add(fak, pos, min_distance)
    end
end

-- add clientsided FAK to a list of clientsided FAKs
function ClientsidedUppers.Add(obj, pos)
    table.insert(
        ClientsidedUppers.List,
        {
            obj = obj,
            pos = pos
        }
    )
end

-- removes the closest clientsided FAK from the list
-- if the fak is empty it's usage is synchronized
function ClientsidedUppers.Remove(pos)
    local closest_dst = -1
    local closest = 0
    local closest_fak = nil

    for i, o in pairs(ClientsidedUppers.List) do
        local dst = mvector3.distance(pos, o.pos)

        if o.obj._clientsided and (dst <= closest_dst or closest_dst == -1) then
            closest_dst = dst
            closest = i
            closest_fak = o.obj
        end
    end

    if closest_fak then
        table.remove(ClientsidedUppers.List, closest)

        if closest_fak._min_distance then
            FirstAidKitBase.Remove(closest_fak)
        end
    end

    return closest_fak
end

-- setup hooks
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
                    local min_distance = tweak_data.upgrades.values.first_aid_kit.first_aid_kit_auto_recovery[1]
                    ClientsidedUppers.Spawn(pos, rot, min_distance, auto_recovery, upgrade_lvl)

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
                if self._removal_needed then
                    self._linked_fak:sync_usage()
                end

                if ClientsidedUppers.settings.notify then
                    ClientsidedUppers.Notify()
                end
            else
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
                        local interaction = fak._unit:interaction()
                        if interaction and interaction._tweak_data_at_interact_start == interaction.tweak_data then
                            fak._removal_needed = true
                            fak._linked_fak = self
                        else
                            fak:_set_empty()
                        end
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
        -- when an interaction object from the kind clientsided FAK is created
        -- it receives a clientsided tag for interaction
        function BaseInteractionExt:init(unit)
            self._unit = unit

            if self._unit:base() and self._unit:base()._clientsided then
                self._clientsided = true
            end

            self._unit:set_extension_update_enabled(Idstring("interaction"), false)
            self:refresh_material()

            if not tweak_data.interaction[self.tweak_data] then
                print("[BaseInteractionExt:init] - Missing Interaction Tweak Data: ", self.tweak_data)
            end

            self:set_tweak_data(self.tweak_data)
            self:set_host_only(self.is_host_only)
            self:set_active(self._tweak_data.start_active or self._tweak_data.start_active == nil and true)
            self:_upd_interaction_topology()
        end

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

            if not self._clientsided and not self._host_only and sync and managers.network:session() then
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

        -- when clientsided and custom color is enabled
        -- apply the color instead of the regular color
        function BaseInteractionExt:set_contour(color, opacity)
            if self._tweak_data.no_contour or self._contour_override then
                return
            end

            local contour_color = tweak_data.contour[self._tweak_data.contour or "interactable"][color]
            local contour_opacity = opacity

            if self._clientsided and ClientsidedUppers.settings.custom_contour then
                if
                    color == "standard_color" or
                        (color == "selected_color" and ClientsidedUppers.settings.override_selected)
                 then
                    contour_color = ClientsidedUppers._contour_color
                    contour_opacity = ClientsidedUppers.settings.opacity
                end
            end

            local ids_contour_color = Idstring("contour_color")
            local ids_contour_opacity = Idstring("contour_opacity")

            for _, m in ipairs(self._materials) do
                m:set_variable(ids_contour_color, contour_color)
                m:set_variable(ids_contour_opacity, contour_opacity or self._active and 1 or 0)
            end
        end

        -- when interation with a clientsided FAK was interrupted
        -- and this FAK has already been synced durin the interaction
        -- set it empty
        function DoctorBagBaseInteractionExt:interact_interupt(player, complete)
            DoctorBagBaseInteractionExt.super.super.interact_interupt(self, player, complete)

            local fak = self._unit:base()

            if self._clientsided and not complete and fak and fak._removal_needed then
                fak:_set_empty()
            end
        end
    elseif RequiredScript == "lib/units/beings/player/playerdamage" then
        -- at playerdamage creation cooldown is fixed
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

                function MenuCallbackHandler:clientsided_uppers_notify_callback(item)
                    ClientsidedUppers.settings.notify = item:value() == "on"
                end

                function MenuCallbackHandler:clientsided_uppers_custom_contour_callback(item)
                    ClientsidedUppers.settings.custom_contour = item:value() == "on"
                end

                function MenuCallbackHandler:clientsided_uppers_red_callback(item)
                    ClientsidedUppers.settings.red = round(item:value(), 2)
                end

                function MenuCallbackHandler:clientsided_uppers_green_callback(item)
                    ClientsidedUppers.settings.green = round(item:value(), 2)
                end

                function MenuCallbackHandler:clientsided_uppers_blue_callback(item)
                    ClientsidedUppers.settings.blue = round(item:value(), 2)
                end

                function MenuCallbackHandler:clientsided_uppers_opacity_callback(item)
                    ClientsidedUppers.settings.opacity = round(item:value(), 2)
                end

                function MenuCallbackHandler:clientsided_uppers_override_selected_callback(item)
                    ClientsidedUppers.settings.override_selected = item:value() == "on"
                end

                function MenuCallbackHandler:clientsided_uppers_back_callback(item)
                    ClientsidedUppers.CreateContourColor()
                    ClientsidedUppers:Save()
                end

                function MenuCallbackHandler:clientsided_uppers_default_callback(item)
                    MenuHelper:ResetItemsToDefaultValue(item, {["clientsided_uppers_cooldown_fix"] = true}, true)
                    MenuHelper:ResetItemsToDefaultValue(item, {["clientsided_uppers_notify"] = true}, false)
                    MenuHelper:ResetItemsToDefaultValue(item, {["clientsided_uppers_custom_contour"] = true}, true)
                    MenuHelper:ResetItemsToDefaultValue(item, {["clientsided_uppers_red"] = true}, 0.1)
                    MenuHelper:ResetItemsToDefaultValue(item, {["clientsided_uppers_green"] = true}, 0.4)
                    MenuHelper:ResetItemsToDefaultValue(item, {["clientsided_uppers_blue"] = true}, 1)
                    MenuHelper:ResetItemsToDefaultValue(item, {["clientsided_uppers_opacity"] = true}, 1)
                    MenuHelper:ResetItemsToDefaultValue(item, {["clientsided_uppers_override_selected"] = true}, true)
                end

                MenuHelper:LoadFromJsonFile(
                    ClientsidedUppers._options_menu_file,
                    ClientsidedUppers,
                    ClientsidedUppers.settings
                )
            end
        )
    end
end

ClientsidedUppers:Setup()
