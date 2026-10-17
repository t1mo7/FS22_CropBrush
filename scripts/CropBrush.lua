-- CropBrush: construction screen brush that paints crops onto fields.
-- Added to Build menu -> Landscaping -> Paint (one brush per crop + "Remove crop").

CropBrush = {}
CropBrush.modDirectory = g_currentModDirectory
CropBrush.RADIUS_STEPS = {1, 2, 3, 5, 8, 12, 16, 25}
CropBrush.DEFAULT_RADIUS_INDEX = 4
CropBrush.PAINT_INTERVAL = 60 -- ms between paint strokes while dragging

-- remembered between brush switches
CropBrush.radiusIndex = CropBrush.DEFAULT_RADIUS_INDEX
CropBrush.growthStateByFruit = {}

local CropBrush_mt = Class(CropBrush, ConstructionBrush)

function CropBrush.new(customMt, cursor)
    local self = ConstructionBrush.new(customMt or CropBrush_mt, cursor)

    self.supportsPrimaryButton = true
    self.supportsPrimaryDragging = true
    self.supportsSecondaryButton = true
    self.supportsTertiaryButton = true
    self.supportsPrimaryAxis = true
    self.primaryAxisIsContinuous = false

    self.fruitTypeIndex = CropBrushUtil.CLEAR_FRUIT
    self.lastPaintTime = 0
    self.lastPaintX = nil
    self.lastPaintZ = nil

    return self
end

function CropBrush:setParameters(fruitTypeIndex)
    self.fruitTypeIndex = fruitTypeIndex or CropBrushUtil.CLEAR_FRUIT
    self.fruitType = g_fruitTypeManager:getFruitTypeByIndex(self.fruitTypeIndex)
end

function CropBrush:activate()
    if ConstructionBrush.activate ~= nil then
        ConstructionBrush.activate(self)
    end
    self.cursor:setShape(GuiTopDownCursor.SHAPES.CIRCLE)
    self.cursor:setShapeSize(self:getRadius())
end

function CropBrush:getRadius()
    return CropBrush.RADIUS_STEPS[CropBrush.radiusIndex]
end

function CropBrush:getGrowthState()
    if self.fruitType == nil then
        return 0
    end
    local state = CropBrush.growthStateByFruit[self.fruitTypeIndex]
    if state == nil then
        state = CropBrushUtil.getDefaultGrowthState(self.fruitType)
    end
    return state
end

function CropBrush:getGrowthStateText()
    if self.fruitType == nil then
        return ""
    end
    local state = self:getGrowthState()
    for _, option in ipairs(CropBrushUtil.getGrowthStateOptions(self.fruitType)) do
        if option.state == state then
            return option.text
        end
    end
    return string.format("stage %d", state)
end

function CropBrush:getCropTitle()
    if self.fruitType == nil then
        return "Remove crop"
    end
    return CropBrushUtil.getFruitTitle(self.fruitType)
end

function CropBrush:refreshInputTexts()
    if self.setInputTextDirty ~= nil then
        self:setInputTextDirty()
    end
end

----------------------------------------------------------------------
-- Update / checks
----------------------------------------------------------------------

function CropBrush:getErrorAt(x, z)
    if x == nil then
        return nil
    end
    if not CropBrushUtil.isOwnedAtPosition(x, z, g_currentMission:getFarmId()) then
        return "You don't own this land"
    end
    return nil
end

function CropBrush:update(dt)
    if ConstructionBrush.update ~= nil then
        ConstructionBrush.update(self, dt)
    end
    local x, _, z = self.cursor:getPosition()
    local err = self:getErrorAt(x, z)
    if err ~= nil then
        self.cursor:setErrorMessage(err)
    end
end

----------------------------------------------------------------------
-- Painting
----------------------------------------------------------------------

function CropBrush:paintAtCursor(force)
    local x, _, z = self.cursor:getPosition()
    if x == nil or self:getErrorAt(x, z) ~= nil then
        return
    end

    local radius = self:getRadius()
    if not force then
        if g_time - self.lastPaintTime < CropBrush.PAINT_INTERVAL then
            return
        end
        if self.lastPaintX ~= nil and MathUtil.vector2Length(x - self.lastPaintX, z - self.lastPaintZ) < radius * 0.35 then
            return
        end
    end

    self.lastPaintTime = g_time
    self.lastPaintX, self.lastPaintZ = x, z
    CropBrushEvent.sendRequest(CropBrushEvent.MODE_CIRCLE, self.fruitTypeIndex, self:getGrowthState(), x, z, radius, 0)
end

function CropBrush:onButtonPrimary(isDown, isDrag, isUp)
    if isDown and not isDrag then
        self:paintAtCursor(true)
    elseif isDrag then
        self:paintAtCursor(false)
    end
    if isUp then
        self.lastPaintX, self.lastPaintZ = nil, nil
    end
end

-- Secondary: choose growth stage
function CropBrush:onButtonSecondary()
    if self.fruitType == nil then
        return
    end

    local options = CropBrushUtil.getGrowthStateOptions(self.fruitType)
    local texts = {}
    for _, option in ipairs(options) do
        table.insert(texts, option.text)
    end

    local fruitTypeIndex = self.fruitTypeIndex
    g_gui:showOptionDialog({
        title = self:getCropTitle(),
        text = "Choose the growth stage to plant:",
        options = texts,
        callback = function(item)
            if type(item) == "number" and item > 0 and options[item] ~= nil then
                CropBrush.growthStateByFruit[fruitTypeIndex] = options[item].state
                self:refreshInputTexts()
            end
        end
    })
end

-- Tertiary: whole field under the cursor
function CropBrush:onButtonTertiary()
    local x, _, z = self.cursor:getPosition()
    if x == nil then
        return
    end

    local field = CropBrushUtil.getFieldAtPosition(x, z)
    if field == nil then
        self.cursor:setErrorMessage("No field here")
        return
    end

    local ownerId = field.farmland ~= nil and g_farmlandManager:getFarmlandOwner(field.farmland.id) or nil
    if ownerId ~= g_currentMission:getFarmId() then
        self.cursor:setErrorMessage("You don't own this field")
        return
    end

    local text
    if self.fruitType == nil then
        text = string.format("Remove all crops from field %d?", field.fieldId)
    else
        text = string.format("Plant the whole field %d with %s (%s)?", field.fieldId, self:getCropTitle(), self:getGrowthStateText())
    end

    local fruitTypeIndex, growthState, fieldId = self.fruitTypeIndex, self:getGrowthState(), field.fieldId
    g_gui:showYesNoDialog({
        text = text,
        yesText = "Yes",
        noText = "No",
        callback = function(_, yes)
            if yes then
                CropBrushEvent.sendRequest(CropBrushEvent.MODE_FIELD, fruitTypeIndex, growthState, 0, 0, 0, fieldId)
            end
        end,
        target = self
    })
end

-- Primary axis: brush size
function CropBrush:onAxisPrimary(inputValue)
    if inputValue > 0 then
        CropBrush.radiusIndex = math.min(CropBrush.radiusIndex + 1, #CropBrush.RADIUS_STEPS)
    elseif inputValue < 0 then
        CropBrush.radiusIndex = math.max(CropBrush.radiusIndex - 1, 1)
    end
    self.cursor:setShapeSize(self:getRadius())
    self:refreshInputTexts()
end

----------------------------------------------------------------------
-- Input texts
----------------------------------------------------------------------

function CropBrush:getButtonPrimaryText()
    if self.fruitType == nil then
        return "Remove crop"
    end
    return string.format("Plant %s (%s)", self:getCropTitle(), self:getGrowthStateText())
end

function CropBrush:getButtonSecondaryText()
    if self.fruitType == nil then
        return "-"
    end
    return "Choose growth stage"
end

function CropBrush:getButtonTertiaryText()
    if self.fruitType == nil then
        return "Clear whole field"
    end
    return "Plant whole field"
end

function CropBrush:getAxisPrimaryText()
    return string.format("Brush size (%d m)", self:getRadius())
end

----------------------------------------------------------------------
-- Add the brushes to the build menu (Landscaping -> Paint)
----------------------------------------------------------------------

local function countTabItems(screen)
    local counts = {}
    for c, category in pairs(screen.items or {}) do
        counts[c] = {}
        for t, tab in pairs(category) do
            counts[c][t] = #tab
        end
    end
    return counts
end

local function findTargetTab(screen, before)
    -- the tab the game just added its paint brushes to
    for c, category in pairs(screen.items or {}) do
        for t, tab in pairs(category) do
            local old = before[c] ~= nil and before[c][t] or 0
            if #tab > old then
                return tab
            end
        end
    end
    -- fallback: last tab of the landscaping category
    local category = g_storeManager:getConstructionCategoryByName("landscaping")
    if category ~= nil and screen.items[category.index] ~= nil then
        local tabs = screen.items[category.index]
        return tabs[#tabs]
    end
    return nil
end

local function buildTerrainPaintBrushes(screen, superFunc, numItems)
    local before = countTabItems(screen)
    numItems = superFunc(screen, numItems)

    local ok, err = pcall(function()
        local tab = findTargetTab(screen, before)
        if tab == nil then
            CropBrushUtil.log("Could not find the paint tab in the build menu")
            return
        end

        local defaultIcon = Utils.getFilename("icon_cropBrush.dds", CropBrush.modDirectory)

        numItems = numItems + 1
        table.insert(tab, {
            price = 0,
            imageFilename = defaultIcon,
            name = "Remove crop",
            brushClass = CropBrush,
            brushParameters = {CropBrushUtil.CLEAR_FRUIT},
            uniqueIndex = numItems
        })

        for _, fruitType in ipairs(CropBrushUtil.getPlantableFruitTypes()) do
            numItems = numItems + 1
            table.insert(tab, {
                price = 0,
                imageFilename = CropBrushUtil.getFruitIcon(fruitType) or defaultIcon,
                name = "Crop: " .. CropBrushUtil.getFruitTitle(fruitType),
                brushClass = CropBrush,
                brushParameters = {fruitType.index},
                uniqueIndex = numItems
            })
        end
    end)
    if not ok then
        CropBrushUtil.log("Error adding brushes to build menu: %s", tostring(err))
    end

    return numItems
end

if ConstructionScreen ~= nil and ConstructionScreen.buildTerrainPaintBrushes ~= nil then
    ConstructionScreen.buildTerrainPaintBrushes = Utils.overwrittenFunction(ConstructionScreen.buildTerrainPaintBrushes, buildTerrainPaintBrushes)
    CropBrushUtil.log("loaded - find the crop brushes in Build menu -> Landscaping -> Paint")
else
    CropBrushUtil.log("ConstructionScreen.buildTerrainPaintBrushes not found, brushes not added")
end
