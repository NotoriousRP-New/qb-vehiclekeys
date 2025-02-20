-----------------------
----   Variables   ----
-----------------------
local QBCore = exports['qb-core']:GetCoreObject()
local KeysList = {}

local isTakingKeys = false
local isCarjacking = false
local canCarjack = true
local AlertSend = false
local lastPickedVehicle = nil
local usingAdvanced = false
local IsHotwiring = false

-----------------------
----   Threads     ----
-----------------------

CreateThread(function()
    while true do
        local sleep = 1000
        if LocalPlayer.state.isLoggedIn then
            sleep = 100

            local ped = PlayerPedId()
            local entering = GetVehiclePedIsTryingToEnter(ped)
            local carIsImmune = false
            if entering ~= 0 and not isBlacklistedVehicle(entering) then
                sleep = 2000
                local plate = QBCore.Functions.GetPlate(entering)

                local driver = GetPedInVehicleSeat(entering, -1)
                for _, veh in ipairs(Config.ImmuneVehicles) do
                    if GetEntityModel(entering) == joaat(veh) then
                        carIsImmune = true
                    end
                end
                -- Driven vehicle logic
                if driver ~= 0 and not IsPedAPlayer(driver) and not HasKeys(plate) and not carIsImmune then
                    if IsEntityDead(driver) then
                        if not isTakingKeys then
                            isTakingKeys = true

                            TriggerServerEvent('qb-vehiclekeys:server:setVehLockState', NetworkGetNetworkIdFromEntity(entering), 1)
                            if lib.progressCircle({
                                duration = 2500,
                                label = Lang:t("progress.takekeys"),
                                position = 'bottom',
                                useWhileDead = false,
                                canCancel = true,
                                disable = {
                                    car = true,
                                },
                            }) then
                                TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', plate)
                                isTakingKeys = false
                            else
                                isTakingKeys = false
                            end
                        end
                    elseif Config.LockNPCDrivingCars then
                        TriggerServerEvent('qb-vehiclekeys:server:setVehLockState', NetworkGetNetworkIdFromEntity(entering), 2)
                    else
                        TriggerServerEvent('qb-vehiclekeys:server:setVehLockState', NetworkGetNetworkIdFromEntity(entering), 1)
                        TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', plate)

                        --Make passengers flee
                        local pedsInVehicle = GetPedsInVehicle(entering)
                        for _, pedInVehicle in pairs(pedsInVehicle) do
                            if pedInVehicle ~= GetPedInVehicleSeat(entering, -1) then
                                MakePedFlee(pedInVehicle)
                            end
                        end
                    end
                -- Parked car logic
                elseif driver == 0 and entering ~= lastPickedVehicle and not HasKeys(plate) and not isTakingKeys then
                    if Config.LockNPCParkedCars then
                        QBCore.Functions.TriggerCallback('qb-vehiclekeys:server:checkOwned', function(result)
                            if not result then
                                TriggerServerEvent('qb-vehiclekeys:server:setVehLockState', NetworkGetNetworkIdFromEntity(entering), 2)
                            end
                        end, plate)
                    else
                        TriggerServerEvent('qb-vehiclekeys:server:setVehLockState', NetworkGetNetworkIdFromEntity(entering), 1)
                    end
                end
            end

            -- Hotwiring while in vehicle, also keeps engine off for vehicles you don't own keys to
            if IsPedInAnyVehicle(ped, false) and not IsHotwiring then
                sleep = 1000
                local vehicle = GetVehiclePedIsIn(ped)
                local plate = QBCore.Functions.GetPlate(vehicle)

                if GetPedInVehicleSeat(vehicle, -1) == PlayerPedId() and not HasKeys(plate) and not isBlacklistedVehicle(vehicle) and not AreKeysJobShared(vehicle) then
                    sleep = 0

                    local vehiclePos = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 1.0, 0.5)
                    DrawText3D(vehiclePos.x, vehiclePos.y, vehiclePos.z, Lang:t("info.search_keys"))
                    SetVehicleEngineOn(vehicle, false, false, true)

                    if IsControlJustPressed(0, 74) then
                        Hotwire(vehicle, plate)
                    end
                end
            end

            if Config.CarJackEnable and canCarjack then
                local playerid = PlayerId()
                local aiming, target = GetEntityPlayerIsFreeAimingAt(playerid)
                if aiming and (target ~= nil and target ~= 0) then
                    if DoesEntityExist(target) and IsPedInAnyVehicle(target, false) and not IsEntityDead(target) and not IsPedAPlayer(target) then
                        local targetveh = GetVehiclePedIsIn(target)
                        for _, veh in ipairs(Config.ImmuneVehicles) do
                            if GetEntityModel(targetveh) == joaat(veh) then
                                carIsImmune = true
                            end
                        end
                        if GetPedInVehicleSeat(targetveh, -1) == target and not IsBlacklistedWeapon() then
                            local pos = GetEntityCoords(ped, true)
                            local targetpos = GetEntityCoords(target, true)
                            if #(pos - targetpos) < 5.0 and not carIsImmune then
                                CarjackVehicle(target)
                            end
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

function isBlacklistedVehicle(vehicle)
    local isBlacklisted = false
    for _,v in ipairs(Config.NoLockVehicles) do
        if GetHashKey(v) == GetEntityModel(vehicle) then
            isBlacklisted = true
            break;
        end
    end
    if Entity(vehicle).state.ignoreLocks or GetVehicleClass(vehicle) == 13 then isBlacklisted = true end
    return isBlacklisted
end

-----------------------
---- Client Events ----
-----------------------

RegisterKeyMapping('togglelocks', Lang:t("info.toggle_locks"), 'keyboard', 'L')
RegisterCommand('togglelocks', function()
    ToggleVehicleLocks(GetVehicle())
end)

RegisterKeyMapping('engine', Lang:t("info.engine"), 'keyboard', 'G')
RegisterCommand('engine', function()
    TriggerEvent("qb-vehiclekeys:client:ToggleEngine")
end)

AddEventHandler('onResourceStart', function(resourceName)
	if resourceName == GetCurrentResourceName() and QBCore.Functions.GetPlayerData() ~= {} then
		GetKeys()
	end
end)

-- Handles state right when the player selects their character and location.
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    GetKeys()
end)

-- Resets state on logout, in case of character change.
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    KeysList = {}
end)

RegisterNetEvent('qb-vehiclekeys:client:AddKeys', function(plate)
    KeysList[plate] = true

    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        local vehicle = GetVehiclePedIsIn(ped)
        local vehicleplate = QBCore.Functions.GetPlate(vehicle)

        if plate == vehicleplate then
            SetVehicleEngineOn(vehicle, false, false, false)
        end
    end
end)

RegisterNetEvent('qb-vehiclekeys:client:RemoveKeys', function(plate)
    KeysList[plate] = nil
end)

RegisterNetEvent('qb-vehiclekeys:client:ToggleEngine', function()
    local EngineOn = GetIsVehicleEngineRunning(GetVehiclePedIsIn(PlayerPedId()))
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), true)
    if HasKeys(QBCore.Functions.GetPlate(vehicle)) then
        if EngineOn then
            SetVehicleEngineOn(vehicle, false, false, true)
        else
            SetVehicleEngineOn(vehicle, true, false, true)
        end
    end
end)

RegisterNetEvent('qb-vehiclekeys:client:GiveKeys', function(id)
    local targetVehicle = GetVehicle()

    if targetVehicle then
        local targetPlate = QBCore.Functions.GetPlate(targetVehicle)
        if HasKeys(targetPlate) then
            if id and type(id) == "number" then -- Give keys to specific ID
                GiveKeys(id, targetPlate)
            else
                if IsPedSittingInVehicle(PlayerPedId(), targetVehicle) then -- Give keys to everyone in vehicle
                    local otherOccupants = GetOtherPlayersInVehicle(targetVehicle)
                    for p=1,#otherOccupants do
                        TriggerServerEvent('qb-vehiclekeys:server:GiveVehicleKeys', GetPlayerServerId(NetworkGetPlayerIndexFromPed(otherOccupants[p])), targetPlate)
                    end
                else -- Give keys to closest player
                    GiveKeys(GetPlayerServerId(QBCore.Functions.GetClosestPlayer()), targetPlate)
                end
            end
        else
            lib.notify({ description = Lang:t("notify.no_keys"), type = 'error' })
        end
    end
end)

exports('lockpick', function(data, slot)
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local vehicle = QBCore.Functions.GetClosestVehicle()
    local canLockpick = true

    if vehicle == nil or vehicle == 0 then canLockpick = false end
    if HasKeys(QBCore.Functions.GetPlate(vehicle)) then canLockpick = false end
    if #(pos - GetEntityCoords(vehicle)) > 2.5 then canLockpick = false end
    if GetVehicleDoorLockStatus(vehicle) <= 0 then canLockpick = false end
    for _, veh in ipairs(Config.ImmuneVehicles) do
        if GetEntityModel(vehicle) == joaat(veh) then
            canLockpick = false
        end
    end
    local vehicleClass = GetVehicleClass(vehicle)
    if canLockpick then
        -- Triggers internal-code to correctly use items.
        -- This adds security, removes the item on use, adds progressbar support, and is necessary for server callbacks.
        exports.ox_inventory:useItem(data, function(data)
            -- The server has verified the item can be used.
            if data then
                local success = false

                if vehicleClass == 6 or vehicleCLass == 5 then -- sports/sportsclassics car
                    success = lib.skillCheck({'medium', 'medium'})
                elseif vehicleClass == 7 then --super car
                    success = lib.skillCheck({'hard', 'hard'})
                else -- other car
                    success = lib.skillCheck({'easy', 'medium'})
                end

                if success then
                    TriggerServerEvent('hud:server:GainStress', math.random(1, 3))
                    lastPickedVehicle = vehicle
                    if GetPedInVehicleSeat(vehicle, -1) == PlayerPedId() then
                        TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', QBCore.Functions.GetPlate(vehicle))
                    else
                        lib.notify({ description = Lang:t("notify.vehicle_lockedpick"), type = 'success' })
                        TriggerServerEvent('qb-vehiclekeys:server:setVehLockState', NetworkGetNetworkIdFromEntity(vehicle), 1)
                    end
                    exports['ps-dispatch']:VehicleTheft(vehicle)
                else
                    TriggerServerEvent('hud:server:GainStress', math.random(2, 4))
                end
            end
        end)
    else
        -- Don't use the item
        lib.notify({type = 'error', description = 'You can\'t use this here'})
    end
end)

-- Backwards Compatibility ONLY -- Remove at some point --
RegisterNetEvent('vehiclekeys:client:SetOwner', function(plate)
    TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', plate)
end)
-- Backwards Compatibility ONLY -- Remove at some point --

-----------------------
----   Functions   ----
-----------------------

function GiveKeys(id, plate)
    local distance = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(GetPlayerPed(GetPlayerFromServerId(id))))
    if distance < 1.5 and distance > 0.0 then
        TriggerServerEvent('qb-vehiclekeys:server:GiveVehicleKeys', id, plate)
    else
        lib.notify({ description = Lang:t("notify.not_near"), type = 'error' })
    end
end

function GetKeys()
    QBCore.Functions.TriggerCallback('qb-vehiclekeys:server:GetVehicleKeys', function(keysList)
        KeysList = keysList
    end)
end

function HasKeys(plate)
    return KeysList[plate]
end
exports('HasKeys', HasKeys)

function loadAnimDict(dict)
    while (not HasAnimDictLoaded(dict)) do
        RequestAnimDict(dict)
        Wait(0)
    end
end

function GetVehicleInDirection(coordFromOffset, coordToOffset)
    local ped = PlayerPedId()
    local coordFrom = GetOffsetFromEntityInWorldCoords(ped, coordFromOffset.x, coordFromOffset.y, coordFromOffset.z)
    local coordTo = GetOffsetFromEntityInWorldCoords(ped, coordToOffset.x, coordToOffset.y, coordToOffset.z)

    local rayHandle = CastRayPointToPoint(coordFrom.x, coordFrom.y, coordFrom.z, coordTo.x, coordTo.y, coordTo.z, 10, PlayerPedId(), 0)
    local _, _, _, _, vehicle = GetShapeTestResult(rayHandle)
    return vehicle
end

-- If in vehicle returns that, otherwise tries 3 different raycasts to get the vehicle they are facing.
-- Raycasts picture: https://i.imgur.com/FRED0kV.png
function GetVehicle()
    local vehicle = GetVehiclePedIsIn(PlayerPedId())

    local RaycastOffsetTable = {
        { ['fromOffset'] = vector3(0.0, 0.0, 0.0), ['toOffset'] = vector3(0.0, 20.0, -10.0) }, -- Waist to ground 45 degree angle
        { ['fromOffset'] = vector3(0.0, 0.0, 0.7), ['toOffset'] = vector3(0.0, 10.0, -10.0) }, -- Head to ground 30 degree angle
        { ['fromOffset'] = vector3(0.0, 0.0, 0.7), ['toOffset'] = vector3(0.0, 10.0, -20.0) }, -- Head to ground 15 degree angle
    }

    local count = 0
    while vehicle == 0 and count < #RaycastOffsetTable do
        count = count + 1
        vehicle = GetVehicleInDirection(RaycastOffsetTable[count]['fromOffset'], RaycastOffsetTable[count]['toOffset'])
    end

    if not IsEntityAVehicle(vehicle) then vehicle = nil end
    return vehicle
end

function AreKeysJobShared(veh)
    local vehName = GetDisplayNameFromVehicleModel(GetEntityModel(veh))
    local vehPlate = GetVehicleNumberPlateText(veh)
    local jobName = QBCore.Functions.GetPlayerData().job.name
    local onDuty = QBCore.Functions.GetPlayerData().job.onduty
    for job, v in pairs(Config.SharedKeys) do
        if job == jobName then
	    if Config.SharedKeys[job].requireOnduty and not onDuty then return false end
	    for _, vehicle in pairs(v.vehicles) do
	        if string.upper(vehicle) == string.upper(vehName) then
		    if not HasKeys(vehPlate) then
		        TriggerServerEvent("qb-vehiclekeys:server:AcquireVehicleKeys", vehPlate)
		    end
		    return true
	        end
            end
        end
    end
    return false
end

function ToggleVehicleLocks(veh)
    if veh then
        if not isBlacklistedVehicle(veh) then
            if HasKeys(QBCore.Functions.GetPlate(veh)) or AreKeysJobShared(veh) then
                local ped = PlayerPedId()
                local vehLockStatus = GetVehicleDoorLockStatus(veh)

                loadAnimDict("anim@mp_player_intmenu@key_fob@")
                TaskPlayAnim(ped, 'anim@mp_player_intmenu@key_fob@', 'fob_click', 3.0, 3.0, -1, 49, 0, false, false, false)

                TriggerServerEvent("InteractSound_SV:PlayWithinDistance", 5, "lock", 0.3)

                NetworkRequestControlOfEntity(veh)
                if vehLockStatus == 1 then
                    TriggerServerEvent('qb-vehiclekeys:server:setVehLockState', NetworkGetNetworkIdFromEntity(veh), 2)
                    lib.notify({ description = Lang:t("notify.vehicle_locked"), type = 'inform' })
                else
                    TriggerServerEvent('qb-vehiclekeys:server:setVehLockState', NetworkGetNetworkIdFromEntity(veh), 1)
                    lib.notify({ description = Lang:t("notify.vehicle_unlocked"), type = 'inform' })
                end

                SetVehicleLights(veh, 2)
                Wait(250)
                SetVehicleLights(veh, 1)
                Wait(200)
                SetVehicleLights(veh, 0)
                Wait(300)
                ClearPedTasks(ped)
            else
                lib.notify({ description = Lang:t("notify.no_keys"), type = 'error' })
            end
        else
            TriggerServerEvent('qb-vehiclekeys:server:setVehLockState', NetworkGetNetworkIdFromEntity(veh), 1)
        end
    end
end

function GetOtherPlayersInVehicle(vehicle)
    local otherPeds = {}
    for seat=-1,GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))-2 do
        local pedInSeat = GetPedInVehicleSeat(vehicle, seat)
        if IsPedAPlayer(pedInSeat) and pedInSeat ~= PlayerPedId() then
            otherPeds[#otherPeds+1] = pedInSeat
        end
    end
    return otherPeds
end

function GetPedsInVehicle(vehicle)
    local otherPeds = {}
    for seat=-1,GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))-2 do
        local pedInSeat = GetPedInVehicleSeat(vehicle, seat)
        if not IsPedAPlayer(pedInSeat) and pedInSeat ~= 0 then
            otherPeds[#otherPeds+1] = pedInSeat
        end
    end
    return otherPeds
end

function IsBlacklistedWeapon()
    local weapon = GetSelectedPedWeapon(PlayerPedId())
    if weapon ~= nil then
        for _, v in pairs(Config.NoCarjackWeapons) do
            if weapon == GetHashKey(v) then
                return true
            end
        end
    end
    return false
end

function Hotwire(vehicle, plate)
    local hotwireTime = math.random(Config.minHotwireTime, Config.maxHotwireTime)
    local ped = PlayerPedId()
    IsHotwiring = true

    SetVehicleAlarm(vehicle, true)
    SetVehicleAlarmTimeLeft(vehicle, hotwireTime)
    if lib.progressCircle({
        duration = hotwireTime,
        label = Lang:t("progress.searching_keys"),
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        anim = {
            dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@',
            clip = 'machinic_loop_mechandplayer'
        },
    }) then
        StopAnimTask(ped, "anim@amb@clubhouse@tutorial@bkr_tut_ig3@", "machinic_loop_mechandplayer", 1.0)
        TriggerServerEvent('hud:server:GainStress', math.random(1, 4))
        if (math.random() <= Config.HotwireChance) then
            TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', plate)
        else
            lib.notify({ description = Lang:t("notify.failed_lockedpick"), type = 'error' })
        end
        Wait(Config.TimeBetweenHotwires)
        IsHotwiring = false
    else
        StopAnimTask(ped, "anim@amb@clubhouse@tutorial@bkr_tut_ig3@", "machinic_loop_mechandplayer", 1.0)
        IsHotwiring = false
    end
    SetTimeout(10000, function()
        exports['ps-dispatch']:VehicleTheft(vehicle)
    end)
    IsHotwiring = false
end

function CarjackVehicle(target)
    if not Config.CarJackEnable then return end
    isCarjacking = true
    canCarjack = false
    loadAnimDict('mp_am_hold_up')
    local vehicle = GetVehiclePedIsUsing(target)
    local occupants = GetPedsInVehicle(vehicle)
    for p=1,#occupants do
        local ped = occupants[p]
        CreateThread(function()
            TaskPlayAnim(ped, "mp_am_hold_up", "holdup_victim_20s", 8.0, -8.0, -1, 49, 0, false, false, false)
            PlayPain(ped, 6, 0)
        end)
        Wait(math.random(200,500))
    end
    -- Cancel progress bar if: Ped dies during robbery, car gets too far away
    CreateThread(function()
        while isCarjacking do
            local distance = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(target))
            if IsPedDeadOrDying(target) or distance > 7.5 then
                lib.cancelProgress()
            end
            Wait(100)
        end
    end)
    
    if lib.progressCircle({
        duration = Config.CarjackingTime,
        label = Lang:t("progress.attempting_carjack"),
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = {
            car = true,
        },
    }) then
        local hasWeapon, weaponHash = GetCurrentPedWeapon(PlayerPedId(), true)
        if hasWeapon and isCarjacking then
            local carjackChance
            if Config.CarjackChance[tostring(GetWeapontypeGroup(weaponHash))] then
                carjackChance = Config.CarjackChance[tostring(GetWeapontypeGroup(weaponHash))]
            else
                carjackChance = 0.5
            end
            if math.random() <= carjackChance then
                local plate = QBCore.Functions.GetPlate(vehicle)
                    for p=1,#occupants do
                        local ped = occupants[p]
                        CreateThread(function()
                        TaskLeaveVehicle(ped, vehicle, 0)
                        PlayPain(ped, 6, 0)
                        Wait(1250)
                        ClearPedTasksImmediately(ped)
                        PlayPain(ped, math.random(7,8), 0)
                        MakePedFlee(ped)
                    end)
                end
                TriggerServerEvent('hud:server:GainStress', math.random(1, 4))
                TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', plate)
            else
                lib.notify({ description = Lang:t("notify.carjack_failed"), type = 'error' })
                MakePedFlee(target)
                TriggerServerEvent('hud:server:GainStress', math.random(1, 4))
            end
            isCarjacking = false
            Wait(2000)
            exports['ps-dispatch']:CarJacking(vehicle)
            Wait(Config.DelayBetweenCarjackings)
            canCarjack = true
        end
    else
        MakePedFlee(target)
        isCarjacking = false
        Wait(Config.DelayBetweenCarjackings)
        canCarjack = true
    end
end


function MakePedFlee(ped)
    SetPedFleeAttributes(ped, 0, 0)
    TaskReactAndFleePed(ped, PlayerPedId())
end

function DrawText3D(x, y, z, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry("STRING")
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(x, y, z, 0)
    DrawText(0.0, 0.0)
    local factor = (string.len(text)) / 370
    DrawRect(0.0, 0.0 + 0.0125, 0.017 + factor, 0.03, 0, 0, 0, 75)
    ClearDrawOrigin()
end
