-- at playerdamage creation cooldown is fixed
Hooks:PostHook(PlayerDamage, "init", "ClientsidedUppers_PlayerDamage:init", function(object, unit)
    if ClientsidedUppers.settings.cooldown_fix then
        object._uppers_elapsed = -PlayerDamage._UPPERS_COOLDOWN
    end
end)
