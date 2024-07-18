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
                debug_pause_unit(self._unit, "[BaseInteractionExt:set_active] could not sync interaction state.",
                    self._unit)

                return
            end
        end

        managers.network:session():send_to_peers_synched("interaction_set_active", self._unit, u_id, active,
            self.tweak_data, self._unit:contour() and self._unit:contour():is_flashing() or false)
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
        if color == "standard_color" or (color == "selected_color" and ClientsidedUppers.settings.override_selected) then
            contour_color = ClientsidedUppers._contour_color
            contour_opacity = ClientsidedUppers.settings.opacity
        end
    end

    local ids_contour_color = Idstring("contour_color")
    local ids_contour_opacity = Idstring("contour_opacity")

    for _, m in ipairs(self._materials) do
        m:set_variable(ids_contour_color, contour_color)
        m:set_variable(ids_contour_opacity, self._active and (contour_opacity or 1) or 0)
    end
end

-- when interation with a clientsided FAK was interrupted
-- and this FAK has already been synced during the interaction
-- set it empty
function DoctorBagBaseInteractionExt:interact_interupt(player, complete)
    DoctorBagBaseInteractionExt.super.super.interact_interupt(self, player, complete)

    local fak = self._unit:base()

    if self._clientsided and fak and fak._linked_fak and not complete then
        fak._empty = true
        fak:delete_clientsided()
    end
end
