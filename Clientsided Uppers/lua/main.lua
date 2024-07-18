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

local function deep_copy(orig)
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
    ClientsidedUppers._contour_color = Vector3(ClientsidedUppers.settings.red, ClientsidedUppers.settings.green,
        ClientsidedUppers.settings.blue)
end

-- notify that a clientsided FAK was taken
function ClientsidedUppers.Notify()
    managers.chat:_receive_message(ChatManager.GAME, "CLIENTSIDED UPPERS", "FirstAidKit consumed.",
        Color(1, 0.1, 1, 0.5))
end

function ClientsidedUppers.UpdateButtons()
    for _, item in pairs(MenuHelper:GetMenu("clientsided_uppers")._items_list) do
        if item:name() == "clientsided_uppers_red" or item:name() == "clientsided_uppers_green" or item:name() ==
            "clientsided_uppers_blue" or item:name() == "clientsided_uppers_opacity" or item:name() ==
            "clientsided_uppers_override_selected" then
            item:set_enabled(ClientsidedUppers.settings.custom_contour)
        end
    end
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
    table.insert(ClientsidedUppers.List, {
        obj = obj,
        pos = pos
    })
end

function ClientsidedUppers.RemoveFromUppers(fak)
    for i, o in pairs(ClientsidedUppers.List) do
        if o.obj == fak then
            o.obj = nil
        end
    end

    if fak._min_distance then
        FirstAidKitBase.Remove(fak)
    end
end

-- removes the closest clientsided FAK from the list
-- if the fak is empty it's usage is synchronized
function ClientsidedUppers.Remove(pos)
    local closest_dst = -1
    local closest_index = 0
    local closest_fak = nil

    for i, o in pairs(ClientsidedUppers.List) do
        local dst = mvector3.distance(o.pos, pos)

        if dst <= closest_dst or closest_dst == -1 then
            closest_dst = dst
            closest_index = i
            closest_fak = o.obj
        end
    end

    if closest_index then
        table.remove(ClientsidedUppers.List, closest_index)

        if closest_fak and closest_fak._min_distance then
            FirstAidKitBase.Remove(closest_fak)
        end
    end

    return closest_fak
end

-- setup hooks
function ClientsidedUppers.SetupHooks()
    if RequiredScript == "lib/managers/menumanager" then
        Hooks:Add("LocalizationManagerPostInit", "ClientsidedUppers_LocalizationManagerPostInit", function(loc)
            loc:load_localization_file(ClientsidedUppers._mod_path .. "loc/english.txt")
        end)

        Hooks:Add("MenuManagerInitialize", "ClientsidedUppers_MenuManagerInitialize", function(menu_manager)
            function MenuCallbackHandler:clientsided_uppers_cooldown_fix_callback(item)
                ClientsidedUppers.settings.cooldown_fix = item:value() == "on"
            end

            function MenuCallbackHandler:clientsided_uppers_notify_callback(item)
                ClientsidedUppers.settings.notify = item:value() == "on"
            end

            function MenuCallbackHandler:clientsided_uppers_custom_contour_callback(item)
                ClientsidedUppers.settings.custom_contour = item:value() == "on"

                ClientsidedUppers.UpdateButtons()
            end

            function MenuCallbackHandler:clientsided_uppers_red_callback(item)
                ClientsidedUppers.settings.red = math.round_with_precision(item:value(), 2)
            end

            function MenuCallbackHandler:clientsided_uppers_green_callback(item)
                ClientsidedUppers.settings.green = math.round_with_precision(item:value(), 2)
            end

            function MenuCallbackHandler:clientsided_uppers_blue_callback(item)
                ClientsidedUppers.settings.blue = math.round_with_precision(item:value(), 2)
            end

            function MenuCallbackHandler:clientsided_uppers_opacity_callback(item)
                ClientsidedUppers.settings.opacity = math.round_with_precision(item:value(), 2)
            end

            function MenuCallbackHandler:clientsided_uppers_override_selected_callback(item)
                ClientsidedUppers.settings.override_selected = item:value() == "on"
            end

            function MenuCallbackHandler:clientsided_uppers_back_callback(item)
                ClientsidedUppers.CreateContourColor()
                ClientsidedUppers:Save()
            end

            function MenuCallbackHandler:clientsided_uppers_default_callback(item)
                MenuHelper:ResetItemsToDefaultValue(item, {
                    ["clientsided_uppers_cooldown_fix"] = true
                }, true)
                MenuHelper:ResetItemsToDefaultValue(item, {
                    ["clientsided_uppers_notify"] = true
                }, false)
                MenuHelper:ResetItemsToDefaultValue(item, {
                    ["clientsided_uppers_custom_contour"] = true
                }, true)
                MenuHelper:ResetItemsToDefaultValue(item, {
                    ["clientsided_uppers_red"] = true
                }, 0.1)
                MenuHelper:ResetItemsToDefaultValue(item, {
                    ["clientsided_uppers_green"] = true
                }, 0.4)
                MenuHelper:ResetItemsToDefaultValue(item, {
                    ["clientsided_uppers_blue"] = true
                }, 1)
                MenuHelper:ResetItemsToDefaultValue(item, {
                    ["clientsided_uppers_opacity"] = true
                }, 1)
                MenuHelper:ResetItemsToDefaultValue(item, {
                    ["clientsided_uppers_override_selected"] = true
                }, true)

                ClientsidedUppers.UpdateButtons()
            end

            MenuHelper:LoadFromJsonFile(ClientsidedUppers._options_menu_file, ClientsidedUppers,
                ClientsidedUppers.settings)
        end)
    end
end

ClientsidedUppers:Setup()
