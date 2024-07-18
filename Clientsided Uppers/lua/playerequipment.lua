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
        local bits = Bitwise:lshift(auto_recovery, FirstAidKitBase.auto_recovery_shift) +
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
