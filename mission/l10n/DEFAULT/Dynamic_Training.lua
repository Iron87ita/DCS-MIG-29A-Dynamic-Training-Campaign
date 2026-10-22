-- MiG-29A TRAINING CAMPAIGN - Caucasus / Kobuleti
-- Single-MIZ MiG-29A training campaign with per-player progress persistence when DCS file I/O is enabled.
-- Campaign ground forces remain fixed; campaign air opposition scales 1:1 with active BLUE players (1-4). Free-training assets can also be spawned from F10.
if M29CAMP and M29CAMP._initialized then return end
M29CAMP = M29CAMP or {}
local T = M29CAMP
T._initialized = true
T.version = "1.1-FF-EN"
T.counter = T.counter or 0
T.airGroups = T.airGroups or {}
T.groundGroups = T.groundGroups or {}
T.tankerGroups = T.tankerGroups or {}
T.menuGroups = T.menuGroups or {}
T.completed = T.completed or {}
T.progressPlayers = T.progressPlayers or {}
T.persistenceAvailable = false
T.persistencePath = nil
T.scoredKills = T.scoredKills or {}
T.activeScenario = nil
T.laserCode = 1688
T.laserEnabled = true
T.jtacGroup = nil
T.jtacUnit = nil
T.laser = nil
T.currentTargetName = nil
T.targetArea = {x = -290900, z = 688700}
T.defaultPlayerPoint = {x = -318165, y = 18, z = 635727}

local BLUE = coalition.side.BLUE
local RED_COUNTRY = 0   -- Russia
local BLUE_COUNTRY = 2  -- USA
local NM = 1852

local function msg(text, sec)
    trigger.action.outTextForCoalition(BLUE, "MiG-29A CAMPAIGN | " .. text, sec or 15)
end

local function atan2(y, x)
    if x > 0 then return math.atan(y / x) end
    if x < 0 and y >= 0 then return math.atan(y / x) + math.pi end
    if x < 0 and y < 0 then return math.atan(y / x) - math.pi end
    if x == 0 and y > 0 then return math.pi / 2 end
    if x == 0 and y < 0 then return -math.pi / 2 end
    return 0
end

local function rand(minv, maxv) return minv + math.random() * (maxv - minv) end
local function pick(list) return list[math.random(1, #list)] end
local function nextName(prefix)
    T.counter = T.counter + 1
    return prefix .. "_" .. tostring(T.counter)
end

local function safeDestroyGroup(name)
    local g = name and Group.getByName(name) or nil
    if g and Group.isExist(g) then pcall(function() g:destroy() end) end
end

local function getPlayerFromGroup(groupName)
    if groupName then
        local g = Group.getByName(groupName)
        if g and Group.isExist(g) then
            for _, u in ipairs(g:getUnits() or {}) do
                if u and Object.isExist(u) and u:getLife() > 0 and u:getPlayerName() then return u end
            end
        end
    end
    for _, u in ipairs(coalition.getPlayers(BLUE) or {}) do
        if u and Object.isExist(u) and u:getLife() > 0 then return u end
    end
    return nil
end

local function activePlayerCount()
    local count = 0
    for _, u in ipairs(coalition.getPlayers(BLUE) or {}) do
        if u and Object.isExist(u) and u:getLife() > 0 and u:getPlayerName() then
            count = count + 1
        end
    end
    if count < 1 then count = 1 end
    if count > 4 then count = 4 end
    return count
end

local function scaledAirTypes(baseTypes)
    local count = activePlayerCount()
    local scaled = {}
    if not baseTypes or #baseTypes == 0 then return scaled, count end
    for i = 1, count do
        scaled[i] = baseTypes[((i - 1) % #baseTypes) + 1]
    end
    return scaled, count
end

-- -----------------------------------------------------------------------------
-- PER-PLAYER TRAINING PERSISTENCE
-- Saved to Saved Games/DCS/Missions/Saves/MiG29ATrainingFF/progress.dat when
-- io + lfs are available (MissionScripting.lua desanitized). Otherwise the same
-- table is maintained safely in memory for the current mission session.
-- -----------------------------------------------------------------------------
local function activePlayerNames()
    local names, seen = {}, {}
    for _, u in ipairs(coalition.getPlayers(BLUE) or {}) do
        if u and Object.isExist(u) and u:getLife() > 0 then
            local n = u:getPlayerName()
            if n and n ~= "" and not seen[n] then
                seen[n] = true
                names[#names + 1] = n
            end
        end
    end
    return names
end

local function playerNameFromGroup(groupName)
    local u = getPlayerFromGroup(groupName)
    return u and u:getPlayerName() or nil
end

local function ensurePlayerRecord(playerName)
    if not playerName or playerName == "" then return nil end
    local r = T.progressPlayers[playerName]
    if not r then
        r = {score = 0, airKills = 0, groundKills = 0, missions = {}}
        T.progressPlayers[playerName] = r
    end
    r.score = tonumber(r.score) or 0
    r.airKills = tonumber(r.airKills) or 0
    r.groundKills = tonumber(r.groundKills) or 0
    r.missions = r.missions or {}
    return r
end

local function hexEncode(text)
    return (tostring(text or ""):gsub(".", function(c) return string.format("%02X", string.byte(c)) end))
end

local function hexDecode(text)
    return (tostring(text or ""):gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end))
end

local function progressMissionsCSV(record)
    local ids = {}
    for id = 1, 9 do if record.missions[id] then ids[#ids + 1] = tostring(id) end end
    return table.concat(ids, ",")
end

local function initPersistencePath()
    if not io or not lfs or not lfs.writedir or not lfs.mkdir then return nil end
    local root = lfs.writedir()
    local d1 = root .. "Missions"
    local d2 = d1 .. "/Saves"
    local d3 = d2 .. "/MiG29ATrainingFF"
    pcall(function() lfs.mkdir(d1) end)
    pcall(function() lfs.mkdir(d2) end)
    pcall(function() lfs.mkdir(d3) end)
    return d3 .. "/progress.dat"
end

local function loadProgress()
    T.persistencePath = initPersistencePath()
    if not T.persistencePath or not io or not io.open then
        T.persistenceAvailable = false
        return
    end
    T.persistenceAvailable = true
    local f = io.open(T.persistencePath, "r")
    if not f then return end
    for line in f:lines() do
        local hname, score, airKills, groundKills, missions = line:match("^P|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
        if hname then
            local name = hexDecode(hname)
            local r = ensurePlayerRecord(name)
            r.score = tonumber(score) or 0
            r.airKills = tonumber(airKills) or 0
            r.groundKills = tonumber(groundKills) or 0
            r.missions = {}
            for id in tostring(missions or ""):gmatch("%d+") do
                id = tonumber(id)
                if id and id >= 1 and id <= 9 then r.missions[id] = true end
            end
        end
    end
    f:close()
end

local function saveProgress()
    if not T.persistenceAvailable or not T.persistencePath or not io or not io.open then return false end
    local f = io.open(T.persistencePath, "w")
    if not f then
        T.persistenceAvailable = false
        return false
    end
    f:write("MIG29AFFTRAINING|1\n")
    local names = {}
    for name in pairs(T.progressPlayers) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local r = ensurePlayerRecord(name)
        f:write(string.format("P|%s|%d|%d|%d|%s\n", hexEncode(name), r.score, r.airKills, r.groundKills, progressMissionsCSV(r)))
    end
    f:close()
    return true
end

local function missionCompletionForPlayer(playerName, missionId)
    local r = ensurePlayerRecord(playerName)
    if not r then return false end
    if not r.missions[missionId] then
        r.missions[missionId] = true
        r.score = r.score + 100
        saveProgress()
        return true
    end
    saveProgress()
    return false
end

local function addKillScore(playerName, target)
    local r = ensurePlayerRecord(playerName)
    if not r or not target then return end
    local targetName = nil
    pcall(function() targetName = target:getName() end)
    if targetName and T.scoredKills[targetName] then return end
    if targetName then T.scoredKills[targetName] = true end

    local category = nil
    pcall(function()
        local d = target:getDesc()
        category = d and d.category or nil
    end)
    local isAir = Unit and Unit.Category and (category == Unit.Category.AIRPLANE or category == Unit.Category.HELICOPTER)
    if isAir then
        r.airKills = r.airKills + 1
        r.score = r.score + 25
    else
        r.groundKills = r.groundKills + 1
        r.score = r.score + 10
    end
    saveProgress()
end

local function progressText(playerName)
    local r = ensurePlayerRecord(playerName)
    if not r then return "PLAYER RECORD UNAVAILABLE" end
    local done = {}
    for id = 1, 9 do done[#done + 1] = string.format("%02d:%s", id, r.missions[id] and "OK" or "--") end
    return string.format("PLAYER: %s\nSCORE: %d | AIR KILLS: %d | GROUND KILLS: %d\nMISSIONS: %s\nPERSISTENCE: %s",
        playerName, r.score, r.airKills, r.groundKills, table.concat(done, "  "), T.persistenceAvailable and "DISK SAVE ACTIVE" or "SESSION ONLY (DCS io/lfs SANDBOXED)")
end

local function groundHeight(x, z)
    local ok, h = pcall(function() return land.getHeight({x = x, y = z}) end)
    return (ok and h) or 0
end

local function surfaceIsLand(x, z)
    local ok, st = pcall(function() return land.getSurfaceType({x = x, y = z}) end)
    if not ok or not st then return false end
    local landType = (land.SurfaceType and land.SurfaceType.LAND) or 1
    return st == landType
end

local function sceneryDensity(x, z, radius, stopAt)
    if not world or not world.searchObjects or not Object or not Object.Category or not Object.Category.SCENERY then return 0 end
    local volumeType = world.VolumeType and world.VolumeType.SPHERE
    if not volumeType then return 0 end
    local count = 0
    local volume = {id = volumeType, params = {point = {x = x, y = groundHeight(x, z) + 5, z = z}, radius = radius}}
    local ok = pcall(function()
        world.searchObjects(Object.Category.SCENERY, volume, function(obj)
            if obj and Object.isExist(obj) then count = count + 1 end
            return count < stopAt
        end)
    end)
    if not ok then return 0 end
    return count
end

local function openTerrainScore(x, z)
    if not surfaceIsLand(x, z) then return false end
    local baseH = groundHeight(x, z)
    local sampleR = 220
    for i = 1, 8 do
        local a = (i - 1) * (math.pi / 4)
        local sx, sz = x + math.cos(a) * sampleR, z + math.sin(a) * sampleR
        if not surfaceIsLand(sx, sz) then return false end
        if math.abs(groundHeight(sx, sz) - baseH) > 14 then return false end
    end
    if sceneryDensity(x, z, 380, 5) >= 5 then return false end
    return true
end

local function findOpenPointAround(anchorX, anchorZ, radius, tries)
    for _ = 1, tries do
        local a = rand(0, 2 * math.pi)
        local r = math.sqrt(math.random()) * radius
        local x, z = anchorX + math.cos(a) * r, anchorZ + math.sin(a) * r
        if openTerrainScore(x, z) then return x, z end
    end
    return nil, nil
end

-- Ground units need a stricter check than the group centre.
-- This keeps each individual vehicle out of trees/buildings/scenery and off steep terrain.
local function clearGroundSpot(x, z, clearRadius)
    if not surfaceIsLand(x, z) then return false end
    local baseH = groundHeight(x, z)
    local slopeR = 35
    for i = 1, 4 do
        local a = (i - 1) * (math.pi / 2)
        local sx, sz = x + math.cos(a) * slopeR, z + math.sin(a) * slopeR
        if not surfaceIsLand(sx, sz) then return false end
        if math.abs(groundHeight(sx, sz) - baseH) > 4 then return false end
    end
    if sceneryDensity(x, z, clearRadius or 55, 1) > 0 then return false end
    return true
end

local function farEnoughFromUsed(x, z, used, minDistance)
    local minD2 = (minDistance or 55) * (minDistance or 55)
    for _, p in ipairs(used or {}) do
        local dx, dz = x - p.x, z - p.z
        if (dx * dx + dz * dz) < minD2 then return false end
    end
    return true
end

local function findClearGroundUnitPoint(preferredX, preferredZ, centerX, centerZ, used, profile)
    -- FREE F10 targets use a wider no-scenery buffer because they can be spawned repeatedly
    -- in areas that were not designed as campaign target sites.
    local isFree = (profile == "free")
    local clearRadius = isFree and 90 or 55
    local separation = isFree and 85 or 60
    local closeTries = isFree and 80 or 45
    local wideTries = isFree and 180 or 90
    local wideRadius = isFree and 1800 or 1000

    if clearGroundSpot(preferredX, preferredZ, clearRadius) and farEnoughFromUsed(preferredX, preferredZ, used, separation) then
        return preferredX, preferredZ
    end

    -- First search close to the intended formation position.
    for _ = 1, closeTries do
        local a = rand(0, 2 * math.pi)
        local r = 35 + math.sqrt(math.random()) * (isFree and 320 or 210)
        local x, z = preferredX + math.cos(a) * r, preferredZ + math.sin(a) * r
        if clearGroundSpot(x, z, clearRadius) and farEnoughFromUsed(x, z, used, separation) then return x, z end
    end

    -- If that spot is obstructed, search a wider clearing around the group centre.
    for _ = 1, wideTries do
        local a = rand(0, 2 * math.pi)
        local r = 120 + math.sqrt(math.random()) * wideRadius
        local x, z = centerX + math.cos(a) * r, centerZ + math.sin(a) * r
        if clearGroundSpot(x, z, clearRadius) and farEnoughFromUsed(x, z, used, separation) then return x, z end
    end
    return nil, nil
end

local GROUND_SPAWN_ZONE_NAMES = {
    "SPAWN ZONE GROUND",
    "SPAWN ZONE GROUND-1",
    "SPAWN ZONE GROUND-2",
    "SPAWN ZONE GROUND-3",
    "SPAWN ZONE GROUND-4",
    "SPAWN ZONE GROUND-5",
    "SPAWN ZONE GROUND-6",
    "SPAWN ZONE GROUND-7"
}

local function zoneXZ(zone)
    if not zone or not zone.point then return nil, nil end
    return zone.point.x, zone.point.z or zone.point.y
end

local function randomGroundSpawnZone()
    local available = {}
    for _, name in ipairs(GROUND_SPAWN_ZONE_NAMES) do
        local z = trigger.misc.getZone(name)
        if z and z.point and z.radius then
            z._trainingName = name
            available[#available + 1] = z
        end
    end
    if #available == 0 then return nil end
    return available[math.random(1, #available)]
end

local function findPointInsideGroundZone(zone, used, clearRadius, separation, tries)
    local zx, zz = zoneXZ(zone)
    if not zx then return nil, nil end
    clearRadius = clearRadius or 35
    separation = separation or 70
    local maxR = math.max(30, (zone.radius or 450) - clearRadius - 12)
    for _ = 1, (tries or 220) do
        local a = rand(0, 2 * math.pi)
        local r = math.sqrt(math.random()) * maxR
        local x, z = zx + math.cos(a) * r, zz + math.sin(a) * r
        if clearGroundSpot(x, z, clearRadius) and farEnoughFromUsed(x, z, used, separation) then
            return x, z
        end
    end
    if clearGroundSpot(zx, zz, clearRadius) and farEnoughFromUsed(zx, zz, used, separation) then return zx, zz end
    return nil, nil
end

local function mgrsText(p)
    local ok, result = pcall(function()
        local lat, lon = coord.LOtoLL(p)
        local m = coord.LLtoMGRS(lat, lon)
        return string.format("%s %s %05d %05d", m.UTMZone or "", m.MGRSDigraph or "", math.floor(m.Easting or 0), math.floor(m.Northing or 0))
    end)
    return (ok and result) or "coordinates unavailable"
end

local function stopLaser()
    if T.laser then pcall(function() T.laser:destroy() end) end
    T.laser = nil
    T.currentTargetName = nil
end

local function clearAir(silent)
    for _, name in ipairs(T.airGroups) do safeDestroyGroup(name) end
    T.airGroups = {}
    if not silent then msg("Air training contacts removed.") end
end

local function clearGround(silent)
    stopLaser()
    for _, name in ipairs(T.groundGroups) do safeDestroyGroup(name) end
    T.groundGroups = {}
    if T.jtacGroup then safeDestroyGroup(T.jtacGroup) end
    T.jtacGroup, T.jtacUnit = nil, nil
    if not silent then msg("Ground training targets removed.") end
end

local function clearTankers(silent)
    for _, name in pairs(T.tankerGroups) do safeDestroyGroup(name) end
    T.tankerGroups = {}
    if not silent then msg("Support tanker removed.") end
end

local function clearRange(silent)
    clearAir(true)
    clearGround(true)
    T.activeScenario = nil
    if not silent then msg("Training range reset. Select another campaign mission or free-training exercise.") end
end

local function findAliveGroundTarget()
    if T.currentTargetName then
        local u = Unit.getByName(T.currentTargetName)
        if u and Object.isExist(u) and u:getLife() > 0 then return u end
    end
    for _, gname in ipairs(T.groundGroups) do
        local g = Group.getByName(gname)
        if g and Group.isExist(g) then
            for _, u in ipairs(g:getUnits() or {}) do
                if u and Object.isExist(u) and u:getLife() > 0 then
                    T.currentTargetName = u:getName()
                    return u
                end
            end
        end
    end
    T.currentTargetName = nil
    return nil
end

local function ensureLaser()
    if not T.laserEnabled or not T.jtacUnit or not Object.isExist(T.jtacUnit) or T.jtacUnit:getLife() <= 0 then return end
    local target = findAliveGroundTarget()
    if not target then stopLaser() return end
    local p = target:getPoint(); p = {x = p.x, y = p.y + 2, z = p.z}
    if not T.laser then
        local ok, ray = pcall(function() return Spot.createLaser(T.jtacUnit, {x = 0, y = 2, z = 0}, p, T.laserCode) end)
        if ok then T.laser = ray end
    else
        pcall(function() T.laser:setPoint(p) end)
    end
end

local function laserLoop(_, time)
    ensureLaser()
    return time + 0.5
end

local function spawnJTAC(zone, usedPositions)
    local jx, jz = findPointInsideGroundZone(zone, usedPositions or {}, 30, 80, 260)
    if not jx then
        msg("JTAC could not find a valid position inside the selected SPAWN ZONE GROUND.", 15)
        return nil
    end
    local gname = nextName("M29_JTAC")
    local uname = gname .. "_1"
    local data = {
        visible = false, hidden = true, task = "Ground Nothing", taskSelected = true,
        route = {points = {[1] = {x = jx, y = jz, alt = groundHeight(jx,jz), alt_type = "BARO", speed = 0,
            action = "Off Road", type = "Turning Point", ETA = 0, ETA_locked = true, speed_locked = true,
            formation_template = "", task = {id = "ComboTask", params = {tasks = {}}}}}},
        units = {[1] = {type = "JTAC", name = uname, x = jx, y = jz, heading = 0, skill = "Excellent", playerCanDrive = false}},
        name = gname, start_time = 0
    }
    local g = coalition.addGroup(BLUE_COUNTRY, Group.Category.GROUND, data)
    if g then
        T.jtacGroup = gname
        timer.scheduleFunction(function()
            local u = Unit.getByName(uname)
            if u and Object.isExist(u) then
                T.jtacUnit = u
                local ctrl = u:getController()
                if ctrl then
                    pcall(function() ctrl:setCommand({id = "SetInvisible", params = {value = true}}) end)
                    pcall(function() ctrl:setCommand({id = "SetImmortal", params = {value = true}}) end)
                end
                ensureLaser()
            end
            return nil
        end, {}, timer.getTime() + 1)
    end
end

local function nextLaserTarget()
    local currentSeen, firstUnit, nextUnit = false, nil, nil
    for _, gname in ipairs(T.groundGroups) do
        local g = Group.getByName(gname)
        if g and Group.isExist(g) then
            for _, u in ipairs(g:getUnits() or {}) do
                if u and Object.isExist(u) and u:getLife() > 0 then
                    firstUnit = firstUnit or u
                    if currentSeen and not nextUnit then nextUnit = u end
                    if u:getName() == T.currentTargetName then currentSeen = true end
                end
            end
        end
    end
    nextUnit = nextUnit or firstUnit
    stopLaser()
    if nextUnit then
        T.currentTargetName = nextUnit:getName(); T.laserEnabled = true; ensureLaser()
        msg(string.format("JTAC target: %s | CODE %d | MGRS %s", nextUnit:getTypeName(), T.laserCode, mgrsText(nextUnit:getPoint())), 18)
    else msg("JTAC: no live ground target.") end
end

local function jtacStatus()
    local target = findAliveGroundTarget()
    if target then msg(string.format("JTAC ACTIVE | %s | CODE %d | MGRS %s", target:getTypeName(), T.laserCode, mgrsText(target:getPoint())), 18)
    else msg("JTAC: no live ground target.") end
end

local GROUND_POOLS = {
    soft = {"Ural-375", "Ural-375", "Ural-375", "BTR-80"},
    mech = {"BTR-80", "BMP-1", "BMP-1", "T-55"},
    armor = {"T-55", "T-55", "T-72B", "BMP-1"},
    aaa = {"Ural-375", "ZSU-23-4 Shilka", "ZSU-23-4 Shilka", "BTR-80"},
    sam = {"Ural-375", "Strela-10M3", "ZSU-23-4 Shilka", "BTR-80"},
    mixed = {"Ural-375", "BTR-80", "BMP-1", "T-55", "T-72B", "ZSU-23-4 Shilka", "Strela-10M3"}
}

local function spawnGroundGroup(pool, count, anchorKey, label, withJTAC, placementProfile)
    -- Campaign and FREE ground events now use ONLY the eight editor-created
    -- SPAWN ZONE GROUND trigger zones. One valid zone is selected at random.
    local zone = randomGroundSpawnZone()
    if not zone then
        msg("GROUND SPAWN ERROR: no SPAWN ZONE GROUND / -1...-7 trigger zones found.", 20)
        return nil
    end
    local centerX, centerZ = zoneXZ(zone)
    local gname = nextName("M29_GROUND")
    local units = {}
    local usedPositions = {}
    for i = 1, count do
        local ux, uz = findPointInsideGroundZone(zone, usedPositions, 35, 70, 260)
        if not ux then
            msg(string.format("GROUND SPAWN ERROR: %s has insufficient clear space for %d units. No units spawned outside the zone.", zone._trainingName or "selected zone", count), 20)
            return nil
        end
        usedPositions[#usedPositions + 1] = {x = ux, z = uz}
        units[i] = {type = pool[((i - 1) % #pool) + 1], name = gname .. "_" .. i,
            x = ux, y = uz, heading = rand(0, 2 * math.pi), skill = "Average", playerCanDrive = true}
    end
    local data = {
        visible = false, hidden = false, task = "Ground Nothing", taskSelected = true,
        route = {points = {[1] = {x = centerX, y = centerZ, alt = groundHeight(centerX,centerZ), alt_type = "BARO",
            speed = 0, action = "Off Road", type = "Turning Point", ETA = 0, ETA_locked = true,
            speed_locked = true, formation_template = "", task = {id = "ComboTask", params = {tasks = {}}}}}},
        units = units, name = gname, start_time = 0
    }
    local g = coalition.addGroup(RED_COUNTRY, Group.Category.GROUND, data)
    if not g then msg("Error spawning ground group: " .. label) return nil end
    table.insert(T.groundGroups, gname)
    T.lastGroundZone = zone._trainingName
    if withJTAC then
        if T.jtacGroup then safeDestroyGroup(T.jtacGroup) end
        stopLaser(); spawnJTAC(zone, usedPositions); T.laserEnabled = true
    end
    msg(string.format("GROUND: %s | %d units | RANDOM ZONE: %s | MGRS %s%s", label, count, zone._trainingName or "SPAWN ZONE GROUND",
        mgrsText({x=centerX,y=groundHeight(centerX,centerZ),z=centerZ}), withJTAC and " | JTAC 1688" or ""), 20)
    return gname
end

local AIR_R73 = "{FBC29BFE-3D24-4C64-B81D-941239D12249}"
local AIR_R27R = "{9B25D316-0434-4954-868F-D51DB1A38DF0}"
local AIR_R24R = "{CCF898C9-5BC7-49A4-9D1E-C3ED3D5166A1}"
local AIR_R24T = "{6980735A-44CC-4BB9-A1B5-591532F1DC69}"
local AIR_R40RD = "{4EDBA993-2E34-444C-95FB-549300BF7CAF}"
local AIR_R40TD = "{5F26DBC2-FB43-4153-92DE-6BBCE26CB0FF}"
local AIR_R60M_SINGLE = "{APU-60-1_R_60M}"
local AIR_R60M_DOUBLE_L = "{B0DBC591-0F52-4F7D-AD7B-51E67725FB81}"
local AIR_R60M_DOUBLE_R = "{275A2855-4A79-4B2D-B082-91EA2ADF4691}"

local function airPayload(acType, profile)
    if acType == "MiG-21Bis" and profile == "visual" then
        return {pylons = {[2]={CLSID="{R-60M}"}, [4]={CLSID="{R-60M}"}}, fuel=2280, flare=40, chaff=18, gun=100}
    elseif acType == "MiG-21Bis" then
        return {pylons = {[1]={CLSID="{R-3R}"}, [2]={CLSID="{R-60M}"}, [4]={CLSID="{R-60M}"}, [5]={CLSID="{R-3R}"}}, fuel=2280, flare=40, chaff=18, gun=100}
    elseif acType == "MiG-23MLD" then
        return {pylons = {[2]={CLSID=AIR_R24R}, [3]={CLSID=AIR_R60M_DOUBLE_L}, [5]={CLSID=AIR_R60M_DOUBLE_R}, [6]={CLSID=AIR_R24T}}, fuel=3800, flare=60, chaff=60, gun=100}
    elseif acType == "MiG-25PD" then
        return {pylons = {[1]={CLSID=AIR_R60M_SINGLE}, [2]={CLSID=AIR_R40RD}, [3]={CLSID=AIR_R40TD}, [4]={CLSID=AIR_R60M_SINGLE}}, fuel=15245, flare=64, chaff=64, gun=100}
    elseif acType == "MiG-29A" then
        return {pylons = {[1]={CLSID=AIR_R73}, [2]={CLSID=AIR_R73}, [3]={CLSID=AIR_R27R}, [5]={CLSID=AIR_R27R}, [6]={CLSID=AIR_R73}, [7]={CLSID=AIR_R73}}, fuel=3376, flare=30, chaff=30, gun=100}
    end
    return {pylons = {}, fuel=3000, flare=20, chaff=20, gun=100}
end

local function airSpeed(acType)
    if acType == "MiG-21Bis" then return 230 end
    if acType == "MiG-23MLD" then return 255 end
    if acType == "MiG-25PD" then return 285 end
    return 250
end

-- Mission 01 visual-BFM merge protection.
-- The bandit approaches with weapons HOLD, crosses the neutral merge, then becomes HOT
-- only after range has opened again. This prevents an AI heater/gun shot at the merge.
local VISUAL_MERGE_ENTRY = 1.20 * NM
local VISUAL_MERGE_EXIT  = 1.50 * NM

local function visualBanditArmAfterMerge(gname)
    local state = {mergeSeen=false}
    return function(_, time)
        local sg = Group.getByName(gname)
        if not (sg and Group.isExist(sg)) then return nil end
        local units = sg:getUnits() or {}
        local bandit = units[1]
        if not (bandit and Object.isExist(bandit) and bandit:getLife() > 0) then return nil end

        local bp = bandit:getPoint()
        local nearest = nil
        for _, pu in ipairs(coalition.getPlayers(BLUE) or {}) do
            if pu and Object.isExist(pu) and pu:getLife() > 0 then
                local pp = pu:getPoint()
                local dx, dy, dz = bp.x-pp.x, bp.y-pp.y, bp.z-pp.z
                local d = math.sqrt(dx*dx + dy*dy + dz*dz)
                if not nearest or d < nearest then nearest = d end
            end
        end

        if nearest then
            if not state.mergeSeen and nearest <= VISUAL_MERGE_ENTRY then
                state.mergeSeen = true
            elseif state.mergeSeen and nearest >= VISUAL_MERGE_EXIT then
                local ctrl = sg:getController()
                if ctrl then
                    pcall(function() ctrl:setOption(AI.Option.Air.id.ROE, AI.Option.Air.val.ROE.WEAPON_FREE) end)
                end
                msg("MERGE COMPLETE - BANDIT HOT / WEAPONS FREE", 8)
                return nil
            end
        end
        return time + 0.25
    end
end

local function spawnOneAir(acType, skill, sx, sz, alt, heading, targetPoint, playerGroupId, index, payloadProfile)
    local gname = nextName("M29_AIR")
    local speed = airSpeed(acType)
    local data = {
        visible=false, hidden=false, task="CAP", taskSelected=true,
        route={points={
            [1]={x=sx,y=sz,alt=alt,alt_type="BARO",speed=speed,action="Turning Point",type="Turning Point",ETA=0,ETA_locked=true,speed_locked=true,formation_template="",task={id="ComboTask",params={tasks={}}}},
            [2]={x=targetPoint.x,y=targetPoint.z,alt=alt,alt_type="BARO",speed=speed,action="Turning Point",type="Turning Point",ETA_locked=false,speed_locked=true,formation_template="",task={id="ComboTask",params={tasks={}}}}
        }},
        units={[1]={type=acType,name=gname.."_1",x=sx,y=sz,alt=alt,alt_type="BARO",speed=speed,heading=heading,skill=skill,payload=airPayload(acType, payloadProfile),callsign=((index-1)%8)+1,onboard_num=string.format("%03d",40+index)}},
        name=gname,communication=true,frequency=124,modulation=0,start_time=0
    }
    local g = coalition.addGroup(RED_COUNTRY, Group.Category.AIRPLANE, data)
    if not g then return nil end
    table.insert(T.airGroups, gname)
    timer.scheduleFunction(function()
        local sg = Group.getByName(gname)
        if sg and Group.isExist(sg) then
            local ctrl = sg:getController()
            if ctrl then
                if payloadProfile == "visual" then
                    pcall(function() ctrl:setOption(AI.Option.Air.id.ROE, AI.Option.Air.val.ROE.WEAPON_HOLD) end)
                    timer.scheduleFunction(visualBanditArmAfterMerge(gname), {}, timer.getTime()+0.25)
                else
                    pcall(function() ctrl:setOption(AI.Option.Air.id.ROE, AI.Option.Air.val.ROE.WEAPON_FREE) end)
                end
                pcall(function() ctrl:setOption(AI.Option.Air.id.REACTION_ON_THREAT, AI.Option.Air.val.REACTION_ON_THREAT.EVADE_FIRE) end)
                if playerGroupId then pcall(function() ctrl:pushTask({id="EngageGroup",params={groupId=playerGroupId,priority=1}}) end) end
            end
        end
        return nil
    end, {}, timer.getTime()+1)
    return gname
end

local function spawnAirFormation(types, skill, rangeNm, altitudeFt, requestingGroupName, label, payloadProfile)
    local player = getPlayerFromGroup(requestingGroupName)
    local pp, ph
    if player then
        pp = player:getPoint()
        local v = player:getVelocity(); local gs = math.sqrt(v.x*v.x + v.z*v.z)
        if gs > 50 then ph = atan2(v.z, v.x) else ph = atan2(T.targetArea.z-pp.z, T.targetArea.x-pp.x) end
    else
        pp = T.defaultPlayerPoint; ph = atan2(T.targetArea.z-pp.z, T.targetArea.x-pp.x)
    end
    local dist = rangeNm * NM
    local fx, fz = math.cos(ph), math.sin(ph)
    local rx, rz = -fz, fx
    local baseX = pp.x + fx*dist
    local baseZ = pp.z + fz*dist
    local baseAlt = altitudeFt / 3.28084
    local heading = atan2(pp.z-baseZ, pp.x-baseX)
    local playerGroupId = player and player:getGroup() and player:getGroup():getID() or nil
    local spawned, names = {}, {}
    for i, acType in ipairs(types) do
        local spread = (i - ((#types+1)/2))*650
        local trail = ((i-1)%2)*500
        local sx, sz = baseX + rx*spread - fx*trail, baseZ + rz*spread - fz*trail
        local gname = spawnOneAir(acType, skill, sx, sz, baseAlt + ((i-1)%3)*160, heading, pp, playerGroupId, i, payloadProfile)
        if gname then table.insert(spawned,gname); table.insert(names,acType) end
    end
    if #spawned > 0 then msg(string.format("AIR: %s | %s | %d NM | %d ft", label or "training contacts", table.concat(names, ", "), rangeNm, altitudeFt), 20)
    else msg("Error spawning air training contacts.") end
    return spawned
end

local SCENARIOS = {
    [1] = {title="VISUAL FIGHTER ENGAGEMENT", brief="MiG-21bis opposition scales 1:1 with active BLUE pilots, maximum four. Opponents carry R-60M only and remain WEAPONS HOLD through the first neutral merge. The trainee must also wait until the first pass. Practise N019 close-combat modes, IRST, HMS/R-73 and the GSh-30-1. For a comparable visual exercise, rearm with R-73 only before departure. Manage energy and fuel, then recover at Kobuleti.", air={"MiG-21Bis"}, skill="Average", range=35, alt=12000, payloadProfile="visual"},
    [2] = {title="AIR DEFENCE INTERCEPT", brief="Intercept MiG-21bis contacts, one per active BLUE pilot, maximum four. Practise N019 search and acquisition, radar/IRST correlation and positive identification before weapon release. Reference weapons: R-27R and R-73. No dedicated GCI system is added by this campaign: use the exercise messages and available simulated contact information.", air={"MiG-21Bis","MiG-21Bis"}, skill="Good", range=42, alt=18000},
    [3] = {title="BVR INTERCEPT", brief="Intercept MiG-23MLD armed with R-24R/R-24T/R-60M, one per active BLUE pilot, maximum four. Practise N019 acquisition and R-27R employment while maintaining the radar support required by the semi-active missile. Manage the transition to IRST/HMS and R-73 if needed. No R-77, R-27ER or R-27ET is included in this training programme.", air={"MiG-23MLD","MiG-23MLD"}, skill="Good", range=48, alt=22000},
    [4] = {title="HIGH-ALTITUDE INTERCEPT", brief="Intercept high-altitude MiG-25PD/MiG-21bis contacts. Opposition scales 1:1, maximum four; a solo pilot faces one MiG-25PD. Practise radar elevation control, intercept geometry, energy and endurance. The published altitude is the initial contact spawn altitude, not a mandatory trainee flight profile.", air={"MiG-25PD","MiG-21Bis"}, skill="Good", range=55, alt=30000},
    [5] = {title="LOGISTICS CONVOY STRIKE", brief="Attack a seven-vehicle logistics group in the assigned range area. Rearm on the ground with module-compatible FAB/OFAB bombs or S-8 rockets. The MiG-29A uses unguided air-to-ground weapons: no laser-guided ordnance or targeting pod is provided. The ground observer supplies coordinates for visual acquisition. Destroy all assigned targets and recover.", groundPool="soft", groundCount=7, anchor="west", jtac=true},
    [6] = {title="ARMOURED INTERDICTION", brief="Interdict a seven-vehicle armoured/mechanised group including ZSU-23-4 protection. Prepare an appropriate unguided air-to-ground loadout before departure. Assess the anti-aircraft threat and limit exposure over the target area. Use SPO-15LM as an awareness aid together with visual search: silence on the RWR does not rule out an infrared threat. The observer provides target coordinates.", groundPool="armor", groundCount=7, extraAAA=true, anchor="east", jtac=true},
    [7] = {title="SHORT-RANGE AIR DEFENCE ATTACK", brief="Conduct a conventional training attack against a six-vehicle SHORAD position containing Strela-10M3 and ZSU-23-4. No anti-radiation missiles or laser-guided weapons are available in this campaign loadout concept. This is not an ARM-equipped SEAD exercise. Assess the visual/IR threat, countermeasures and disengagement, then recover at Kobuleti.", groundPool="sam", groundCount=6, anchor="north", jtac=true},
    [8] = {title="COMBINED ARMS EXERCISE", brief="A seven-vehicle mechanised group including AAA is covered by MiG-23MLD. Fighter opposition scales 1:1, maximum four; ground strength remains fixed. Prepare a compatible mixed loadout before departure, for example R-73 and FAB/OFAB bombs. Manage task priorities, multiplayer roles and fuel. If required, recover and rearm before completing the remaining objectives.", air={"MiG-23MLD","MiG-23MLD"}, skill="Good", range=50, alt=20000, groundPool="mech", groundCount=7, extraAAA=true, anchor="south", jtac=true},
    [9] = {title="FINAL OPERATIONAL EVALUATION", brief="Final combined exercise against a nine-vehicle mixed group with AAA/SAM and fighter opposition. One fighter per active BLUE pilot, maximum four: MiG-21bis, then MiG-23MLD, MiG-25PD and MiG-29A as player count increases. Plan weapons and any required ground rearming. Destroy all air and ground objectives and recover. Automatic credit measures target destruction; recovery and airmanship remain trainee-assessed.", air={"MiG-21Bis","MiG-23MLD","MiG-25PD","MiG-29A"}, skill="Excellent", range=58, alt=24000, groundPool="mixed", groundCount=9, anchor="north", jtac=true}
}

local function scenarioObjectiveAlive()
    if not T.activeScenario then return 0 end
    local alive = 0
    for _, name in ipairs(T.activeScenario.objectiveGroups or {}) do
        local g = Group.getByName(name)
        if g and Group.isExist(g) then
            for _, u in ipairs(g:getUnits() or {}) do
                if u and Object.isExist(u) and u:getLife() > 0 then alive = alive + 1 end
            end
        end
    end
    return alive
end

local function showActiveBrief()
    if not T.activeScenario then msg("No campaign mission is active. Select a mission from F10 > MiG-29A TRAINING CAMPAIGN > CAMPAIGN MISSIONS.") return end
    local s = SCENARIOS[T.activeScenario.id]
    msg(string.format("MISSION %02d - %s\n%s\nOBJECTIVES REMAINING: %d%s", T.activeScenario.id, s.title, s.brief, scenarioObjectiveAlive(), T.activeScenario.spawnFailed and "\nINCOMPLETE SPAWN: restart this exercise. Completion credit is suspended." or ""), 30)
end

local function startScenario(id, requestingGroupName)
    local s = SCENARIOS[id]
    if not s then return end
    clearRange(true)
    local participants = {}
    for _, playerName in ipairs(activePlayerNames()) do participants[playerName] = true end
    local requesterName = playerNameFromGroup(requestingGroupName)
    if requesterName then participants[requesterName] = true end
    T.activeScenario = {id=id, objectiveGroups={}, started=timer.getTime(), announced=false, spawnFailed=false, participants=participants}
    msg(string.format("MISSION %02d - %s\n%s\nRearm at Kobuleti BEFORE selecting an exercise. Start when ready airborne; contacts spawn immediately. Recover afterwards. No air-to-air refuelling.", id, s.title, s.brief), 30)

    if s.groundPool then
        local pool = {}
        for _, t in ipairs(GROUND_POOLS[s.groundPool] or GROUND_POOLS.mixed) do table.insert(pool,t) end
        if s.extraAAA then table.insert(pool,"ZSU-23-4 Shilka") end
        local gname = spawnGroundGroup(pool, s.groundCount or #pool, s.anchor or "north", s.title, s.jtac)
        if gname then table.insert(T.activeScenario.objectiveGroups,gname) else T.activeScenario.spawnFailed=true end
    end
    if s.air then
        local airTypes, playerCount = scaledAirTypes(s.air)
        local groups = spawnAirFormation(airTypes, s.skill or "Good", s.range or 45, s.alt or 18000, requestingGroupName, s.title, s.payloadProfile)
        for _, gname in ipairs(groups) do table.insert(T.activeScenario.objectiveGroups,gname) end
        if #groups ~= #airTypes then T.activeScenario.spawnFailed=true end
        msg(string.format("DYNAMIC AIR THREAT: %d BANDIT%s | %d ACTIVE PLAYER%s | 1:1 SCALE (MAX 4)", #airTypes, #airTypes == 1 and "" or "S", playerCount, playerCount == 1 and "" or "S"), 20)
    end
end

local function scenarioLoop(_, time)
    if T.activeScenario and not T.activeScenario.announced and not T.activeScenario.spawnFailed then
        if #T.activeScenario.objectiveGroups > 0 and scenarioObjectiveAlive() == 0 then
            local id = T.activeScenario.id
            T.completed[id] = true
            T.activeScenario.announced = true
            local credited = {}
            for playerName in pairs(T.activeScenario.participants or {}) do credited[playerName] = true end
            for _, playerName in ipairs(activePlayerNames()) do credited[playerName] = true end
            local newlyCompleted = 0
            for playerName in pairs(credited) do
                if missionCompletionForPlayer(playerName, id) then newlyCompleted = newlyCompleted + 1 end
            end
            msg(string.format("MISSION %02d COMPLETE. +100 TRAINING POINTS for first completion. Player records updated%s. Recover at Kobuleti and select the next mission when ready.",
                id, T.persistenceAvailable and " and saved to disk" or " for this session"), 25)
        end
    end
    return time + 4
end

local function campaignStatus(requestingGroupName)
    local playerName = playerNameFromGroup(requestingGroupName)
    if playerName then
        local active = T.activeScenario and string.format("%02d %s (%d objectives alive)", T.activeScenario.id, SCENARIOS[T.activeScenario.id].title, scenarioObjectiveAlive()) or "none"
        msg(progressText(playerName) .. "\nACTIVE: " .. active, 30)
    else
        msg("Player record unavailable for this group.", 15)
    end
end

local function nextScenarioId(requestingGroupName)
    local playerName = playerNameFromGroup(requestingGroupName)
    local r = playerName and ensurePlayerRecord(playerName) or nil
    if r then
        for i = 1, #SCENARIOS do if not r.missions[i] then return i end end
    end
    return 1
end

local function showPlayerProgress(requestingGroupName)
    local playerName = playerNameFromGroup(requestingGroupName)
    if playerName then msg(progressText(playerName), 30) else msg("Player record unavailable for this group.", 15) end
end

local function freeAir(mode, count, requestingGroupName)
    clearAir(true); T.activeScenario=nil
    local pools = {
        random={"MiG-21Bis","MiG-23MLD","MiG-25PD","MiG-29A"},
        mig21={"MiG-21Bis"}, mig23={"MiG-23MLD"}, mig25={"MiG-25PD"}, mig29={"MiG-29A"}
    }
    local pool=pools[mode] or pools.random
    local types={}
    for i=1,count do types[i]=pick(pool) end
    spawnAirFormation(types, count>=4 and "Excellent" or "Good", count>=4 and 52 or 42, count>=4 and 24000 or 18000, requestingGroupName, "FREE TRAINING")
end

local function freeGround(kind)
    clearGround(true); T.activeScenario=nil
    local cfg = {
        soft={pool="soft",count=7,label="Logistics convoy"},
        mech={pool="mech",count=7,label="Mechanized group"},
        armor={pool="armor",count=7,label="Armored group"},
        aaa={pool="aaa",count=6,label="AAA position"},
        sam={pool="sam",count=6,label="Short-range SAM/AAA position"},
        mixed={pool="mixed",count=9,label="Mixed Cold War battlegroup"}
    }
    local c=cfg[kind] or cfg.mixed
    spawnGroundGroup(GROUND_POOLS[c.pool],c.count,"north",c.label,true,"free")
end

local function buildMenuForPlayerUnit(u)
    if not u or not Object.isExist(u) or u:getLife()<=0 then return end
    local g=u:getGroup(); if not g or not Group.isExist(g) then return end
    local gname,gid=g:getName(),g:getID(); if not gname or not gid or T.menuGroups[gname] then return end
    local playerName = u:getPlayerName()
    if playerName and playerName ~= "" then
        ensurePlayerRecord(playerName)
        saveProgress()
    end

    local root=missionCommands.addSubMenuForGroup(gid,"MiG-29A TRAINING CAMPAIGN")
    local camp=missionCommands.addSubMenuForGroup(gid,"CAMPAIGN MISSIONS",root)
    local airCamp=missionCommands.addSubMenuForGroup(gid,"PHASE 1 - AIR DEFENCE",camp)
    for i=1,4 do local id=i; missionCommands.addCommandForGroup(gid,string.format("%02d - %s",id,SCENARIOS[id].title),airCamp,function() startScenario(id,gname) end) end
    local strikeCamp=missionCommands.addSubMenuForGroup(gid,"PHASE 2 - CONVENTIONAL ATTACK",camp)
    for i=5,7 do local id=i; missionCommands.addCommandForGroup(gid,string.format("%02d - %s",id,SCENARIOS[id].title),strikeCamp,function() startScenario(id,gname) end) end
    local advCamp=missionCommands.addSubMenuForGroup(gid,"PHASE 3 - OPERATIONAL EVALUATION",camp)
    for i=8,9 do local id=i; missionCommands.addCommandForGroup(gid,string.format("%02d - %s",id,SCENARIOS[id].title),advCamp,function() startScenario(id,gname) end) end
    missionCommands.addCommandForGroup(gid,"START NEXT IN SEQUENCE",camp,function() startScenario(nextScenarioId(gname),gname) end)

    local freeAirMenu=missionCommands.addSubMenuForGroup(gid,"FREE TRAINING - AIR",root)
    missionCommands.addCommandForGroup(gid,"Random Cold War - 1",freeAirMenu,function() freeAir("random",1,gname) end)
    missionCommands.addCommandForGroup(gid,"Random Cold War - pair",freeAirMenu,function() freeAir("random",2,gname) end)
    missionCommands.addCommandForGroup(gid,"Random Cold War - 4 ship",freeAirMenu,function() freeAir("random",4,gname) end)
    local byType=missionCommands.addSubMenuForGroup(gid,"BY TYPE",freeAirMenu)
    missionCommands.addCommandForGroup(gid,"MiG-21Bis pair",byType,function() freeAir("mig21",2,gname) end)
    missionCommands.addCommandForGroup(gid,"MiG-23MLD pair",byType,function() freeAir("mig23",2,gname) end)
    missionCommands.addCommandForGroup(gid,"MiG-25PD single",byType,function() freeAir("mig25",1,gname) end)
    missionCommands.addCommandForGroup(gid,"MiG-29A pair - Late CW",byType,function() freeAir("mig29",2,gname) end)
    missionCommands.addCommandForGroup(gid,"REMOVE AIR",freeAirMenu,function() clearAir(false) end)

    local freeGroundMenu=missionCommands.addSubMenuForGroup(gid,"FREE TRAINING - GROUND",root)
    missionCommands.addCommandForGroup(gid,"Logistics convoy",freeGroundMenu,function() freeGround("soft") end)
    missionCommands.addCommandForGroup(gid,"Mechanized group",freeGroundMenu,function() freeGround("mech") end)
    missionCommands.addCommandForGroup(gid,"Armored group",freeGroundMenu,function() freeGround("armor") end)
    missionCommands.addCommandForGroup(gid,"AAA position",freeGroundMenu,function() freeGround("aaa") end)
    missionCommands.addCommandForGroup(gid,"Short-range SAM + AAA",freeGroundMenu,function() freeGround("sam") end)
    missionCommands.addCommandForGroup(gid,"Mixed battlegroup",freeGroundMenu,function() freeGround("mixed") end)
    missionCommands.addCommandForGroup(gid,"REMOVE GROUND",freeGroundMenu,function() clearGround(false) end)

    local support=missionCommands.addSubMenuForGroup(gid,"GROUND OBSERVER",root)
    missionCommands.addCommandForGroup(gid,"Target coordinates (no laser guidance)",support,jtacStatus)
    missionCommands.addCommandForGroup(gid,"Select next observer target",support,nextLaserTarget)

    missionCommands.addCommandForGroup(gid,"ACTIVE MISSION BRIEF",root,showActiveBrief)
    missionCommands.addCommandForGroup(gid,"CAMPAIGN STATUS",root,function() campaignStatus(gname) end)
    missionCommands.addCommandForGroup(gid,"MY TRAINING RECORD",root,function() showPlayerProgress(gname) end)
    missionCommands.addCommandForGroup(gid,"RESET TRAINING RANGE",root,function() clearRange(false) end)
    T.menuGroups[gname]=true
end

local function menuScan(_,time)
    for _,u in ipairs(coalition.getPlayers(BLUE) or {}) do pcall(buildMenuForPlayerUnit,u) end
    return time+3
end

-- Persistent scoring event: +25 per aircraft/helicopter kill, +10 per ground kill.
local ProgressEventHandler = {}
function ProgressEventHandler:onEvent(event)
    if not event or not world or not world.event or event.id ~= world.event.S_EVENT_KILL then return end
    local initiator, target = event.initiator, event.target
    if not initiator or not target then return end
    local playerName = nil
    pcall(function() playerName = initiator:getPlayerName() end)
    if playerName and playerName ~= "" then addKillScore(playerName, target) end
end
world.addEventHandler(ProgressEventHandler)

loadProgress()

-- Remove obsolete editor/template player groups. The dedicated MiG-29A Fulcrum FF slot remains at Kobuleti HOT.
safeDestroyGroup("TRAINING_KOBULETI")
safeDestroyGroup("TRAINING_KOBULETI-1")
safeDestroyGroup("Ground-1")
safeDestroyGroup("Ground-2")

timer.scheduleFunction(menuScan,{},timer.getTime()+0.5)
timer.scheduleFunction(laserLoop,{},timer.getTime()+1)
timer.scheduleFunction(scenarioLoop,{},timer.getTime()+4)
msg("Training campaign ready. Ground targets (Campaign + FREE) use random SPAWN ZONE GROUND locations only. Per-player score/mission progress: " .. (T.persistenceAvailable and "DISK SAVE ACTIVE." or "SESSION ONLY - progress lasts until the mission session closes.") .. " Use F10 > MiG-29A TRAINING CAMPAIGN.",25)
