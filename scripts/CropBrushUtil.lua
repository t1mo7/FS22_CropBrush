-- CropBrushUtil: field lookup and the actual density map changes (runs on the server)

CropBrushUtil = {}

-- fruitTypeIndex 0 means "remove crop"
CropBrushUtil.CLEAR_FRUIT = 0

function CropBrushUtil.log(fmt, ...)
    print(string.format("[CropBrush] " .. fmt, ...))
end

----------------------------------------------------------------------
-- Fruit types / growth states
----------------------------------------------------------------------

function CropBrushUtil.getPlantableFruitTypes()
    local result = {}
    for _, fruitType in ipairs(g_fruitTypeManager:getFruitTypes()) do
        if fruitType.allowsSeeding and fruitType.numGrowthStates ~= nil and fruitType.numGrowthStates > 0 then
            table.insert(result, fruitType)
        end
    end
    return result
end

-- Crop names are always shown in English, whatever language the game runs in.
CropBrushUtil.FRUIT_TITLES = {
    WHEAT = "Wheat", BARLEY = "Barley", OAT = "Oat", CANOLA = "Canola", SORGHUM = "Sorghum",
    SUNFLOWER = "Sunflower", SOYBEAN = "Soybean", MAIZE = "Corn", POTATO = "Potato",
    SUGARBEET = "Sugar beet", SUGARCANE = "Sugarcane", COTTON = "Cotton", GRASS = "Grass",
    OILSEEDRADISH = "Oilseed radish", POPLAR = "Poplar", OLIVE = "Olive", GRAPE = "Grape",
    MEADOW = "Meadow"
}

function CropBrushUtil.getFruitTitle(fruitType)
    local name = fruitType.name or "?"
    local title = CropBrushUtil.FRUIT_TITLES[name:upper()]
    if title ~= nil then
        return title
    end
    -- modded crops: "MY_CROP" -> "My crop"
    title = name:lower():gsub("_", " ")
    return (title:gsub("^%l", string.upper))
end

function CropBrushUtil.getFruitIcon(fruitType)
    local fillType = g_fruitTypeManager:getFillTypeByFruitTypeIndex(fruitType.index)
    if fillType ~= nil then
        return fillType.hudOverlayFilename
    end
    return nil
end

-- Returns a list of {state = n, text = "..."} for the given fruit type
function CropBrushUtil.getGrowthStateOptions(fruitType)
    local options = {}
    local minHarvest = fruitType.minHarvestingGrowthState or fruitType.numGrowthStates
    local maxHarvest = fruitType.maxHarvestingGrowthState or minHarvest

    for state = 1, maxHarvest do
        local text
        if state == 1 then
            text = "Seeded (stage 1)"
        elseif state < minHarvest then
            text = string.format("Growing (stage %d)", state)
        else
            text = string.format("Ready to harvest (stage %d)", state)
        end
        table.insert(options, {state = state, text = text})
    end

    if fruitType.witheredState ~= nil and fruitType.witheredState > maxHarvest then
        table.insert(options, {state = fruitType.witheredState, text = "Withered"})
    end
    if fruitType.cutState ~= nil and fruitType.cutState > 0 then
        table.insert(options, {state = fruitType.cutState, text = "Harvested (stubble)"})
    end
    return options
end

function CropBrushUtil.getDefaultGrowthState(fruitType)
    return fruitType.minHarvestingGrowthState or 1
end

----------------------------------------------------------------------
-- Fields
----------------------------------------------------------------------

function CropBrushUtil.getFields()
    if g_fieldManager.getFields ~= nil then
        return g_fieldManager:getFields()
    end
    return g_fieldManager.fields or {}
end

-- Parallelograms {x0,z0,x1,z1,x2,z2} (start, width, height points) of a field
function CropBrushUtil.getFieldAreas(field)
    local areas = {}
    local dimensions = field.fieldDimensions
    if dimensions ~= nil and dimensions ~= 0 then
        for i = 0, getNumOfChildren(dimensions) - 1 do
            local dimWidth = getChildAt(dimensions, i)
            local dimStart = getChildAt(dimWidth, 0)
            local dimHeight = getChildAt(dimWidth, 1)
            local x0, _, z0 = getWorldTranslation(dimStart)
            local x1, _, z1 = getWorldTranslation(dimWidth)
            local x2, _, z2 = getWorldTranslation(dimHeight)
            table.insert(areas, {x0 = x0, z0 = z0, x1 = x1, z1 = z1, x2 = x2, z2 = z2})
        end
    end
    return areas
end

local function isPointInArea(area, px, pz)
    local ux, uz = area.x1 - area.x0, area.z1 - area.z0
    local vx, vz = area.x2 - area.x0, area.z2 - area.z0
    local det = ux * vz - uz * vx
    if math.abs(det) < 0.0001 then
        return false
    end
    local dx, dz = px - area.x0, pz - area.z0
    local a = (dx * vz - dz * vx) / det
    local b = (ux * dz - uz * dx) / det
    return a >= 0 and a <= 1 and b >= 0 and b <= 1
end

function CropBrushUtil.getFieldAtPosition(x, z)
    for _, field in ipairs(CropBrushUtil.getFields()) do
        for _, area in ipairs(CropBrushUtil.getFieldAreas(field)) do
            if isPointInArea(area, x, z) then
                return field
            end
        end
    end
    return nil
end

function CropBrushUtil.getFieldById(fieldId)
    for _, field in ipairs(CropBrushUtil.getFields()) do
        if field.fieldId == fieldId then
            return field
        end
    end
    return nil
end

function CropBrushUtil.isOwnedAtPosition(x, z, farmId)
    local ownerId = g_farmlandManager:getOwnerIdAtWorldPosition(x, z)
    return ownerId ~= nil and ownerId == farmId
end

----------------------------------------------------------------------
-- Density map changes
----------------------------------------------------------------------

local fruitModifiers = {}

local function getFruitModifiers(fruitType)
    if g_fieldManager.getFruitModifier ~= nil then
        return g_fieldManager:getFruitModifier(fruitType)
    end
    -- Fallback: build our own modifier for the growth state channels
    if fruitModifiers[fruitType.index] == nil and fruitType.terrainDataPlaneId ~= nil then
        fruitModifiers[fruitType.index] = DensityMapModifier.new(fruitType.terrainDataPlaneId, fruitType.startStateChannel, fruitType.numStateChannels, g_currentMission.terrainRootNode)
    end
    return fruitModifiers[fruitType.index], nil
end

local fieldFilter = nil
local fieldFilterFailed = false

-- Filter that only lets changes through where there already is field ground
local function getFieldFilter()
    if fieldFilter == nil and not fieldFilterFailed then
        local ok, result = pcall(function()
            local filter = DensityMapFilter.new(g_fieldManager.groundTypeModifier)
            filter:setValueCompareParams(DensityValueCompareType.GREATER, 0)
            return filter
        end)
        if ok and result ~= nil then
            fieldFilter = result
        else
            fieldFilterFailed = true
            CropBrushUtil.log("Could not create field filter (%s), painting is not clipped to field edges", tostring(result))
        end
    end
    return fieldFilter
end

local function getGroundValue(name)
    local fgs = g_currentMission.fieldGroundSystem
    if FieldGroundType ~= nil and FieldGroundType[name] ~= nil and fgs.getFieldGroundValue ~= nil then
        return fgs:getFieldGroundValue(FieldGroundType[name])
    end
    if fgs.getFieldGroundValueByName ~= nil then
        return fgs:getFieldGroundValueByName(name)
    end
    return nil
end

local function setValue(modifier, value, area, filter)
    if modifier == nil or value == nil then
        return
    end
    modifier:setParallelogramWorldCoords(area.x0, area.z0, area.x1, area.z1, area.x2, area.z2, DensityCoordType.POINT_POINT_POINT)
    if filter ~= nil then
        modifier:executeSet(value, filter)
    else
        modifier:executeSet(value)
    end
end

-- Sets the crop on one parallelogram. fruitTypeIndex 0 = remove crop.
function CropBrushUtil.setFruitOnArea(area, fruitTypeIndex, growthState)
    local filter = getFieldFilter()

    -- remove every existing crop in the area
    for _, other in ipairs(g_fruitTypeManager:getFruitTypes()) do
        if other.terrainDataPlaneId ~= nil and other.index ~= fruitTypeIndex then
            local modifier, preparingModifier = getFruitModifiers(other)
            setValue(modifier, 0, area, filter)
            setValue(preparingModifier, 0, area, filter)
        end
    end

    if fruitTypeIndex == CropBrushUtil.CLEAR_FRUIT then
        setValue(g_fieldManager.groundTypeModifier, getGroundValue("CULTIVATED"), area, filter)
        return
    end

    local fruitType = g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex)
    if fruitType == nil then
        return
    end

    local groundValue = getGroundValue("SOWN")
    if fruitType.groundTypeChangeGrowthState ~= nil and fruitType.groundTypeChangeGrowthState >= 0
        and growthState >= fruitType.groundTypeChangeGrowthState and fruitType.groundTypeChangeType ~= nil then
        groundValue = g_currentMission.fieldGroundSystem:getFieldGroundValue(fruitType.groundTypeChangeType)
    end

    local isPrepared = (fruitType.preparedGrowthState ~= nil and growthState == fruitType.preparedGrowthState)
        or (fruitType.cutState ~= nil and growthState == fruitType.cutState)

    local modifier, preparingModifier = getFruitModifiers(fruitType)
    setValue(modifier, growthState, area, filter)
    setValue(preparingModifier, isPrepared and 1 or 0, area, filter)
    -- ground type last, because the filter checks the ground type
    setValue(g_fieldManager.groundTypeModifier, groundValue, area, filter)
end

-- Paints a circle around x,z by cutting it into horizontal strips
function CropBrushUtil.paintCircle(x, z, radius, fruitTypeIndex, growthState)
    local numStrips = math.max(1, math.min(24, math.ceil(radius * 2)))
    local stripHeight = (radius * 2) / numStrips
    for i = 0, numStrips - 1 do
        local z0 = z - radius + i * stripHeight
        local zMid = z0 + stripHeight * 0.5
        local dz = zMid - z
        local halfWidth = math.sqrt(math.max(0, radius * radius - dz * dz))
        if halfWidth > 0.05 then
            local area = {
                x0 = x - halfWidth, z0 = z0,
                x1 = x + halfWidth, z1 = z0,
                x2 = x - halfWidth, z2 = z0 + stripHeight
            }
            CropBrushUtil.setFruitOnArea(area, fruitTypeIndex, growthState)
        end
    end
end

function CropBrushUtil.paintField(field, fruitTypeIndex, growthState)
    for _, area in ipairs(CropBrushUtil.getFieldAreas(field)) do
        CropBrushUtil.setFruitOnArea(area, fruitTypeIndex, growthState)
    end
end

-- Entry point used by the brush (local) and by the event (on the server)
function CropBrushUtil.applyRequest(mode, fruitTypeIndex, growthState, x, z, radius, fieldId)
    local ok, err = pcall(function()
        if mode == CropBrushEvent.MODE_FIELD then
            local field = CropBrushUtil.getFieldById(fieldId)
            if field ~= nil then
                CropBrushUtil.paintField(field, fruitTypeIndex, growthState)
            end
        else
            CropBrushUtil.paintCircle(x, z, radius, fruitTypeIndex, growthState)
        end
    end)
    if not ok then
        CropBrushUtil.log("Error while painting: %s", tostring(err))
    end
end
