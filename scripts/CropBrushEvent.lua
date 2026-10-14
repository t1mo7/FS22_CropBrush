-- CropBrushEvent: sends a paint request from a multiplayer client to the server

CropBrushEvent = {}
CropBrushEvent.MODE_CIRCLE = 0
CropBrushEvent.MODE_FIELD = 1

local CropBrushEvent_mt = Class(CropBrushEvent, Event)
InitEventClass(CropBrushEvent, "CropBrushEvent")

function CropBrushEvent.emptyNew()
    return Event.new(CropBrushEvent_mt)
end

function CropBrushEvent.new(mode, fruitTypeIndex, growthState, x, z, radius, fieldId)
    local self = CropBrushEvent.emptyNew()
    self.mode = mode
    self.fruitTypeIndex = fruitTypeIndex
    self.growthState = growthState
    self.x = x or 0
    self.z = z or 0
    self.radius = radius or 0
    self.fieldId = fieldId or 0
    return self
end

function CropBrushEvent:readStream(streamId, connection)
    self.mode = streamReadUInt8(streamId)
    self.fruitTypeIndex = streamReadInt32(streamId)
    self.growthState = streamReadUInt8(streamId)
    self.x = streamReadFloat32(streamId)
    self.z = streamReadFloat32(streamId)
    self.radius = streamReadFloat32(streamId)
    self.fieldId = streamReadInt32(streamId)
    self:run(connection)
end

function CropBrushEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.mode)
    streamWriteInt32(streamId, self.fruitTypeIndex)
    streamWriteUInt8(streamId, self.growthState)
    streamWriteFloat32(streamId, self.x)
    streamWriteFloat32(streamId, self.z)
    streamWriteFloat32(streamId, self.radius)
    streamWriteInt32(streamId, self.fieldId)
end

function CropBrushEvent:run(connection)
    if not connection:getIsServer() then
        CropBrushUtil.applyRequest(self.mode, self.fruitTypeIndex, self.growthState, self.x, self.z, self.radius, self.fieldId)
    end
end

-- Applies directly on server / single player, otherwise asks the server
function CropBrushEvent.sendRequest(mode, fruitTypeIndex, growthState, x, z, radius, fieldId)
    if g_server ~= nil then
        CropBrushUtil.applyRequest(mode, fruitTypeIndex, growthState, x, z, radius, fieldId)
    else
        g_client:getServerConnection():sendEvent(CropBrushEvent.new(mode, fruitTypeIndex, growthState, x, z, radius, fieldId))
    end
end
