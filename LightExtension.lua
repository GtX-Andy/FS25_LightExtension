--[[
Copyright (C) GtX (Andy), 2018

Author: GtX | Andy
Date: 17.12.2018
Revision: FS25-02

Contact:
https://forum.giants-software.com
https://github.com/GtX-Andy

Thankyou:
Sven777b @ http://ls-landtechnik.com    -   Allowing me to use parts of his strobe light code as found in ‘Beleuchtung v3.1.1’.
Inerti and Nicolina                     -   FS17 suggestions, testing in single and multiplayer.

Important:
Free for use in mods (FS25 Only) - no permission needed.
No modifications may be made to this script, including conversion to other game versions without written permission from GtX | Andy

Frei verwendbar (Nur LS25) - keine erlaubnis nötig
Ohne schriftliche Genehmigung von GtX | Andy dürfen keine Änderungen an diesem Skript vorgenommen werden, einschließlich der Konvertierung in andere Spielversionen
]]


LightExtension = {}

LightExtension.MOD_NAME = g_currentModName
LightExtension.SPEC_NAME = string.format("spec_%s.lightExtension", LightExtension.MOD_NAME)

LightExtension.strobeLightXMLSchema = nil
LightExtension.stepCharacters = {
    ["X"] = "ON",
    ["-"] = "OFF"
}

function LightExtension.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Lights, specializations)
end

function LightExtension.initSpecialization()
    if g_vehicleConfigurationManager:getConfigurationDescByName("lightExtension") == nil then
        g_vehicleConfigurationManager:addConfigurationType("lightExtension", g_i18n:getText("configuration_additionalLights"), "lightExtension", VehicleConfigurationItem)
    end

    local schema = Vehicle.xmlSchema

    schema:setXMLSpecializationType("LightExtension")

    local basePath = "vehicle.lightExtension.lightExtensionConfigurations.lightExtensionConfiguration(?)"

    schema:register(XMLValueType.STRING, basePath .. ".strobeLights.strobeLight(?)#filename", "Strobe light XML file")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".strobeLights.strobeLight(?)#linkNode", "Shared I3d link node")
    schema:register(XMLValueType.FLOAT, basePath .. ".strobeLights.strobeLight(?)#realLightRange", "Factor that is applied on real light range of the strobe light", 1)
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".strobeLights.strobeLight(?)#realLightNode", "Real light node. Only required if shared i3d does not include it or light is part of vehicle")

    StaticLight.registerXMLPaths(schema, basePath .. ".strobeLights.strobeLight(?).staticLight(?)")

    schema:register(XMLValueType.STRING, basePath .. ".strobeLights.strobeLight(?)#blinkPattern", "Uses a string of X and - characters to define the sequence times, X represents ON state and - represents OFF state for the given 'blinkStepLength'.")
    schema:register(XMLValueType.FLOAT, basePath .. ".strobeLights.strobeLight(?)#blinkStepLength", "A float value representing the duration of one step inside blink pattern in seconds.", 0.5)

    schema:register(XMLValueType.STRING, basePath .. ".strobeLights.strobeLight(?)#sequence", "When 'blinkPattern' is not used then a string of millisecond values each separated with a space are used to create an alternating light sequence.")
    schema:register(XMLValueType.BOOL, basePath .. ".strobeLights.strobeLight(?)#invert", "Invert the sequence. When true the first ms value will represent OFF.", false)
    schema:register(XMLValueType.INT, basePath .. ".strobeLights.strobeLight(?)#minOn", "The minimum 'ON' time in ms used to randomise if no sequence is given", 100)
    schema:register(XMLValueType.INT, basePath .. ".strobeLights.strobeLight(?)#maxOn", "The maximum 'ON' time in ms used to randomise if no sequence is given", 100)
    schema:register(XMLValueType.INT, basePath .. ".strobeLights.strobeLight(?)#minOff", "The minimum 'OFF' time in ms used to randomise if no sequence is given", 100)
    schema:register(XMLValueType.INT, basePath .. ".strobeLights.strobeLight(?)#maxOff", "The maximum 'OFF' time in ms used to randomise if no sequence is given", 400)

    SoundManager.registerSampleXMLPaths(schema, basePath, "beaconSound")
    schema:register(XMLValueType.FLOAT, basePath .. ".autoCombineBeaconLights#percent", "The percentage when the beacon lights should be activated & deactivated when operated by a player")

    schema:setXMLSpecializationType()

    local strobeLightXMLSchema = XMLSchema.new("sharedStrobeLight")

    strobeLightXMLSchema:register(XMLValueType.STRING, "strobeLight.filename", "Path to i3d file", nil, true)
    strobeLightXMLSchema:register(XMLValueType.NODE_INDEX, "strobeLight.rootNode#node", "Node index", "0")

    StaticLight.registerXMLPaths(strobeLightXMLSchema, "strobeLight.staticLight(?)")

    VehicleMaterial.registerXMLPaths(strobeLightXMLSchema, "strobeLight.baseMaterial")
    VehicleMaterial.registerXMLPaths(strobeLightXMLSchema, "strobeLight.glassMaterial")

    LightExtension.strobeLightXMLSchema = strobeLightXMLSchema
end

function LightExtension.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "loadLightExtensionStrobeLightFromXML", LightExtension.loadLightExtensionStrobeLightFromXML)
    SpecializationUtil.registerFunction(vehicleType, "loadLightExtensionLightStrobeDataFromXML", LightExtension.loadLightExtensionLightStrobeDataFromXML)
    SpecializationUtil.registerFunction(vehicleType, "onLightExtensionStrobeLightI3DLoaded", LightExtension.onLightExtensionStrobeLightI3DLoaded)
end

function LightExtension.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "loadAdditionalLightAttributesFromXML", LightExtension.loadAdditionalLightAttributesFromXML)
end

function LightExtension.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", LightExtension)
    SpecializationUtil.registerEventListener(vehicleType, "onLoadFinished", LightExtension)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete", LightExtension)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", LightExtension)
    SpecializationUtil.registerEventListener(vehicleType, "onBeaconLightsVisibilityChanged", LightExtension)
end

function LightExtension:onLoad(savegame)
    self.spec_lightExtension = self[LightExtension.SPEC_NAME]

    if self.spec_lightExtension == nil then
        Logging.error("[%s] Specialization with name 'lightExtension' was not found in modDesc!", LightExtension.MOD_NAME)
    end

    local spec = self.spec_lightExtension

    spec.xmlLoadingHandles = {}
    spec.sharedLoadRequestIds = {}
    spec.strobeLights = {}

    spec.strobeLightsActive = false
    spec.strobeLightsNeedReset = false

    spec.hasStrobeLights = false
    spec.hasAutoCombineBeaconLights = false

    if self.xmlFile:hasProperty("vehicle.lightExtension") and not self.xmlFile:hasProperty("vehicle.lightExtension.lightExtensionConfigurations") then
        Logging.xmlWarning(self.xmlFile, "FS25 LightExtension XML keys were not found!  Required: 'vehicle.lightExtension.lightExtensionConfigurations.lightExtensionConfiguration'")

        SpecializationUtil.removeEventListener(self, "onLoadFinished", LightExtension)
        SpecializationUtil.removeEventListener(self, "onDelete", LightExtension)
        SpecializationUtil.removeEventListener(self, "onUpdate", LightExtension)
        SpecializationUtil.removeEventListener(self, "onBeaconLightsVisibilityChanged", LightExtension)

        return
    end

    local lightExtensionConfigurationId = Utils.getNoNil(self.configurations.lightExtension, 1)
    local configKey = string.format("vehicle.lightExtension.lightExtensionConfigurations.lightExtensionConfiguration(%d)", lightExtensionConfigurationId - 1)

    ObjectChangeUtil.updateObjectChanges(self.xmlFile, "vehicle.lightExtension.lightExtensionConfigurations.lightExtensionConfiguration", lightExtensionConfigurationId, self.components, self)

    -- Removed 'Running Lights feature, no longer required in FS25
    if self.xmlFile:hasProperty(configKey .. ".runningLights") then
        Logging.xmlWarning(self.xmlFile, "Light Extension no longer supports 'Running Lights', use base game option 'vehicle.lights.dayTimeLights.dayTimeLight' instead")

        return
    end

    -- A flexible strobe light system allowing for random sequences or ms sequences or patterns using X (ON) and - (OFF).
    self.xmlFile:iterate(configKey .. ".strobeLights.strobeLight", function (_, key)
        self:loadLightExtensionStrobeLightFromXML(self.xmlFile, key)
    end)

    -- Plays a sample when beacons are active, maybe a police siren or similar
    local beaconSoundSample = g_soundManager:loadSampleFromXML(self.xmlFile, configKey, "beaconSound", self.baseDirectory, self.components, 0, AudioGroup.VEHICLE, self.i3dMappings, self)

    if beaconSoundSample ~= nil then
        spec.beaconSound = {
            sample = beaconSoundSample,
            isActive = false
        }
    end

    -- Toggles beacons on when fill level reaches percent. No longer plays a sound, this can be added via base game since FS22
    local percent = self.xmlFile:getValue(configKey .. ".autoCombineBeaconLights#percent")

    if percent ~= nil then
        if (self.spec_combine ~= nil and self.spec_pipe ~= nil) and self.spec_fillUnit ~= nil then
            spec.autoCombineBeaconLights = {
                percent = math.clamp(percent * 0.01, 0.01, 1),
                active = false
            }
        else
            Logging.xmlWarning(self.xmlFile, "[LightExtension] Auto combine beacon lights is only for use on combines and requires the 'fillUnit', 'combine' and 'pipe' specializations.")
        end
    end
end

function LightExtension:onLoadFinished(savegame)
    local spec = self.spec_lightExtension

    spec.hasRealStrobeLights = g_gameSettings:getValue("realBeaconLights")
    spec.hasStrobeLights = #spec.strobeLights > 0
    spec.hasAutoCombineBeaconLights = spec.autoCombineBeaconLights ~= nil

    if not spec.hasStrobeLights then
        if spec.beaconSound == nil then
            SpecializationUtil.removeEventListener(self, "onBeaconLightsVisibilityChanged", LightExtension)
        end

        if self.isServer then
            if not spec.hasAutoCombineBeaconLights then
                SpecializationUtil.removeEventListener(self, "onUpdate", LightExtension)
            end
        else
            SpecializationUtil.removeEventListener(self, "onUpdate", LightExtension)
        end
    end
end

function LightExtension:onDelete()
    local spec = self.spec_lightExtension

    spec.hasStrobeLights = false
    spec.hasAutoCombineBeaconLights = false

    if spec.xmlLoadingHandles ~= nil then
        for lightXMLFile, _ in pairs(spec.xmlLoadingHandles) do
            lightXMLFile:delete()
        end

        spec.xmlLoadingHandles = nil
    end

    if spec.sharedLoadRequestIds ~= nil then
        for _, sharedLoadRequestId in ipairs(spec.sharedLoadRequestIds) do
            g_i3DManager:releaseSharedI3DFile(sharedLoadRequestId)
        end

        spec.sharedLoadRequestIds = nil
    end

    if spec.beaconSound ~= nil then
        g_soundManager:deleteSample(spec.beaconSound.sample)

        spec.beaconSound = nil
    end
end

function LightExtension:onUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local spec = self.spec_lightExtension

    if self.isClient and spec.hasStrobeLights then
        if spec.strobeLightsActive then
            spec.strobeLightsNeedReset = true

            for i, light in ipairs(spec.strobeLights) do
                light.time += dt

                if light.time >= light.sequenceTime then
                    -- Keep the extra time to try and keep all lights in sync ??
                    light.time = math.max(light.time - light.sequenceTime, 0)

                    if not light.isRandom then
                        -- If sequence has reached the start then reset in case a pattern has the same start and end type
                        if light.index == 1 then
                            light.active = not light.invert
                        else
                            light.active = not light.active
                        end

                        light.sequenceTime = light.sequence[light.index]

                        light.index += 1

                        if light.index > light.sequenceCount then
                            light.index = 1
                        end
                    else
                        light.active = not light.active

                        if light.active then
                            light.sequenceTime = math.random(light.minOn, light.maxOn)
                        else
                            light.sequenceTime = math.random(light.minOff, light.maxOff)
                        end
                    end

                    for _, staticLight in ipairs(light.staticLights) do
                        staticLight:setState(light.active)
                    end

                    if spec.hasRealStrobeLights and light.realLightNode ~= nil then
                        setVisibility(light.realLightNode, light.active)
                    end
                end
            end

            self:raiseActive()
        elseif spec.strobeLightsNeedReset then
            spec.strobeLightsNeedReset = false

            for _, light in ipairs(spec.strobeLights) do
                for _, staticLight in ipairs(light.staticLights) do
                    staticLight:setState(false)
                end

                if light.realLightNode ~= nil then
                    setVisibility(light.realLightNode, false)
                end

                if not light.isRandom then
                    light.index = 1
                    light.active = light.invert
                    light.sequenceTime = 0
                    light.time = 0
                end
            end
        end
    end

    if self.isServer and spec.hasAutoCombineBeaconLights and not self:getIsAIActive() then
        local fillLevel, capacity = 0, 0
        local dischargeNode = self:getCurrentDischargeNode()

        if dischargeNode ~= nil then
            fillLevel = self:getFillUnitFillLevel(dischargeNode.fillUnitIndex) or 0
            capacity = self:getFillUnitCapacity(dischargeNode.fillUnitIndex) or 0
        end

        if fillLevel > spec.autoCombineBeaconLights.percent * capacity then
            if not spec.autoCombineBeaconLights.active then
                self:setBeaconLightsVisibility(true)
                spec.autoCombineBeaconLights.active = true
            end
        else
            if spec.autoCombineBeaconLights.active then
                self:setBeaconLightsVisibility(false)
                spec.autoCombineBeaconLights.active = false
            end
        end
    end
end

function LightExtension:onBeaconLightsVisibilityChanged(visibility)
    local spec = self.spec_lightExtension

    spec.strobeLightsActive = Utils.getNoNil(visibility, false)

    if self.isClient and spec.beaconSound ~= nil then
        spec.beaconSound.isActive = spec.strobeLightsActive

        if spec.beaconSound.isActive then
            g_soundManager:playSample(spec.beaconSound.sample)
        else
            g_soundManager:stopSample(spec.beaconSound.sample)
        end
    end

    self:raiseActive()
end

function LightExtension:loadLightExtensionStrobeLightFromXML(vehicleXmlFile, key)
    local spec = self.spec_lightExtension
    local xmlFilename = vehicleXmlFile:getValue(key .. "#filename")

    if xmlFilename ~= nil then
        local linkNode = vehicleXmlFile:getValue(key .. "#linkNode", nil, self.components, self.i3dMappings)

        if linkNode ~= nil then
            xmlFilename = Utils.getFilename(xmlFilename, self.baseDirectory)

            local xmlFile = XMLFile.loadIfExists("sharedStrobeLight", xmlFilename, LightExtension.strobeLightXMLSchema)

            if xmlFile == nil then
                if SharedLight.FS22_RENAMED_LIGHTS ~= nil then
                    for old, new in pairs(SharedLight.FS22_RENAMED_LIGHTS) do
                        if xmlFilename:find(old) then
                            local newPath = xmlFilename:gsub(old, new)
                            if fileExists(newPath) then
                                Logging.xmlWarning(vehicleXmlFile, "Light has been renamed from '%s' to '%s'!", old, new)

                                return
                            end
                        end
                    end
                end

                Logging.xmlWarning(vehicleXmlFile, "Unable to load shared lights from xml '%s'", xmlFilename)

                return
            end

            local filename = xmlFile:getValue("strobeLight.filename")

            if filename == nil then
                Logging.xmlWarning(xmlFile, "Missing light i3d filename!")

                xmlFile:delete()

                return
            end

            filename = Utils.getFilename(filename, self.baseDirectory)
            spec.xmlLoadingHandles[xmlFile] = filename

            local strobeLight = {
                linkNode = linkNode,
                xmlFile = xmlFile,
                staticLights = {},
                isSharedLight = true
            }

            local realLightNode = vehicleXmlFile:getValue(key .. "#realLightNode", nil, self.components, self.i3dMappings)

            if realLightNode ~= nil then
                if getHasClassId(realLightNode, ClassIds.LIGHT_SOURCE) then
                    local realLightRange = vehicleXmlFile:getValue(key .. "#realLightRange", 1)
                    local defaultLightRange = getLightRange(realLightNode)

                    setLightRange(realLightNode, defaultLightRange * realLightRange)
                    setVisibility(realLightNode, false)

                    strobeLight.realLightNode = realLightNode
                else
                    Logging.xmlWarning(vehicleXmlFile, "Node '%s' is not a real light source in '%s'", getName(realLightNode), key)
                end
            end

            if self:loadLightExtensionLightStrobeDataFromXML(vehicleXmlFile, key, strobeLight) then
                local sharedLoadRequestId

                if self.loadSubSharedI3DFile ~= nil then
                    sharedLoadRequestId = self:loadSubSharedI3DFile(filename, false, false, self.onLightExtensionStrobeLightI3DLoaded, self, strobeLight)
                else
                    sharedLoadRequestId = g_i3DManager:loadSharedI3DFileAsync(filename, false, false, self.onLightExtensionStrobeLightI3DLoaded, self, strobeLight)
                end

                table.insert(spec.sharedLoadRequestIds, sharedLoadRequestId)
            end
        else
            Logging.xmlWarning(vehicleXmlFile, "Missing light linkNode in '%s'!", key)
        end
    else
        local staticLights = {}

        for _, staticLightKey in vehicleXmlFile:iterator(key .. ".staticLight") do
            local staticLight = StaticLight.new(self)

            staticLight.isTopLight = false
            staticLight.isBottomLight = false
            staticLight.isLightExtensionStrobe = true

            if staticLight:loadFromXML(vehicleXmlFile, staticLightKey, self.components, self.i3dMappings, false, nil) then
                table.insert(staticLights, staticLight)
            end
        end

        if #staticLights > 0 then
            local strobeLight = {
                staticLights = staticLights,
                isSharedLight = false
            }

            if self:loadLightExtensionLightStrobeDataFromXML(vehicleXmlFile, key, strobeLight) then
                local realLightNode = vehicleXmlFile:getValue(key .. "#realLightNode", nil, self.components, self.i3dMappings)

                if realLightNode ~= nil then
                    if getHasClassId(realLightNode, ClassIds.LIGHT_SOURCE) then
                        local realLightRange = vehicleXmlFile:getValue(key .. "#realLightRange", 1)
                        local defaultLightRange = getLightRange(realLightNode)

                        setLightRange(realLightNode, defaultLightRange * realLightRange)
                        setVisibility(realLightNode, false)

                        strobeLight.realLightNode = realLightNode
                    else
                        Logging.xmlWarning(vehicleXmlFile, "Node '%s' is not a real light source in '%s'", getName(realLightNode), key)
                    end
                end

                table.insert(spec.strobeLights, strobeLight)
            end
        end
    end
end

function LightExtension:onLightExtensionStrobeLightI3DLoaded(i3dNode, failedReason, strobeLight)
    local spec = self.spec_lightExtension

    if i3dNode ~= 0 then
        strobeLight.node = strobeLight.xmlFile:getValue("strobeLight.rootNode#node", "0", i3dNode)

        if strobeLight.node ~= nil then
            StaticLight.loadLightsFromXML(strobeLight.staticLights, strobeLight.xmlFile, "strobeLight.staticLight", self, i3dNode, nil, false, strobeLight)

            if strobeLight.xmlFile:hasProperty("strobeLight.baseMaterial") then
                local material = VehicleMaterial.new(self.baseDirectory)

                if material:loadFromXML(strobeLight.xmlFile, "strobeLight.baseMaterial", self.customEnvironment) then
                    material:apply(strobeLight.node, "sharedLightBase_mat")
                end
            end

            if strobeLight.xmlFile:hasProperty("strobeLight.glassMaterial") then
                local material = VehicleMaterial.new(self.baseDirectory)

                if material:loadFromXML(strobeLight.xmlFile, "strobeLight.glassMaterial", self.customEnvironment) then
                    material:apply(strobeLight.node, "sharedLightGlass_mat")
                end
            end

            link(strobeLight.linkNode, strobeLight.node)

            if #strobeLight.staticLights > 0 then
                table.insert(spec.strobeLights, strobeLight)
            end
        end

        delete(i3dNode)
    end

    spec.xmlLoadingHandles[strobeLight.xmlFile] = nil

    strobeLight.xmlFile:delete()
    strobeLight.xmlFile = nil
    strobeLight.key = nil
end

function LightExtension:loadLightExtensionLightStrobeDataFromXML(xmlFile, key, light)
    light.time = 0
    light.sequenceTime = 0

    local blinkPattern = xmlFile:getValue(key .. "#blinkPattern") -- Similar to ETS2 and ATS strobe patterns for those more familiar with this using a string of X and - characters, where X represents ON state and - represents OFF state.

    if blinkPattern ~= nil then
        blinkPattern = blinkPattern:trim()

        local blinkStepLength = xmlFile:getValue(key .. "#blinkStepLength", 0.5) * 1000 -- Float representing duration of one step inside blink pattern in seconds.

        local sequence = {}
        local stepTime = 0

        local invert = blinkPattern:sub(1, 1) == "-"
        local lastCharacter = invert and "-" or "X"
        local patternLength = #blinkPattern

        for i = 1, patternLength do
            local character = blinkPattern:sub(i, i)

            if LightExtension.stepCharacters[character] ~= nil then
                if lastCharacter ~= character then
                    table.insert(sequence, math.floor(stepTime + 0.5))
                    stepTime = 0
                end

                stepTime += blinkStepLength
                lastCharacter = character

                if i == patternLength then
                    table.insert(sequence, math.floor(stepTime + 0.5))
                end
            end
        end

        if #sequence > 0 then
            light.isRandom = false
            light.sequence = sequence
            light.sequenceCount = #sequence
            light.invert = invert
            light.active = invert
            light.index = 1
        else
            light.isRandom = true
            light.active = false
            light.minOn = 100
            light.maxOn = 100
            light.minOff = 100
            light.maxOff = 400

            Logging.xmlWarning(xmlFile, "Invalid or no Blink Pattern' given in '%s'. Loading random sequence instead!", key)
        end
    else
        -- Make sure there is a real sequence or at least 1 value
        local sequence = string.getVector(xmlFile:getValue(key .. "#sequence"))
        local sequenceCount = sequence ~= nil and #sequence or 0

        if sequenceCount > 0 then
            light.isRandom = false
            light.sequence = sequence
            light.sequenceCount = sequenceCount
            light.invert = xmlFile:getValue(key .. "#invert", false)
            light.active = light.invert
            light.index = 1
        else
            light.isRandom = true
            light.active = false
            light.minOn = xmlFile:getValue(key .. "#minOn", 100)
            light.maxOn = xmlFile:getValue(key .. "#maxOn", 100)
            light.minOff = xmlFile:getValue(key .. "#minOff", 100)
            light.maxOff = xmlFile:getValue(key .. "#maxOff", 400)
        end
    end

    return true
end

function LightExtension:loadAdditionalLightAttributesFromXML(superFunc, xmlFile, key, light)
    if light ~= nil and light.isLightExtensionStrobe then
        return false
    end

    return superFunc(self, xmlFile, key, light)
end