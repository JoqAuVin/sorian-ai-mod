do
local SUtils = import('/lua/AI/sorianutilities.lua')

sorianoldPlatoon = Platoon

Platoon = Class(sorianoldPlatoon) {

    OnDestroy = function(self)
		
		#Courtesy of Duncane
		self:StopAI()
		self:PlatoonDisband()
        
		self:DoDestroyCallbacks()
        if self.Trash then
            self.Trash:Destroy()
        end
    end,

    NukeAISorian = function(self)
    end,

    ExperimentalAIHubSorian = function(self)
		local aiBrain = self:GetBrain()
	    local behaviors = import('/lua/ai/AIBehaviors.lua')
	    
	    local experimental = self:GetPlatoonUnits()[1]
	    if not experimental then
		    return
	    end
		if Random(1,5) == 3 and (not aiBrain.LastTaunt or GetGameTimeSeconds() - aiBrain.LastTaunt > 90) then
			local randelay = Random(60,180)
			aiBrain.LastTaunt = GetGameTimeSeconds() + randelay
			SUtils.AIDelayChat('enemies', ArmyBrains[aiBrain:GetArmyIndex()].Nickname, 't4taunt', nil, randelay)
		end
        local ID = experimental:GetUnitId()
        
		self:SetPlatoonFormationOverride('AttackFormation')
		
        if ID == 'uel0401' then
            return behaviors.FatBoyBehaviorSorian(self)
        elseif ID == 'uaa0310' then
            return behaviors.CzarBehaviorSorian(self)
        elseif ID == 'xsa0402' then
            return behaviors.AhwassaBehaviorSorian(self)
        elseif ID == 'ura0401' then
            return behaviors.TickBehaviorSorian(self)
        elseif ID == 'url0401' then
            return behaviors.ScathisBehaviorSorian(self)
        elseif ID == 'uas0401' then
            return self:NavalHuntAI(self)
        elseif ID == 'ues0401' then
            return self:NavalHuntAI(self)
        end
        
        return behaviors.BehemothBehaviorSorian(self)
    end,
	
    PlatoonCallForHelpAISorian = function(self)
        local aiBrain = self:GetBrain()
        local checkTime = self.PlatoonData.DistressCheckTime or 7
		local pos = self:GetPlatoonPosition()
        while aiBrain:PlatoonExists(self) and pos do
            if pos and not self.DistressCall then
                local threat = aiBrain:GetThreatAtPosition( pos, 0, true, 'AntiSurface' )
				local myThreat = aiBrain:GetThreatAtPosition( pos, 0, true, 'AntiSurface', aiBrain:GetArmyIndex())
				 #LOG('*AI DEBUG: PlatoonCallForHelpAISorian threat is: '..threat..' myThreat is: '..myThreat)
                if threat and threat > (myThreat * 1.5) then
                    #LOG('*AI DEBUG: Platoon Calling for help')
                    aiBrain:BaseMonitorPlatoonDistress(self, threat)
                    self.DistressCall = true
                end
            end
            WaitSeconds(checkTime)
			pos = self:GetPlatoonPosition()
        end
    end,
	
    DistressResponseAISorian = function(self)
        local aiBrain = self:GetBrain()
        while aiBrain:PlatoonExists(self) do
            # In the loop so they may be changed by other platoon things
            local distressRange = self.PlatoonData.DistressRange or aiBrain.BaseMonitor.DefaultDistressRange
            local reactionTime = self.PlatoonData.DistressReactionTime or aiBrain.BaseMonitor.PlatoonDefaultReactionTime
            local threatThreshold = self.PlatoonData.ThreatSupport or self.BaseMonitor.AlertLevel or 1
            local platoonPos = self:GetPlatoonPosition()
			local transporting = false
			units = self:GetPlatoonUnits()
			for k, v in units do
				if not v:IsDead() and v:IsUnitState( 'Attached' ) then
					transporting = true
				end
				if transporting then break end
			end
            if platoonPos and not self.DistressCall and not transporting then
                # Find a distress location within the platoons range
                local distressLocation = aiBrain:BaseMonitorDistressLocation(platoonPos, distressRange, threatThreshold)
                local moveLocation
				local threatatPos
				local myThreatatPos
                
                # We found a location within our range! Activate!
                if distressLocation then
                    #LOG('*AI DEBUG: ARMY '.. aiBrain:GetArmyIndex() ..': --- DISTRESS RESPONSE AI ACTIVATION ---')
                    
                    # Backups old ai plan
                    local oldPlan = self:GetPlan()
                    if self.AIThread then
                        self.AIThread:Destroy()
                    end
                    
                    # Continue to position until the distress call wanes
                    repeat
                        moveLocation = distressLocation
                        self:Stop()
                        local cmd = self:AggressiveMoveToLocation( distressLocation )
						local poscheck = self:GetPlatoonPosition()
						local prevpos = poscheck
						local poscounter = 0
						local breakResponse = false
                        repeat
                            WaitSeconds(reactionTime)
                            if not aiBrain:PlatoonExists(self) then
                                return
                            end
							poscheck = self:GetPlatoonPosition()
							if VDist3(poscheck, prevpos) < 10 then
								poscounter = poscounter + 1
								if poscounter >= 3 then
									breakResponse = true
									poscounter = 0
								end
							elseif not SUtils.CanRespondEffectively(aiBrain, distressLocation, self) then
								breakResponse = true
								poscounter = 0
							else
								prevpos = poscheck
								poscounter = 0
							end
							threatatPos = aiBrain:GetThreatAtPosition(moveLocation, 0, true, 'AntiSurface')
							artyThreatatPos = aiBrain:GetThreatAtPosition(moveLocation, 0, true, 'Artillery')
							myThreatatPos = aiBrain:GetThreatAtPosition(moveLocation, 0, true, 'AntiSurface', aiBrain:GetArmyIndex())
                        until not self:IsCommandsActive(cmd) or breakResponse or ((threatatPos + artyThreatatPos) - myThreatatPos) <= threatThreshold
                        
                        
                        platoonPos = self:GetPlatoonPosition()
                        if platoonPos then
                            # Now that we have helped the first location, see if any other location needs the help
                            distressLocation = aiBrain:BaseMonitorDistressLocation(platoonPos, distressRange)
                            if distressLocation then
                                self:AggressiveMoveToLocation( distressLocation )
                            end
                        end
                    # If no more calls or we are at the location; break out of the function
                    until not distressLocation or not SUtils.CanRespondEffectively(aiBrain, distressLocation, self) or ( distressLocation[1] == moveLocation[1] and distressLocation[3] == moveLocation[3] )
                    
                    #LOG('*AI DEBUG: '..aiBrain.Name..' DISTRESS RESPONSE AI DEACTIVATION - oldPlan: '..oldPlan)
					if not oldPlan then
						units = self:GetPlatoonUnits()
						for k, v in units do
							if not v:IsDead() and EntityCategoryContains(categories.MOBILE * categories.EXPERIMENTAL, v) then
								oldPlan = 'ExperimentalAIHubSorian'
							elseif not v:IsDead() and EntityCategoryContains(categories.MOBILE * categories.LAND - categories.EXPERIMENTAL, v) then
								oldPlan = 'AttackForceAISorian'
							elseif not v:IsDead() and EntityCategoryContains(categories.MOBILE * categories.AIR - categories.EXPERIMENTAL, v) then
								oldPlan = 'AirHuntAI'
							elseif not v:IsDead() and EntityCategoryContains(categories.MOBILE * categories.NAVAL - categories.EXPERIMENTAL, v) then
								oldPlan = 'NavalForceAISorian'
							end
							if oldPlan then break end
						end
					end
                    self:SetAIPlan(oldPlan)
                end
            end
            WaitSeconds(11)
        end
    end,
	
    BaseManagersDistressAI = function(self)
        local aiBrain = self:GetBrain()
        while aiBrain:PlatoonExists(self) do
            local distressRange = aiBrain.BaseMonitor.PoolDistressRange
            local reactionTime = aiBrain.BaseMonitor.PoolReactionTime

            local platoonUnits = self:GetPlatoonUnits()
            
            for locName, locData in aiBrain.BuilderManagers do
                if not locData.BaseSettings.DistressCall then
                    local position = locData.EngineerManager:GetLocationCoords()
					local retPos = AIUtils.RandomLocation(position[1],position[3])
                    local radius = locData.EngineerManager:GetLocationRadius()
                    local distressRange = locData.BaseSettings.DistressRange or aiBrain.BaseMonitor.PoolDistressRange
                    local distressLocation = aiBrain:BaseMonitorDistressLocation( position, distressRange, aiBrain.BaseMonitor.PoolDistressThreshold )
                    
                    # Distress !
                    if distressLocation then
                        #LOG('*AI DEBUG: ARMY '.. aiBrain:GetArmyIndex() ..': --- POOL DISTRESS RESPONSE ---')
                        
                        # Grab the units at the location
                        local group = self:GetUnitsAroundPoint( categories.MOBILE - categories.EXPERIMENTAL - categories.COMMAND - categories.ENGINEER, position, radius )

                        # Move the group to the distress location and then back to the location of the base
                        IssueClearCommands( group )
                        IssueAggressiveMove( group, distressLocation )
                        IssueMove( group, retPos )
                        
                        # Set distress active for duration
                        locData.BaseSettings.DistressCall = true
                        self:ForkThread( self.UnlockBaseManagerDistressLocation, locData )
                    end
                end
            end
            WaitSeconds( aiBrain.BaseMonitor.PoolReactionTime )
        end
    end,
	
    PauseAI = function(self)
        local platoonUnits = self:GetPlatoonUnits()
        local aiBrain = self:GetBrain()
        for k, v in platoonUnits do
            v:SetScriptBit('RULEUTC_ProductionToggle', true)
        end
        local econ = AIUtils.AIGetEconomyNumbers(aiBrain)
        while econ.EnergyStorageRatio < 0.8 do
            WaitSeconds(2)
            econ = AIUtils.AIGetEconomyNumbers(aiBrain)
        end
        for k, v in platoonUnits do
            v:SetScriptBit('RULEUTC_ProductionToggle', false)
        end
        self:PlatoonDisband()
	end,
	
    EnhanceAI = function(self)
		self:Stop()
        local aiBrain = self:GetBrain()
        local unit
        for k,v in self:GetPlatoonUnits() do
            unit = v
            break
        end
        local data = self.PlatoonData
		local numLoop = 0
		local lastEnhancement
        if unit then
			unit.Upgrading = true
            IssueStop({unit})
            IssueClearCommands({unit})
            for k,v in data.Enhancement do
				if not unit:HasEnhancement(v) then
					local order = {
						TaskName = "EnhanceTask",
						Enhancement = v
					}
					IssueScript({unit}, order)
					lastEnhancement = v
					#LOG('*AI DEBUG: '..aiBrain.Nickname..' EnhanceAI Added Enhancement: '..v)
				end
            end
            WaitSeconds(data.TimeBetweenEnhancements or 1)
            repeat
                WaitSeconds(5)
                if not aiBrain:PlatoonExists(self) then
					#LOG('*AI DEBUG: '..aiBrain.Nickname..' EnhanceAI platoon dead')
                    return
                end
				if not unit:IsUnitState('Upgrading') then
					numLoop = numLoop + 1
				else
					numLoop = 0
				end
				#LOG('*AI DEBUG: '..aiBrain.Nickname..' EnhanceAI loop. numLoop = '..numLoop)
            until unit:IsDead() or numLoop > 1 or unit:HasEnhancement(lastEnhancement)
			#LOG('*AI DEBUG: '..aiBrain.Nickname..' EnhanceAI exited loop. numLoop = '..numLoop)
			unit.Upgrading = false
		end
		#LOG('*AI DEBUG: '..aiBrain.Nickname..' EnhanceAI done')
        if data.DoNotDisband then return end
        self:PlatoonDisband()
    end,
	
    UnitUpgradeAI = function(self)
        local aiBrain = self:GetBrain()
        local platoonUnits = self:GetPlatoonUnits()
        local factionIndex = aiBrain:GetFactionIndex()
		local upgradeIssued = false
        self:Stop()
        for k, v in platoonUnits do
            local upgradeID
            if EntityCategoryContains(categories.MOBILE, v ) then
                upgradeID = aiBrain:FindUpgradeBP(v:GetUnitId(), UnitUpgradeTemplates[factionIndex])
            else
                upgradeID = aiBrain:FindUpgradeBP(v:GetUnitId(), StructureUpgradeTemplates[factionIndex])
            end
			if EntityCategoryContains(categories.CONSTRUCTION, v) and not v:CanBuild(upgradeID) then
				continue
			end
            if upgradeID then
				upgradeIssued = true
                IssueUpgrade({v}, upgradeID)
            end
        end
		if not upgradeIssued then 
			self:PlatoonDisband()
			return
		end
        local upgrading = true
        while aiBrain:PlatoonExists(self) and upgrading do
            WaitSeconds(3)
            upgrading = false
            for k, v in platoonUnits do
                if v and not v:IsDead() then
                    upgrading = true
                end
            end
        end
        if not aiBrain:PlatoonExists(self) then
            return
        end
        WaitTicks(1)
        self:PlatoonDisband()
    end,

    ArtilleryAISorian = function(self)
        local aiBrain = self:GetBrain()

        local atkPri = { 'STRUCTURE STRATEGIC EXPERIMENTAL', 'EXPERIMENTAL ARTILLERY OVERLAYINDIRECTFIRE', 'STRUCTURE STRATEGIC TECH3', 'STRUCTURE NUKE TECH3', 'EXPERIMENTAL ORBITALSYSTEM', 'EXPERIMENTAL ENERGYPRODUCTION STRUCTURE', 'STRUCTURE ANTIMISSILE TECH3', 'TECH3 MASSFABRICATION', 'TECH3 ENERGYPRODUCTION', 'STRUCTURE STRATEGIC', 'STRUCTURE DEFENSE TECH3 ANTIAIR',
		'COMMAND', 'STRUCTURE DEFENSE TECH3', 'STRUCTURE DEFENSE TECH2', 'EXPERIMENTAL LAND', 'MOBILE TECH3 LAND', 'MOBILE TECH2 LAND', 'MOBILE TECH1 LAND', 'STRUCTURE FACTORY', 'SPECIALLOWPRI', 'ALLUNITS' }
        local atkPriTable = {}
        for k,v in atkPri do
            table.insert( atkPriTable, ParseEntityCategory( v ) )
        end
        self:SetPrioritizedTargetList( 'Artillery', atkPriTable )

        # Set priorities on the unit so if the target has died it will reprioritize before the platoon does
        local unit = false
        for k,v in self:GetPlatoonUnits() do
            if not v:IsDead() then
                unit = v
                break
            end
        end
        if not unit then
            return
        end
        local bp = unit:GetBlueprint()
        local weapon = bp.Weapon[1]
        local maxRadius = weapon.MaxRadius
        unit:SetTargetPriorities( atkPriTable )
        
        while aiBrain:PlatoonExists(self) do
			if self:IsOpponentAIRunning() then                
                target = AIUtils.AIFindBrainTargetInRangeSorian( aiBrain, self, 'Artillery', maxRadius, atkPri, true )
				local newtarget
				if aiBrain.AttackPoints and table.getn(aiBrain.AttackPoints) > 0 then
					newtarget = AIUtils.AIFindPingTargetInRangeSorian( aiBrain, self, 'Artillery', maxRadius, atkPri, true )
					if newtarget then
						target = newtarget
					end
				end
                if target and not unit:IsDead() then
					#self:Stop()
					#self:AttackTarget(target)
                    IssueClearCommands( {unit} )
                    IssueAttack( {unit}, target )
				elseif not target then
					self:Stop()
				end
            end
            WaitSeconds(20)
        end
    end,
	
    SatelliteAISorian = function(self)
        local aiBrain = self:GetBrain()
		local data = self.PlatoonData
		local atkPri = {}
		local atkPriTable = {}
        if data.PrioritizedCategories then
            for k,v in data.PrioritizedCategories do
                table.insert( atkPri, v )
                table.insert( atkPriTable, ParseEntityCategory( v ) )
            end
        end
        table.insert( atkPri, 'ALLUNITS' )
        table.insert( atkPriTable, categories.ALLUNITS )
        self:SetPrioritizedTargetList( 'Attack', atkPriTable )
		
		local maxRadius = data.SearchRadius or 50
		local oldTarget = false
		local target = false
        
        while aiBrain:PlatoonExists(self) do
			self:MergeWithNearbyPlatoonsSorian('SatelliteAISorian', 50, true)
			if self:IsOpponentAIRunning() then
                target = AIUtils.AIFindBrainTargetInRangeSorian( aiBrain, self, 'Attack', maxRadius, atkPri )
				local newtarget
				if aiBrain.AttackPoints and table.getn(aiBrain.AttackPoints) > 0 then
					newtarget = AIUtils.AIFindPingTargetInRangeSorian( aiBrain, self, 'Attack', maxRadius, atkPri )
					if newtarget then
						target = newtarget
					end
				end
                if target and target != oldTarget and not target:IsDead() then
					self:Stop()
					self:AttackTarget(target)
					oldTarget = target
				end
            end
            WaitSeconds(30)
        end
    end,

    TacticalAISorian = function(self)
        self:Stop()
        local aiBrain = self:GetBrain()
        local armyIndex = aiBrain:GetArmyIndex()
        local platoonUnits = self:GetPlatoonUnits()
        local unit
        
        if not aiBrain:PlatoonExists(self) then return end
        
        #GET THE Launcher OUT OF THIS PLATOON
        for k, v in platoonUnits do
            if EntityCategoryContains(categories.STRUCTURE * categories.TACTICALMISSILEPLATFORM, v) then
                unit = v
                break
            end
        end
        
        if not unit then return end
        
        local bp = unit:GetBlueprint()
        local weapon = bp.Weapon[1]
        local maxRadius = weapon.MaxRadius
        local minRadius = weapon.MinRadius
        unit:SetAutoMode(true)
		local atkPri = { 'STRUCTURE STRATEGIC EXPERIMENTAL', 'ARTILLERY EXPERIMENTAL', 'STRUCTURE NUKE EXPERIMENTAL', 'EXPERIMENTAL ORBITALSYSTEM', 'STRUCTURE ARTILLERY TECH3', 
		'STRUCTURE NUKE TECH3', 'EXPERIMENTAL ENERGYPRODUCTION STRUCTURE', 'COMMAND', 'EXPERIMENTAL MOBILE LAND', 'TECH3 MASSFABRICATION', 'TECH3 ENERGYPRODUCTION', 'TECH3 MASSPRODUCTION', 'TECH2 ENERGYPRODUCTION', 'TECH2 MASSPRODUCTION', 'STRUCTURE STRATEGIC', 'STRUCTURE DEFENSE TECH3', 'STRUCTURE DEFENSE TECH2', 'STRUCTURE FACTORY', 'STRUCTURE', 'ALLUNITS' }
        self:SetPrioritizedTargetList( 'Attack', { categories.STRUCTURE * categories.ARTILLERY * categories.EXPERIMENTAL, categories.STRUCTURE * categories.NUKE * categories.EXPERIMENTAL, categories.EXPERIMENTAL * categories.ORBITALSYSTEM, categories.STRUCTURE * categories.ARTILLERY * categories.TECH3, 
		categories.STRUCTURE * categories.NUKE * categories.TECH3, categories.EXPERIMENTAL * categories.ENERGYPRODUCTION * categories.STRUCTURE, categories.COMMAND, categories.EXPERIMENTAL * categories.MOBILE * categories.LAND, categories.TECH3 * categories.MASSFABRICATION,
		categories.TECH3 * categories.ENERGYPRODUCTION, categories.MASSPRODUCTION, categories.ENERGYPRODUCTION, categories.STRUCTURE * categories.STRATEGIC, categories.STRUCTURE * categories.DEFENSE * categories.TECH3, categories.STRUCTURE * categories.DEFENSE * categories.TECH2, categories.STRUCTURE * categories.FACTORY, categories.STRUCTURE, categories.ALLUNITS } )
        while aiBrain:PlatoonExists(self) do
            local target = false
            local blip = false
            while unit:GetTacticalSiloAmmoCount() < 1 or not target do
                WaitSeconds(7)
                target = false
                while not target do
                    #if aiBrain:GetCurrentEnemy() and aiBrain:GetCurrentEnemy():IsDefeated() then
                    #    aiBrain:PickEnemyLogic()
                    #end

                    target = AIUtils.AIFindBrainTargetInRangeSorian( aiBrain, self, 'Attack', maxRadius, atkPri, true )
					local newtarget
					if aiBrain.AttackPoints and table.getn(aiBrain.AttackPoints) > 0 then
						newtarget = AIUtils.AIFindPingTargetInRangeSorian( aiBrain, self, 'Artillery', maxRadius, atkPri, true )
						if newtarget then
							target = newtarget
						end
					end
                    if not target then
                        target = self:FindPrioritizedUnit('Attack', 'Enemy', true, unit:GetPosition(), maxRadius)
                    end
                    if target then
                        break
                    end
                    WaitSeconds(3)
                    if not aiBrain:PlatoonExists(self) then
                        return
                    end
                end
            end
            if not target:IsDead() then
                #LOG('*AI DEBUG: Firing Tactical Missile at enemy swine!')
				if EntityCategoryContains(categories.STRUCTURE, target) then
					IssueTactical({unit}, target)
				else
					targPos = SUtils.LeadTarget(self, target)
					if targPos then
						IssueTactical({unit}, targPos)
					end
				end
            end
            WaitSeconds(3)
        end
    end,

    AirHuntAI = function(self)
        self:Stop()
        local aiBrain = self:GetBrain()
        local armyIndex = aiBrain:GetArmyIndex()
        local target
        local blip
		local hadtarget = false
        while aiBrain:PlatoonExists(self) do
            if self:IsOpponentAIRunning() then
                target = self:FindClosestUnit('Attack', 'Enemy', true, categories.ALLUNITS - categories.WALL)
				local newtarget
				if aiBrain.T4ThreatFound['Land'] or aiBrain.T4ThreatFound['Naval'] or aiBrain.T4ThreatFound['Structure'] then
					newtarget = self:FindClosestUnit('Attack', 'Enemy', true, categories.EXPERIMENTAL * (categories.LAND + categories.NAVAL + categories.STRUCTURE + categories.ARTILLERY))
					if newtarget then
						target = newtarget
					end
				end
                if target then
                    blip = target:GetBlip(armyIndex)
                    self:Stop()
                    self:AggressiveMoveToLocation( table.copy(target:GetPosition()) )
					hadtarget = true
				elseif not target and hadtarget then
					local x,z = aiBrain:GetArmyStartPos()
					local position = AIUtils.RandomLocation(x,z)
					local safePath, reason = AIAttackUtils.PlatoonGenerateSafePathTo(aiBrain, 'Air', self:GetPlatoonPosition(), position, 200)
					if safePath then
						for _,p in safePath do
							self:MoveToLocation( p, false )
						end
					else
						self:MoveToLocation( position, false )
					end
					hadtarget = false
                end
            end
            WaitSeconds(17)
        end
    end,  

    FighterHuntAI = function(self)
        self:Stop()
        local aiBrain = self:GetBrain()
        local armyIndex = aiBrain:GetArmyIndex()
		local location = self.PlatoonData.LocationType or 'MAIN'
		local radius = self.PlatoonData.Radius or 100
        local target
        local blip
		local hadtarget = false
        while aiBrain:PlatoonExists(self) do
            if self:IsOpponentAIRunning() then
                target = self:FindClosestUnit('Attack', 'Enemy', true, categories.ALLUNITS - categories.WALL)
				local newtarget
				if aiBrain.T4ThreatFound['Air'] then
					newtarget = self:FindClosestUnit('Attack', 'Enemy', true, categories.EXPERIMENTAL * categories.AIR)
					if newtarget then
						target = newtarget
					end
				end
                if target and target:GetFractionComplete() == 1 then
                    blip = target:GetBlip(armyIndex)
                    self:Stop()
                    self:AggressiveMoveToLocation( table.copy(target:GetPosition()) )
					hadtarget = true
				elseif not target and hadtarget then
					for k,v in AIUtils.GetBasePatrolPoints(aiBrain, location, radius, 'Air') do
						self:Patrol(v)
					end
					hadtarget = false
					return self:GuardExperimentalSorian(self.FighterHuntAI)
				end
            end
            WaitSeconds(17)
        end
    end,	
          
    #-----------------------------------------------------
    #   Function: GuardMarkerSorian
    #   Args:
    #       platoon - platoon to run the AI
    #   Description:
    #       Will guard the location of a marker
    #   Returns:  
    #       nil
    #-----------------------------------------------------
    GuardMarkerSorian = function(self)
        local aiBrain = self:GetBrain()
        
        local platLoc = self:GetPlatoonPosition()        
        
        if not aiBrain:PlatoonExists(self) or not platLoc then
            return
        end
        
        #---------------------------------------------------------------------
        # Platoon Data
        #---------------------------------------------------------------------
        # type of marker to guard
        # Start location = 'Start Location'... see MarkerTemplates.lua for other types
        local markerType = self.PlatoonData.MarkerType or 'Expansion Area'

        # what should we look for for the first marker?  This can be 'Random',
        # 'Threat' or 'Closest'
        local moveFirst = self.PlatoonData.MoveFirst or 'Threat'
        
        # should our next move be no move be (same options as before) as well as 'None'
        # which will cause the platoon to guard the first location they get to
        local moveNext = self.PlatoonData.MoveNext or 'None'         

        # Minimum distance when looking for closest
        local avoidClosestRadius = self.PlatoonData.AvoidClosestRadius or 0        
        
        # set time to wait when guarding a location with moveNext = 'None'
        local guardTimer = self.PlatoonData.GuardTimer or 0
        
        # threat type to look at      
        local threatType = self.PlatoonData.ThreatType or 'AntiSurface'
        
        # should we look at our own threat or the enemy's
        local bSelfThreat = self.PlatoonData.SelfThreat or false
        
        # if true, look to guard highest threat, otherwise, 
        # guard the lowest threat specified                 
        local bFindHighestThreat = self.PlatoonData.FindHighestThreat or false 
        
        # minimum threat to look for
        local minThreatThreshold = self.PlatoonData.MinThreatThreshold or -1
        # maximum threat to look for
        local maxThreatThreshold = self.PlatoonData.MaxThreatThreshold  or 99999999
  
        # Avoid bases (true or false)
        local bAvoidBases = self.PlatoonData.AvoidBases or false
             
        # Radius around which to avoid the main base
        local avoidBasesRadius = self.PlatoonData.AvoidBasesRadius or 0
        
        # Use Aggresive Moves Only
        local bAggroMove = self.PlatoonData.AggressiveMove or false
        
        local PlatoonFormation = self.PlatoonData.UseFormation or 'NoFormation'
        #---------------------------------------------------------------------
         
           
        AIAttackUtils.GetMostRestrictiveLayer(self)
        self:SetPlatoonFormationOverride(PlatoonFormation)
        local markerLocations = AIUtils.AIGetMarkerLocations(aiBrain, markerType)
        
        local bestMarker = false
        
        if not self.LastMarker then
            self.LastMarker = {nil,nil}
        end
            
        # look for a random marker
        if moveFirst == 'Random' then
            if table.getn(markerLocations) <= 2 then
                self.LastMarker[1] = nil
                self.LastMarker[2] = nil
            end        	
            for _,marker in RandomIter(markerLocations) do
	            if table.getn(markerLocations) <= 2 then
	                self.LastMarker[1] = nil
	                self.LastMarker[2] = nil
	            end            	
                if self:AvoidsBases(marker.Position, bAvoidBases, avoidBasesRadius) then
            		if self.LastMarker[1] and marker.Position[1] == self.LastMarker[1][1] and marker.Position[3] == self.LastMarker[1][3] then
            		    continue                
            		end                        
            		if self.LastMarker[2] and marker.Position[1] == self.LastMarker[2][1] and marker.Position[3] == self.LastMarker[2][3] then
            		    continue                
            		end                    	
                    bestMarker = marker
                    break
                end
            end
        elseif moveFirst == 'Threat' then
            #Guard the closest least-defended marker
            local bestMarkerThreat = 0
            if not bFindHighestThreat then
                bestMarkerThreat = 99999999
            end
            
            local bestDistSq = 99999999
                      
             
            # find best threat at the closest distance
            for _,marker in markerLocations do
                local markerThreat
                if bSelfThreat then
                    markerThreat = aiBrain:GetThreatAtPosition( marker.Position, 0, true, threatType, aiBrain:GetArmyIndex())
                else
                    markerThreat = aiBrain:GetThreatAtPosition( marker.Position, 0, true, threatType)
                end
                local distSq = VDist2Sq(marker.Position[1], marker.Position[3], platLoc[1], platLoc[3])

                if markerThreat >= minThreatThreshold and markerThreat <= maxThreatThreshold then
                    if self:AvoidsBases(marker.Position, bAvoidBases, avoidBasesRadius) then
                        if self.IsBetterThreat(bFindHighestThreat, markerThreat, bestMarkerThreat) then
                            bestDistSq = distSq
                            bestMarker = marker
                            bestMarkerThreat = markerThreat
                        elseif markerThreat == bestMarkerThreat then
                            if distSq < bestDistSq then
                                bestDistSq = distSq
                                bestMarker = marker  
                                bestMarkerThreat = markerThreat  
                            end
                        end
                     end
                 end
            end
            
        else 
            # if we didn't want random or threat, assume closest (but avoid ping-ponging)
            local bestDistSq = 99999999
            if table.getn(markerLocations) <= 2 then
                self.LastMarker[1] = nil
                self.LastMarker[2] = nil
            end
            for _,marker in markerLocations do
                local distSq = VDist2Sq(marker.Position[1], marker.Position[3], platLoc[1], platLoc[3])
                if self:AvoidsBases(marker.Position, bAvoidBases, avoidBasesRadius) and distSq > (avoidClosestRadius * avoidClosestRadius) then
                    if distSq < bestDistSq then
                		if self.LastMarker[1] and marker.Position[1] == self.LastMarker[1][1] and marker.Position[3] == self.LastMarker[1][3] then
                		    continue                
                		end                        
                		if self.LastMarker[2] and marker.Position[1] == self.LastMarker[2][1] and marker.Position[3] == self.LastMarker[2][3] then
                		    continue                
                		end                      		
                        bestDistSq = distSq
                        bestMarker = marker 
                    end
                end
            end            
        end
        
        
        # did we find a threat?
		local usedTransports = false
        if bestMarker then
        	self.LastMarker[2] = self.LastMarker[1]
            self.LastMarker[1] = bestMarker.Position
            #LOG("GuardMarker: Attacking " .. bestMarker.Name)
            local path, reason = AIAttackUtils.PlatoonGenerateSafePathTo(aiBrain, self.MovementLayer, self:GetPlatoonPosition(), bestMarker.Position, 200)
			local success, bestGoalPos = AIAttackUtils.CheckPlatoonPathingEx(self, bestMarker.Position)
            IssueClearCommands(self:GetPlatoonUnits())
            if path then
				local position = self:GetPlatoonPosition()
				if not success or VDist2( position[1], position[3], bestMarker.Position[1], bestMarker.Position[3] ) > 512 then
					usedTransports = AIAttackUtils.SendPlatoonWithTransportsSorian(aiBrain, self, bestMarker.Position, true, false, true)
				elseif VDist2( position[1], position[3], bestMarker.Position[1], bestMarker.Position[3] ) > 256 then
					usedTransports = AIAttackUtils.SendPlatoonWithTransportsSorian(aiBrain, self, bestMarker.Position, false, false, false)
				end
				if not usedTransports then
					local pathLength = table.getn(path)
					for i=1, pathLength-1 do
						if bAggroMove then
							self:AggressiveMoveToLocation(path[i])
						else
							self:MoveToLocation(path[i], false)
						end
					end 
				end
            elseif (not path and reason == 'NoPath') then
                usedTransports = AIAttackUtils.SendPlatoonWithTransportsSorian(aiBrain, self, bestMarker.Position, true, false, true)
            else
                self:PlatoonDisband()
                return
            end
			
			if (not path or not success) and not usedTransports then
                self:PlatoonDisband()
                return
			end
            
            if moveNext == 'None' then
                # guard
                IssueGuard( self:GetPlatoonUnits(), bestMarker.Position )
                # guard forever
                if guardTimer <= 0 then return end
            else
                # otherwise, we're moving to the location
                self:AggressiveMoveToLocation(bestMarker.Position)
            end
            
            # wait till we get there
			local oldPlatPos = self:GetPlatoonPosition()
			local StuckCount = 0
            repeat
                WaitSeconds(5)    
                platLoc = self:GetPlatoonPosition()
				if VDist3(oldPlatPos, platLoc) < 1 then
					StuckCount = StuckCount + 1
				else
					StuckCount = 0
				end
				if StuckCount > 5 then
					return self:GuardMarker()
				end
				oldPlatPos = platLoc
            until VDist2Sq(platLoc[1], platLoc[3], bestMarker.Position[1], bestMarker.Position[3]) < 64 or not aiBrain:PlatoonExists(self)
            
            # if we're supposed to guard for some time
            if moveNext == 'None' then
                # this won't be 0... see above
                WaitSeconds(guardTimer)
                self:PlatoonDisband()
                return
            end
            
            if moveNext == 'Guard Base' then
                return self:GuardBaseSorian()
            end
            
            # we're there... wait here until we're done
            local numGround = aiBrain:GetNumUnitsAroundPoint( ( categories.LAND + categories.NAVAL + categories.STRUCTURE ), bestMarker.Position, 15, 'Enemy' )
            while numGround > 0 and aiBrain:PlatoonExists(self) do
                WaitSeconds(Random(5,10))
                numGround = aiBrain:GetNumUnitsAroundPoint( ( categories.LAND + categories.NAVAL + categories.STRUCTURE ), bestMarker.Position, 15, 'Enemy' )    
            end
            
            if not aiBrain:PlatoonExists(self) then
                return
            end
            
            # set our MoveFirst to our MoveNext
            self.PlatoonData.MoveFirst = moveNext
            return self:GuardMarker()
        else
            # no marker found, disband!
            self:PlatoonDisband()
        end               
    end,
    
	#-----------------------------------------------------
    #   Function: AirIntelToggle
    #   Args:
    #       self - platoon to run the AI
    #   Description:
    #       Turns on Air unit cloak/stealth.
    #   Returns:  
    #       nil
    #-----------------------------------------------------	
	AirIntelToggle = function(self)
		#LOG('*AI DEBUG: AirIntelToggle run')
		for k,v in self:GetPlatoonUnits() do        
			if v:TestToggleCaps('RULEUTC_StealthToggle') then
				v:SetScriptBit('RULEUTC_StealthToggle', false)
			end
		end
	end,
	
    GuardBaseSorian = function(self)
        self:Stop()
        local aiBrain = self:GetBrain()
        local armyIndex = aiBrain:GetArmyIndex()
        local target = false
        local basePosition = false

        if self.PlatoonData.LocationType and self.PlatoonData.LocationType != 'NOTMAIN' then
            basePosition = aiBrain.BuilderManagers[self.PlatoonData.LocationType].Position
        else
            basePosition = aiBrain:FindClosestBuilderManagerPosition(self:GetPlatoonPosition())
        end
        
        local guardRadius = self.PlatoonData.GuardRadius or 200
        
        while aiBrain:PlatoonExists(self) do
            if self:IsOpponentAIRunning() then
                target = self:FindClosestUnit('Attack', 'Enemy', true, categories.ALLUNITS - categories.WALL)
                if target and not target:IsDead() and VDist3( target:GetPosition(), self:GetPlatoonPosition() ) < guardRadius then
                    self:Stop()
                    self:AggressiveMoveToLocation( target:GetPosition() )
                elseif VDist3( basePosition, self:GetPlatoonPosition() ) > guardRadius then
					local position = AIUtils.RandomLocation(basePosition[1],basePosition[3])
                    self:Stop()
                    self:MoveToLocation( position, false )
                end
            end
            WaitSeconds(5)
        end
    end,
	
    NavalForceAISorian = function(self)
        self:Stop()
        local aiBrain = self:GetBrain()
        
        AIAttackUtils.GetMostRestrictiveLayer(self)
        
        local platoonUnits = self:GetPlatoonUnits()
        local numberOfUnitsInPlatoon = table.getn(platoonUnits)
        local oldNumberOfUnitsInPlatoon = numberOfUnitsInPlatoon
        local stuckCount = 0
        
        self.PlatoonAttackForce = true
        # formations have penalty for taking time to form up... not worth it here
        # maybe worth it if we micro
        #self:SetPlatoonFormationOverride('GrowthFormation')
        local PlatoonFormation = self.PlatoonData.UseFormation or 'No Formation'
        self:SetPlatoonFormationOverride(PlatoonFormation)
        
        for k,v in self:GetPlatoonUnits() do
            if v:IsDead() then
                continue
            end
            
            if v:GetCurrentLayer() == 'Sub' then
                continue
            end
            
            if v:TestCommandCaps('RULEUCC_Dive') then
                IssueDive( {v} )
            end
        end
		
		local maxRange, selectedWeaponArc, turretPitch = AIAttackUtils.GetNavalPlatoonMaxRangeSorian(aiBrain, self)
#		local quickReset = false

        while aiBrain:PlatoonExists(self) do
            local pos = self:GetPlatoonPosition() # update positions; prev position done at end of loop so not done first time  
            
            # if we can't get a position, then we must be dead
            if not pos then
                break
            end
            
            # pick out the enemy
            if aiBrain:GetCurrentEnemy() and aiBrain:GetCurrentEnemy():IsDefeated() then
                aiBrain:PickEnemyLogicSorian()
            end

            # merge with nearby platoons
			if aiBrain:GetThreatAtPosition( pos, 1, true, 'AntiSurface') < 1 then
				self:MergeWithNearbyPlatoonsSorian('NavalForceAISorian', 20)
			end

            # rebuild formation
            platoonUnits = self:GetPlatoonUnits()
            numberOfUnitsInPlatoon = table.getn(platoonUnits)
            # if we have a different number of units in our platoon, regather
            if (oldNumberOfUnitsInPlatoon != numberOfUnitsInPlatoon) and aiBrain:GetThreatAtPosition( pos, 1, true, 'AntiSurface') < 1 then
                self:StopAttack()
                self:SetPlatoonFormationOverride(PlatoonFormation)
				oldNumberOfUnitsInPlatoon = numberOfUnitsInPlatoon
			end
						
            local cmdQ = {} 
            # fill cmdQ with current command queue for each unit
            for k,v in platoonUnits do
                if not v:IsDead() then
                    local unitCmdQ = v:GetCommandQueue()
                    for cmdIdx,cmdVal in unitCmdQ do
                        table.insert(cmdQ, cmdVal)
                        break
                    end
                end
            end
			
			if (oldNumberOfUnitsInPlatoon != numberOfUnitsInPlatoon) then
				maxRange, selectedWeaponArc, turretPitch = AIAttackUtils.GetNavalPlatoonMaxRangeSorian(aiBrain, self)
			end
			
			if not maxRange then maxRange = 50 end

            # if we're on our final push through to the destination, and we find a unit close to our destination
            #local closestTarget = self:FindClosestUnit( 'attack', 'enemy', true, categories.ALLUNITS )
			local closestTarget = SUtils.FindClosestUnitPosToAttack( aiBrain, self, 'attack', maxRange + 20, categories.ALLUNITS - categories.AIR - categories.WALL, selectedWeaponArc, turretPitch )
            local nearDest = false
            local oldPathSize = table.getn(self.LastAttackDestination)

            if self.LastAttackDestination then
                nearDest = oldPathSize == 0 or VDist3(self.LastAttackDestination[oldPathSize], pos) < maxRange + 20
            end
            
            # if we're near our destination and we have a unit closeby to kill, kill it
            if table.getn(cmdQ) <= 1 and closestTarget and nearDest then
                self:StopAttack()
                if PlatoonFormation != 'No Formation' then
					self:AggressiveMoveToLocation(closestTarget)
					#IssueFormAttack(platoonUnits, closestTarget, PlatoonFormation, 0)
					#self:AttackTarget(closestTarget)
					#IssueAttack(platoonUnits, closestTarget)
                else
					self:AggressiveMoveToLocation(closestTarget)
					#IssueFormAttack(platoonUnits, closestTarget, PlatoonFormation, 0)
					#self:AttackTarget(closestTarget)
					#IssueAttack(platoonUnits, closestTarget)
                end
                cmdQ = {1}
#				quickReset = true
			# if we have a target and can attack it, attack!
			elseif closestTarget then
				self:StopAttack()
				if PlatoonFormation != 'No Formation' then
					self:AggressiveMoveToLocation(closestTarget)
					#IssueFormAttack(platoonUnits, closestTarget, PlatoonFormation, 0)
					#self:AttackTarget(closestTarget)
					#IssueAttack(platoonUnits, closestTarget)
				else
					self:AggressiveMoveToLocation(closestTarget)
					#IssueFormAttack(platoonUnits, closestTarget, PlatoonFormation, 0)
					#self:AttackTarget(closestTarget)
					#IssueAttack(platoonUnits, closestTarget)
				end
				cmdQ = {1}
#				quickReset = true
            # if we have nothing to do, but still have a path (because of one of the above)
			elseif table.getn(cmdQ) == 0 and oldPathSize > 0 then
				self.LastAttackDestination = nil
                self:StopAttack()
                cmdQ = AIAttackUtils.AIPlatoonNavalAttackVectorSorian( aiBrain, self )
                stuckCount = 0
            # if we have nothing to do, try finding something to do        
            elseif table.getn(cmdQ) == 0 then
                self:StopAttack()
                cmdQ = AIAttackUtils.AIPlatoonNavalAttackVectorSorian( aiBrain, self )
                stuckCount = 0
            # if we've been stuck and unable to reach next marker? Ignore nearby stuff and pick another target  
            elseif self.LastPosition and VDist2Sq(self.LastPosition[1], self.LastPosition[3], pos[1], pos[3]) < ( self.PlatoonData.StuckDistance or 50) then
                stuckCount = stuckCount + 1
                if stuckCount >= 2 then               
                    self:StopAttack()
					self.LastAttackDestination = nil
                    cmdQ = AIAttackUtils.AIPlatoonNavalAttackVectorSorian( aiBrain, self )
                    stuckCount = 0
                end
            else
                stuckCount = 0
            end
            
            self.LastPosition = pos
            
            #wait a while if we're stuck so that we have a better chance to move
#			if quickReset then
#				quickReset = false
#				WaitSeconds(6)
#			else
				WaitSeconds(Random(5,11) + 2 * stuckCount)
#			end
        end
    end,
	
    AttackForceAI = function(self)
        self:Stop()
        local aiBrain = self:GetBrain()
        
        # get units together
        if not self:GatherUnits() then
            return
        end
        
        # Setup the formation based on platoon functionality
        
        local enemy = aiBrain:GetCurrentEnemy()

        local platoonUnits = self:GetPlatoonUnits()
        local numberOfUnitsInPlatoon = table.getn(platoonUnits)
        local oldNumberOfUnitsInPlatoon = numberOfUnitsInPlatoon
        local stuckCount = 0
        
        self.PlatoonAttackForce = true
        # formations have penalty for taking time to form up... not worth it here
        # maybe worth it if we micro
        #self:SetPlatoonFormationOverride('GrowthFormation')
		local bAggro = self.PlatoonData.AggressiveMove or false
        local PlatoonFormation = self.PlatoonData.UseFormation or 'NoFormation'
        self:SetPlatoonFormationOverride(PlatoonFormation)
        
        while aiBrain:PlatoonExists(self) do
            local pos = self:GetPlatoonPosition() # update positions; prev position done at end of loop so not done first time  
            
            # if we can't get a position, then we must be dead
            if not pos then
                break
            end
            
            
            # if we're using a transport, wait for a while
            if self.UsingTransport then
                WaitSeconds(10)
                continue
            end
                        
            # pick out the enemy
            if aiBrain:GetCurrentEnemy() and aiBrain:GetCurrentEnemy():IsDefeated() then
                aiBrain:PickEnemyLogic()
            end

            # merge with nearby platoons
            self:MergeWithNearbyPlatoons('AttackForceAI', 10)

            # rebuild formation
            platoonUnits = self:GetPlatoonUnits()
            numberOfUnitsInPlatoon = table.getn(platoonUnits)
            # if we have a different number of units in our platoon, regather
            if (oldNumberOfUnitsInPlatoon != numberOfUnitsInPlatoon) then
                self:StopAttack()
                self:SetPlatoonFormationOverride(PlatoonFormation)
            end
            oldNumberOfUnitsInPlatoon = numberOfUnitsInPlatoon

            # deal with lost-puppy transports
            local strayTransports = {}
            for k,v in platoonUnits do
                if EntityCategoryContains(categories.TRANSPORTATION, v) then
                    table.insert(strayTransports, v)
                end 
            end
            if table.getn(strayTransports) > 0 then
                local dropPoint = pos
                dropPoint[1] = dropPoint[1] + Random(-3, 3)
                dropPoint[3] = dropPoint[3] + Random(-3, 3)
                IssueTransportUnload( strayTransports, dropPoint )
                WaitSeconds(10)
                local strayTransports = {}
                for k,v in platoonUnits do
                    local parent = v:GetParent()
                    if parent and EntityCategoryContains(categories.TRANSPORTATION, parent) then
                        table.insert(strayTransports, parent)
                        break
                    end 
                end
                if table.getn(strayTransports) > 0 then
                    local MAIN = aiBrain.BuilderManagers.MAIN
                    if MAIN then
                        dropPoint = MAIN.Position
                        IssueTransportUnload( strayTransports, dropPoint )
                        WaitSeconds(30)
                    end
                end
                self.UsingTransport = false
                AIUtils.ReturnTransportsToPool( strayTransports, true )
                platoonUnits = self:GetPlatoonUnits()
            end    
    

        	#Disband platoon if it's all air units, so they can be picked up by another platoon
            local mySurfaceThreat = AIAttackUtils.GetSurfaceThreatOfUnits(self)
            if mySurfaceThreat == 0 and AIAttackUtils.GetAirThreatOfUnits(self) > 0 then
                self:PlatoonDisband()
                return
            end
                        
            local cmdQ = {} 
            # fill cmdQ with current command queue for each unit
            for k,v in platoonUnits do
                if not v:IsDead() then
                    local unitCmdQ = v:GetCommandQueue()
                    for cmdIdx,cmdVal in unitCmdQ do
                        table.insert(cmdQ, cmdVal)
                        break
                    end
                end
            end            
            
            # if we're on our final push through to the destination, and we find a unit close to our destination
            local closestTarget = self:FindClosestUnit( 'attack', 'enemy', true, categories.ALLUNITS )
            local nearDest = false
            local oldPathSize = table.getn(self.LastAttackDestination)
            if self.LastAttackDestination then
                nearDest = oldPathSize == 0 or VDist3(self.LastAttackDestination[oldPathSize], pos) < 20
            end
            
            # if we're near our destination and we have a unit closeby to kill, kill it
            if table.getn(cmdQ) <= 1 and closestTarget and VDist3( closestTarget:GetPosition(), pos ) < 20 and nearDest then
                self:StopAttack()
                if PlatoonFormation != 'No Formation' then
                    IssueFormAttack(platoonUnits, closestTarget, PlatoonFormation, 0)
                else
                    IssueAttack(platoonUnits, closestTarget)
                end
                cmdQ = {1}
            # if we have nothing to do, try finding something to do        
            elseif table.getn(cmdQ) == 0 then
                self:StopAttack()
                cmdQ = AIAttackUtils.AIPlatoonSquadAttackVector( aiBrain, self, bAggro )
                stuckCount = 0
            # if we've been stuck and unable to reach next marker? Ignore nearby stuff and pick another target  
            elseif self.LastPosition and VDist2Sq(self.LastPosition[1], self.LastPosition[3], pos[1], pos[3]) < ( self.PlatoonData.StuckDistance or 16) then
                stuckCount = stuckCount + 1
                if stuckCount >= 2 then               
                    self:StopAttack()
                    cmdQ = AIAttackUtils.AIPlatoonSquadAttackVector( aiBrain, self, bAggro )
                    stuckCount = 0
                end
            else
                stuckCount = 0
            end
            
            self.LastPosition = pos
            
            if table.getn(cmdQ) == 0 then
                # if we have a low threat value, then go and defend an engineer or a base
                if mySurfaceThreat < 4  
                    and mySurfaceThreat > 0 
                    and not self.PlatoonData.NeverGuard 
                    and not (self.PlatoonData.NeverGuardEngineers and self.PlatoonData.NeverGuardBases)
                then
                    #LOG('*DEBUG: Trying to guard')
                    return self:GuardEngineer(self.AttackForceAI)
                end
                
                # we have nothing to do, so find the nearest base and disband
                if not self.PlatoonData.NeverMerge then
                    return self:ReturnToBaseAI()
                end
                WaitSeconds(5)
            else
                # wait a little longer if we're stuck so that we have a better chance to move
                WaitSeconds(Random(5,11) + 2 * stuckCount)
            end
        end
    end,
	
	GuardExperimentalSorian = function(self, nextAIFunc)
		local aiBrain = self:GetBrain()
        
		if not aiBrain:PlatoonExists(self) or not self:GetPlatoonPosition() then
			return
		end
		
		AIAttackUtils.GetMostRestrictiveLayer(self)
		
		local unitToGuard = false
		local units = aiBrain:GetListOfUnits( categories.MOBILE * categories.EXPERIMENTAL - categories.url0401, false )
		for k,v in units do
			if (self.MovementLayer == 'Air' and SUtils.GetGuardCount(aiBrain, v, categories.AIR) < 10) or ((self.MovementLayer == 'Land' or self.MovementLayer == 'Amphibious') and EntityCategoryContains(categories.LAND, v) and SUtils.GetGuardCount(aiBrain, v, categories.LAND) < 10) then #not v.BeingGuarded then
				unitToGuard = v
				#v.BeingGuarded = true
			end
		end

		local guardTime = 0
		if unitToGuard and not unitToGuard:IsDead() then
			IssueGuard(self:GetPlatoonUnits(), unitToGuard)

			while aiBrain:PlatoonExists(self) and not unitToGuard:IsDead() do
				guardTime = guardTime + 5
				WaitSeconds(5)
                    
				if self.PlatoonData.T4GuardTimeLimit and guardTime >= self.PlatoonData.T4GuardTimeLimit 
				or (not unitToGuard:IsDead() and unitToGuard:GetCurrentLayer() == 'Seabed' and self.MovementLayer == 'Land') then
					break
				end
			end
		end
		
        ##Tail call into the next ai function
        WaitSeconds(1)
        if type(nextAIFunc) == 'function' then
            return nextAIFunc(self)
        end
        
        return self:GuardExperimentalSorian(nextAIFunc)
    end,
	
    ReclaimStructuresAI = function(self)
        self:Stop()
        local aiBrain = self:GetBrain()
		local data = self.PlatoonData
        local radius = aiBrain:PBMGetLocationRadius(data.Location)
		local categories = data.Reclaim
        local counter = 0
        while aiBrain:PlatoonExists(self) do
            local unitPos = self:GetPlatoonPosition()
			local reclaimunit = false
			local distance = false
			for num,cat in categories do
				local reclaimcat = ParseEntityCategory(cat)
				local reclaimables = aiBrain:GetListOfUnits( reclaimcat, false )
				for k,v in reclaimables do
					if not v:IsDead() and (not reclaimunit or VDist3(unitPos, v:GetPosition()) < distance) then
						reclaimunit = v
						distance = VDist3(unitPos, v:GetPosition())
					end
				end
				if reclaimunit then break end
			end
            if reclaimunit and not reclaimunit:IsDead() then
                counter = 0
                IssueReclaim( self:GetPlatoonUnits(), reclaimunit )
                local allIdle
                repeat
                    WaitSeconds(2)
                    if not aiBrain:PlatoonExists(self) then
                        return
                    end
                    allIdle = true
                    for k,v in self:GetPlatoonUnits() do
                        if not v:IsDead() and not v:IsIdleState() then
                            allIdle = false
                            break
                        end
                    end
                until allIdle
            elseif not reclaimunit or counter >= 5 then
                self:PlatoonDisband()
            else
                counter = counter + 1
                WaitSeconds(5)
            end
        end
    end,
	
    ReclaimAISorian = function(self)
        self:Stop()
        local aiBrain = self:GetBrain()
        local locationType = self.PlatoonData.LocationType
        local timeAlive = 0
		local stuckCount = 0
        local closest, entType, closeDist
        local oldClosest
		local eng = self:GetPlatoonUnits()[1]
		if not aiBrain.BadReclaimables then
			aiBrain.BadReclaimables = {}
		end
        while aiBrain:PlatoonExists(self) do
            local massRatio = aiBrain:GetEconomyStoredRatio('MASS')
            local energyRatio = aiBrain:GetEconomyStoredRatio('ENERGY')
            local massFirst = true
            if energyRatio < massRatio then
                massFirst = false
            end

            local ents = AIUtils.AIGetReclaimablesAroundLocation( aiBrain, locationType )
            if not ents or table.getn( ents ) == 0 then
                WaitTicks(1)
                self:PlatoonDisband()
            end
			local reclaimables = { Mass = {}, Energy = {} }
            for k,v in ents do
                if v.MassReclaim and v.MassReclaim > 0 then
                    table.insert( reclaimables.Mass, v )
                elseif v.EnergyReclaim and v.EnergyReclaim > 0 then
                    table.insert( reclaimables.Energy, v )
                end
            end
            
            local unitPos = self:GetPlatoonPosition()
            if not unitPos then break end
            local recPos = nil
            closest = false
			for num, recType in reclaimables do
				for k, v in recType do
					recPos = v:GetPosition()
					if not recPos then 
						WaitTicks(1)
						self:PlatoonDisband()
					end
					if not (unitPos[1] and unitPos[3] and recPos[1] and recPos[3]) then return end
					local tempDist = VDist2( unitPos[1], unitPos[3], recPos[1], recPos[3] )
					# We don't want any reclaimables super close to us
					#if not aiBrain.BadReclaimables[v] and aiBrain.BadReclaimables[v] != false and VDist3(eng:GetPosition(), recPos) > 10 and not eng:CanPathTo( v:GetPosition() ) then
					#	aiBrain.BadReclaimables[v] = true
					#else
					#	aiBrain.BadReclaimables[v] = false
					#end
					if ( ( not closest or tempDist < closeDist ) and ( not oldClosest or closest != oldClosest ) ) and not aiBrain.BadReclaimables[v] then
						closest = v
						entType = num
						closeDist = tempDist
					end
				end
                if num == 'Mass' and closest and massFirst then
                    break
                end
			end
			
            if closest and (( entType == 'Mass' and massRatio < .9 ) or ( entType == 'Energy' and energyRatio < .9 )) then
				if closest == oldClosest then
					stuckCount = stuckCount + 1
				else
					stuckCount = 0
				end
                oldClosest = closest
                IssueClearCommands( self:GetPlatoonUnits() )
				IssueReclaim( self:GetPlatoonUnits(), closest )
                local count = 0
				local allIdle = false
				if stuckCount > 1 then
					stuckCount = 0
					aiBrain.BadReclaimables[closest] = true
					WaitSeconds(10)
					count = 60
				end
                repeat
                    WaitSeconds(2)
                    if not aiBrain:PlatoonExists(self) then
                        return
                    end
                    timeAlive = timeAlive + 2
                    count = count + 1
                    if self.PlatoonData.ReclaimTime and timeAlive >= self.PlatoonData.ReclaimTime then
						local basePosition = aiBrain.BuilderManagers[locationType].Position
						local location = AIUtils.RandomLocation(basePosition[1],basePosition[3])
						self:MoveToLocation( location, false )
						WaitSeconds(10)
                        self:PlatoonDisband()
                        return
                    end
					allIdle = true
					if not eng:IsIdleState() then allIdle = false end
                until allIdle or count >= 60
            else
				local basePosition = aiBrain.BuilderManagers[locationType].Position
                local location = AIUtils.RandomLocation(basePosition[1],basePosition[3])
                self:MoveToLocation( location, false )
				WaitSeconds(10)
                self:PlatoonDisband()
            end
        end
    end,
	
    RepairAI = function(self)
        if not self.PlatoonData or not self.PlatoonData.LocationType then
            self:PlatoonDisband()
        end
		local eng = self:GetPlatoonUnits()[1]
		#LOG('*AI DEBUG: Engineer Repairing')
        local aiBrain = self:GetBrain()
		local engineerManager = aiBrain.BuilderManagers[self.PlatoonData.LocationType].EngineerManager
        local Structures = AIUtils.GetOwnUnitsAroundPoint( aiBrain, categories.STRUCTURE - (categories.TECH1 - categories.FACTORY), engineerManager:GetLocationCoords(), engineerManager:GetLocationRadius() )
        for k,v in Structures do
            if not v:IsDead() and v:GetHealthPercent() < .8 then
                self:Stop()
                IssueRepair( self:GetPlatoonUnits(), v )
				break
            end
        end
		local count = 0
        repeat
            WaitSeconds(2)
            if not aiBrain:PlatoonExists(self) then
				return
            end
            count = count + 1
			allIdle = true
			if not eng:IsIdleState() then allIdle = false end
        until allIdle or count >= 30
        self:PlatoonDisband()
    end,
	
    SorianManagerEngineerAssistAI = function(self)
        local aiBrain = self:GetBrain()
		local assistData = self.PlatoonData.Assist
		local beingBuilt = false
        self:SorianEconAssistBody()
        WaitSeconds(self.PlatoonData.AssistData.Time or 60)
		local eng = self:GetPlatoonUnits()[1]
		if eng:GetGuardedUnit() then
			beingBuilt = eng:GetGuardedUnit()
		end
		if beingBuilt and assistData.AssistUntilFinished then
			while beingBuilt:IsUnitState('Building') or beingBuilt:IsUnitState('Upgrading') do
				WaitSeconds(5)
			end
		end
        if not aiBrain:PlatoonExists(self) then
            return
        end
        self.AssistPlatoon = nil
        self:PlatoonDisband()
    end,
    
    SorianEconAssistBody = function(self)
        local eng = self:GetPlatoonUnits()[1]
        if not eng then
            self:PlatoonDisband()
            return
        end
        local aiBrain = self:GetBrain()
        local assistData = self.PlatoonData.Assist
        local assistee = false
        
        eng.AssistPlatoon = self
        
        if not assistData.AssistLocation or not assistData.AssisteeType then
            WARN('*AI WARNING: Disbanding Assist platoon that does not have either AssistLocation or AssisteeType')
            self:PlatoonDisband()
        end
        
        local beingBuilt = assistData.BeingBuiltCategories or { 'ALLUNITS' }
        
        local assisteeCat = assistData.AssisteeCategory or categories.ALLUNITS
        if type(assisteeCat) == 'string' then
            assisteeCat = ParseEntityCategory( assisteeCat )
        end

        # loop through different categories we are looking for
        for _,catString in beingBuilt do
            # Track all valid units in the assist list so we can load balance for factories
            
            local category = ParseEntityCategory( catString )
        
            local assistList = AIUtils.GetAssisteesSorian( aiBrain, assistData.AssistLocation, assistData.AssisteeType, category, assisteeCat )

            if table.getn(assistList) > 0 then
                # only have one unit in the list; assist it
                if table.getn(assistList) == 1 then
                    assistee = assistList[1]
                    break
                else
                    # Find the unit with the least number of assisters; assist it
                    local lowNum = false
                    local lowUnit = false
                    for k,v in assistList do
                        if not lowNum or table.getn( v:GetGuards() ) < lowNum then
                            lowNum = v:GetGuards()
                            lowUnit = v
                        end
                    end
                    assistee = lowUnit
                    break
                end
            end
        end
        # assist unit
        if assistee  then
            self:Stop()
            eng.AssistSet = true
            IssueGuard( {eng}, assistee )
        else
            self.AssistPlatoon = nil
            self:PlatoonDisband()
        end
    end,
	
    ManagerEngineerFindUnfinished = function(self)
        local aiBrain = self:GetBrain()
		local beingBuilt = false
        self:EconUnfinishedBody()
		WaitSeconds(20)
		local eng = self:GetPlatoonUnits()[1]
		if eng:GetUnitBeingBuilt() then
			beingBuilt = eng:GetUnitBeingBuilt()
		end
		if beingBuilt then
			while not beingBuilt:BeenDestroyed() and beingBuilt:GetFractionComplete() < 1 do
				WaitSeconds(5)
			end
		end
        if not aiBrain:PlatoonExists(self) then
            return
        end
        #self.AssistPlatoon = nil
        self:PlatoonDisband()
    end,

    EconUnfinishedBody = function(self)
        local eng = self:GetPlatoonUnits()[1]
        if not eng then
            self:PlatoonDisband()
            return
        end
        local aiBrain = self:GetBrain()
        local assistData = self.PlatoonData.Assist
        local assistee = false
        
        #eng.AssistPlatoon = self
        
        if not assistData.AssistLocation then
            WARN('*AI WARNING: Disbanding EconUnfinishedBody platoon that does not have either AssistLocation')
            self:PlatoonDisband()
        end
        
        local beingBuilt = assistData.BeingBuiltCategories or { 'ALLUNITS' }
        
        # loop through different categories we are looking for
        for _,catString in beingBuilt do
            # Track all valid units in the assist list so we can load balance for factories
            
            local category = ParseEntityCategory( catString )
        
            local assistList = SUtils.FindUnfinishedUnits( aiBrain, assistData.AssistLocation, category )

			if assistList then
				assistee = assistList
				break
            end
        end
        # assist unit
        if assistee then
            self:Stop()
            eng.AssistSet = true
            IssueGuard( {eng}, assistee )
        else
            #self.AssistPlatoon = nil
            self:PlatoonDisband()
        end
    end,
	
    ManagerEngineerFindLowShield = function(self)
        local aiBrain = self:GetBrain()
        self:EconDamagedShield()
		WaitSeconds(60)
        if not aiBrain:PlatoonExists(self) then
            return
        end
        #self.AssistPlatoon = nil
        self:PlatoonDisband()
    end,

    EconDamagedShield = function(self)
        local eng = self:GetPlatoonUnits()[1]
        if not eng then
            self:PlatoonDisband()
            return
        end
        local aiBrain = self:GetBrain()
        local assistData = self.PlatoonData.Assist
        local assistee = false
        
        #eng.AssistPlatoon = self
        
        if not assistData.AssistLocation then
            WARN('*AI WARNING: Disbanding ManagerEngineerFindLowShield platoon that does not have either AssistLocation')
            self:PlatoonDisband()
        end
        
        local beingBuilt = assistData.BeingBuiltCategories or { 'ALLUNITS' }
        
        # loop through different categories we are looking for
        for _,catString in beingBuilt do
            # Track all valid units in the assist list so we can load balance for factories
            
            local category = ParseEntityCategory( catString )
        
            local assistList = SUtils.FindDamagedShield( aiBrain, assistData.AssistLocation, category )

			if assistList then
				assistee = assistList
				break
            end
        end
        # assist unit
        if assistee then
            self:Stop()
            eng.AssistSet = true
            IssueGuard( {eng}, assistee )
        else
            #self.AssistPlatoon = nil
            self:PlatoonDisband()
        end
    end,
	
    LandScoutingAISorian = function(self)
        AIAttackUtils.GetMostRestrictiveLayer(self)
        
        local aiBrain = self:GetBrain()
        local scout = self:GetPlatoonUnits()[1]
        
        aiBrain:BuildScoutLocationsSorian()
        
        #If we have cloaking (are cybran), then turn on our cloaking
        if self.PlatoonData.UseCloak and scout:TestToggleCaps('RULEUTC_CloakToggle') then
			scout:SetScriptBit('RULEUTC_CloakToggle', false)
        end
               
        while not scout:IsDead() do
            #Head towards the the area that has not had a scout sent to it in a while           
            local targetData = false
            
            #For every scouts we send to all opponents, send one to scout a low pri area.
            if aiBrain.IntelData.HiPriScouts < aiBrain.NumOpponents and table.getn(aiBrain.InterestList.HighPriority) > 0 then
                targetData = aiBrain.InterestList.HighPriority[1]
                aiBrain.IntelData.HiPriScouts = aiBrain.IntelData.HiPriScouts + 1
                targetData.LastScouted = GetGameTimeSeconds()
                
                aiBrain:SortScoutingAreas(aiBrain.InterestList.HighPriority)
                
            elseif table.getn(aiBrain.InterestList.LowPriority) > 0 then
                targetData = aiBrain.InterestList.LowPriority[1]
                aiBrain.IntelData.HiPriScouts = 0
                targetData.LastScouted = GetGameTimeSeconds()
                
                aiBrain:SortScoutingAreas(aiBrain.InterestList.LowPriority)
            else
                #Reset number of scoutings and start over
                aiBrain.IntelData.HiPriScouts = 0
            end
            
            #Is there someplace we should scout?
            if targetData then
                #Can we get there safely?
                local path, reason = AIAttackUtils.PlatoonGenerateSafePathTo(aiBrain, self.MovementLayer, scout:GetPosition(), targetData.Position, 100)
                
                IssueClearCommands(self)

                if path then
                    local pathLength = table.getn(path)
                    for i=1, pathLength-1 do
                        self:MoveToLocation(path[i], false)
                    end 
                end

                self:MoveToLocation(targetData.Position, false)  
                
                #Scout until we reach our destination
                while not scout:IsDead() and not scout:IsIdleState() do                                       
                    WaitSeconds(2.5)
                end
            end
            
            WaitSeconds(1)
        end
    end,
	
    AirScoutingAISorian = function(self)
        
        local aiBrain = self:GetBrain()
        local scout = self:GetPlatoonUnits()[1]
		local badScouting = false
        
        aiBrain:BuildScoutLocationsSorian()
        
        if scout:TestToggleCaps('RULEUTC_CloakToggle') then
			scout:SetScriptBit('RULEUTC_CloakToggle', false)
        end
        
        while not scout:IsDead() do
            local targetArea = false
            local highPri = false
            
            local mustScoutArea, mustScoutIndex = aiBrain:GetUntaggedMustScoutArea()
            local unknownThreats = aiBrain:GetThreatsAroundPosition(scout:GetPosition(), 16, true, 'Unknown')
            
            #1) If we have any "must scout" (manually added) locations that have not been scouted yet, then scout them
            if mustScoutArea then
                mustScoutArea.TaggedBy = scout
                targetArea = mustScoutArea.Position
            
            #2) Scout "unknown threat" areas with a threat higher than 25
            elseif table.getn(unknownThreats) > 0 and unknownThreats[1][3] > 25 then
                aiBrain:AddScoutArea({unknownThreats[1][1], 0, unknownThreats[1][2]})
            
            #3) Scout high priority locations    
            elseif aiBrain.IntelData.AirHiPriScouts < aiBrain.NumOpponents and aiBrain.IntelData.AirLowPriScouts < 1 
            and table.getn(aiBrain.InterestList.HighPriority) > 0 then
                aiBrain.IntelData.AirHiPriScouts = aiBrain.IntelData.AirHiPriScouts + 1
                
                highPri = true
                
                targetData = aiBrain.InterestList.HighPriority[1]
                targetData.LastScouted = GetGameTimeSeconds()
                targetArea = targetData.Position
                
                aiBrain:SortScoutingAreas(aiBrain.InterestList.HighPriority)
                
            #4) Every time we scout NumOpponents number of high priority locations, scout a low priority location               
            elseif aiBrain.IntelData.AirLowPriScouts < 1 and table.getn(aiBrain.InterestList.LowPriority) > 0 then
                aiBrain.IntelData.AirHiPriScouts = 0
                aiBrain.IntelData.AirLowPriScouts = aiBrain.IntelData.AirLowPriScouts + 1
                
                targetData = aiBrain.InterestList.LowPriority[1]
                targetData.LastScouted = GetGameTimeSeconds()
                targetArea = targetData.Position
                
                aiBrain:SortScoutingAreas(aiBrain.InterestList.LowPriority)
            else
                #Reset number of scoutings and start over
                aiBrain.IntelData.AirLowPriScouts = 0
                aiBrain.IntelData.AirHiPriScouts = 0
            end
            
            #Air scout do scoutings.
            if targetArea then
				badScouting = false
                self:Stop()
                
                local vec = self:DoAirScoutVecs(scout, targetArea)
                
                while not scout:IsDead() and not scout:IsIdleState() do                   
                    
                    #If we're close enough...
                    if VDist2Sq(vec[1], vec[3], scout:GetPosition()[1], scout:GetPosition()[3]) < 15625 then
                        if mustScoutArea then
                            #Untag and remove
                            for idx,loc in aiBrain.InterestList.MustScout do
                                if loc == mustScoutArea then
                                   table.remove(aiBrain.InterestList.MustScout, idx)
                                   break 
                                end
                            end
                        end
                        #Break within 125 ogrids of destination so we don't decelerate trying to stop on the waypoint.
                        break
                    end
                    
                    if VDist3( scout:GetPosition(), targetArea ) < 25 then
                        break
                    end

                    WaitSeconds(5)
                end
            elseif not badScouting then
				self:Stop()
				badScouting = true
				markers = AIUtils.AIGetMarkerLocations( aiBrain, 'Combat Zone' )
				if markers and table.getn( markers ) > 0 then
					local ScoutPath = {}
					local MarkerCount = table.getn( markers )
					for i = 1, MarkerCount do
						rand = Random( 1, MarkerCount + 1 - i )
						table.insert( ScoutPath, markers[rand] )
						table.remove( markers, rand )
					end
					for k, v in ScoutPath do
						self:Patrol( v.Position)
					end
				end
                WaitSeconds(1)
            end
            WaitTicks(1)
        end
    end,
	
    ScoutingAISorian = function(self)
        AIAttackUtils.GetMostRestrictiveLayer(self)
        
        if self.MovementLayer == 'Air' then 
            return self:AirScoutingAISorian() 
        else 
            return self:LandScoutingAISorian()
        end
    end,
	
    NavalHuntAI = function(self)
        self:Stop()
        local aiBrain = self:GetBrain()
        local armyIndex = aiBrain:GetArmyIndex()
        local target
        local blip
		local cmd = false
		local platoonUnits = self:GetPlatoonUnits()
        local PlatoonFormation = self.PlatoonData.UseFormation or 'NoFormation'
        self:SetPlatoonFormationOverride(PlatoonFormation)
        local atkPri = { 'SPECIALHIGHPRI', 'STRUCTURE ANTINAVY', 'MOBILE NAVAL', 'STRUCTURE NAVAL', 'COMMAND', 'EXPERIMENTAL', 'STRUCTURE STRATEGIC EXPERIMENTAL', 'ARTILLERY EXPERIMENTAL', 'STRUCTURE ARTILLERY TECH3', 'STRUCTURE NUKE TECH3', 'STRUCTURE ANTIMISSILE SILO', 
							'STRUCTURE DEFENSE DIRECTFIRE', 'TECH3 MASSFABRICATION', 'TECH3 ENERGYPRODUCTION', 'STRUCTURE STRATEGIC', 'STRUCTURE DEFENSE', 'STRUCTURE', 'MOBILE', 'SPECIALLOWPRI', 'ALLUNITS' }
        local atkPriTable = {}
        for k,v in atkPri do
            table.insert( atkPriTable, ParseEntityCategory( v ) )
        end
        self:SetPrioritizedTargetList( 'Attack', atkPriTable )
        local maxRadius = 6000
        for k,v in platoonUnits do

            if v:IsDead() then
                continue
            end
            
            if v:GetCurrentLayer() == 'Sub' then
                continue
            end
            
            if v:TestCommandCaps('RULEUCC_Dive') and v:GetUnitId() != 'uas0401' then
                IssueDive( {v} )
            end
        end
		WaitSeconds(5)
        while aiBrain:PlatoonExists(self) do
            if self:IsOpponentAIRunning() then
				target = AIUtils.AIFindBrainTargetInRangeSorian( aiBrain, self, 'Attack', maxRadius, atkPri)
                if target then
                    blip = target:GetBlip(armyIndex)
                    self:Stop()
					cmd = self:AggressiveMoveToLocation(target:GetPosition())
				end
				WaitSeconds(1)
				if (not cmd or not self:IsCommandsActive( cmd )) then
					target = self:FindClosestUnit('Attack', 'Enemy', true, categories.ALLUNITS - categories.WALL)
					if target then
						blip = target:GetBlip(armyIndex)
						self:Stop()
						cmd = self:AggressiveMoveToLocation(target:GetPosition())
					else
						local scoutPath = {}
						scoutPath = AIUtils.AIGetSortedNavalLocations(self:GetBrain())
						for k, v in scoutPath do
							self:Patrol(v)
						end
					end
				end
            end
            WaitSeconds(17)
        end
    end,
	
    HuntAISorian = function(self)
        self:Stop()
        local aiBrain = self:GetBrain()
        local armyIndex = aiBrain:GetArmyIndex()
        local target
        local blip
		local platoonUnits = self:GetPlatoonUnits()
        local PlatoonFormation = self.PlatoonData.UseFormation or 'NoFormation'
        self:SetPlatoonFormationOverride(PlatoonFormation)
        while aiBrain:PlatoonExists(self) do
            if self:IsOpponentAIRunning() then
                target = self:FindClosestUnit('Attack', 'Enemy', true, categories.ALLUNITS - categories.WALL - categories.AIR - categories.NAVAL)
                if target then
                    blip = target:GetBlip(armyIndex)
                    self:Stop()
					if PlatoonFormation != 'NoFormation' then
						#IssueFormAttack(platoonUnits, target, PlatoonFormation, 0)
						IssueAggressiveMove(platoonUnits, target)
					else
						#IssueAttack(platoonUnits, target)
						IssueAggressiveMove(platoonUnits, target)
					end
				end
            end
            WaitSeconds(17)
        end
    end,

    AttackForceAISorian = function(self)
        self:Stop()
        local aiBrain = self:GetBrain()
        
        # get units together
        if not self:GatherUnits() then
            return
        end
        
        # Setup the formation based on platoon functionality
        
        local enemy = aiBrain:GetCurrentEnemy()

        local platoonUnits = self:GetPlatoonUnits()
        local numberOfUnitsInPlatoon = table.getn(platoonUnits)
        local oldNumberOfUnitsInPlatoon = numberOfUnitsInPlatoon
		local platoonTechLevel = SUtils.GetPlatoonTechLevel(platoonUnits)
		local platoonThreatTable = {4,28,80} 
        local stuckCount = 0
        
        self.PlatoonAttackForce = true
        # formations have penalty for taking time to form up... not worth it here
        # maybe worth it if we micro
        #self:SetPlatoonFormationOverride('GrowthFormation')
		local bAggro = self.PlatoonData.AggressiveMove or false
        local PlatoonFormation = self.PlatoonData.UseFormation or 'No Formation'
        self:SetPlatoonFormationOverride(PlatoonFormation)
		local maxRange, selectedWeaponArc, turretPitch = AIAttackUtils.GetLandPlatoonMaxRangeSorian(aiBrain, self)
		#local quickReset = false
        
        while aiBrain:PlatoonExists(self) do
            local pos = self:GetPlatoonPosition() # update positions; prev position done at end of loop so not done first time  
            
            # if we can't get a position, then we must be dead
            if not pos then
                break
            end
            
            
            # if we're using a transport, wait for a while
            if self.UsingTransport then
                WaitSeconds(10)
                continue
            end
                        
            # pick out the enemy
            if aiBrain:GetCurrentEnemy() and aiBrain:GetCurrentEnemy():IsDefeated() then
                aiBrain:PickEnemyLogicSorian()
            end

            # merge with nearby platoons
			if aiBrain:GetThreatAtPosition( pos, 1, true, 'AntiSurface') < 1 then
				self:MergeWithNearbyPlatoonsSorian('AttackForceAISorian', 10)
			end

            # rebuild formation
            platoonUnits = self:GetPlatoonUnits()
            numberOfUnitsInPlatoon = table.getn(platoonUnits)
            # if we have a different number of units in our platoon, regather
            if (oldNumberOfUnitsInPlatoon != numberOfUnitsInPlatoon) and aiBrain:GetThreatAtPosition( pos, 1, true, 'AntiSurface') < 1 then
                self:StopAttack()
                self:SetPlatoonFormationOverride(PlatoonFormation)
				oldNumberOfUnitsInPlatoon = numberOfUnitsInPlatoon
			end

            # deal with lost-puppy transports
            local strayTransports = {}
            for k,v in platoonUnits do
                if EntityCategoryContains(categories.TRANSPORTATION, v) then
                    table.insert(strayTransports, v)
                end 
            end
            if table.getn(strayTransports) > 0 then
                local dropPoint = pos
                dropPoint[1] = dropPoint[1] + Random(-3, 3)
                dropPoint[3] = dropPoint[3] + Random(-3, 3)
                IssueTransportUnload( strayTransports, dropPoint )
                WaitSeconds(10)
                local strayTransports = {}
                for k,v in platoonUnits do
                    local parent = v:GetParent()
                    if parent and EntityCategoryContains(categories.TRANSPORTATION, parent) then
                        table.insert(strayTransports, parent)
                        break
                    end 
                end
                if table.getn(strayTransports) > 0 then
                    local MAIN = aiBrain.BuilderManagers.MAIN
                    if MAIN then
                        dropPoint = MAIN.Position
                        IssueTransportUnload( strayTransports, dropPoint )
                        WaitSeconds(30)
                    end
                end
                self.UsingTransport = false
                AIUtils.ReturnTransportsToPool( strayTransports, true )
                platoonUnits = self:GetPlatoonUnits()
            end    
    

        	#Disband platoon if it's all air units, so they can be picked up by another platoon
            local mySurfaceThreat = AIAttackUtils.GetSurfaceThreatOfUnits(self)
            if mySurfaceThreat == 0 and AIAttackUtils.GetAirThreatOfUnits(self) > 0 then
                self:PlatoonDisband()
                return
            end
                        
            local cmdQ = {} 
            # fill cmdQ with current command queue for each unit
            for k,v in platoonUnits do
                if not v:IsDead() then
                    local unitCmdQ = v:GetCommandQueue()
                    for cmdIdx,cmdVal in unitCmdQ do
                        table.insert(cmdQ, cmdVal)
                        break
                    end
                end
            end
			
			if (oldNumberOfUnitsInPlatoon != numberOfUnitsInPlatoon) then
				maxRange, selectedWeaponArc, turretPitch = AIAttackUtils.GetLandPlatoonMaxRangeSorian(aiBrain, self)
			end
			
			if not maxRange then maxRange = 50 end
			
            # if we're on our final push through to the destination, and we find a unit close to our destination
            #local closestTarget = self:FindClosestUnit( 'attack', 'enemy', true, categories.ALLUNITS )
			local closestTarget = SUtils.FindClosestUnitPosToAttack( aiBrain, self, 'attack', maxRange + 20, categories.ALLUNITS - categories.AIR - categories.NAVAL - categories.WALL, selectedWeaponArc, turretPitch )
            local nearDest = false
            local oldPathSize = table.getn(self.LastAttackDestination)
            if self.LastAttackDestination then
                nearDest = oldPathSize == 0 or VDist3(self.LastAttackDestination[oldPathSize], pos) < 20
            end
			
		# if we're near our destination and we have a unit closeby to kill, kill it
            if table.getn(cmdQ) <= 1 and closestTarget and nearDest then
                self:StopAttack()
                if PlatoonFormation != 'No Formation' then
                    #IssueFormAttack(platoonUnits, closestTarget, PlatoonFormation, 0)
					#IssueAggressiveMove(platoonUnits, closestTarget)
					self:AggressiveMoveToLocation(closestTarget)
                else
                    #IssueAttack(platoonUnits, closestTarget)
					#IssueAggressiveMove(platoonUnits, closestTarget)
					self:AggressiveMoveToLocation(closestTarget)
                end
                cmdQ = {1}
#				quickReset = true
			# if we have a target and can attack it, attack!
			elseif closestTarget then
				self:StopAttack()
				if PlatoonFormation != 'No Formation' then
					#IssueFormAttack(platoonUnits, closestTarget, PlatoonFormation, 0)
					#IssueAggressiveMove(platoonUnits, closestTarget)
					self:AggressiveMoveToLocation(closestTarget)
				else
					#IssueAttack(platoonUnits, closestTarget)
					#IssueAggressiveMove(platoonUnits, closestTarget)
					self:AggressiveMoveToLocation(closestTarget)
				end
				cmdQ = {1}
#				quickReset = true
            # if we have nothing to do, but still have a path (because of one of the above)
			elseif table.getn(cmdQ) == 0 and oldPathSize > 0 then
				self.LastAttackDestination = nil
                self:StopAttack()
                cmdQ = AIAttackUtils.AIPlatoonSquadAttackVectorSorian( aiBrain, self, bAggro )
                stuckCount = 0
			# if we have nothing to do, try finding something to do
            elseif table.getn(cmdQ) == 0 then
                self:StopAttack()
                cmdQ = AIAttackUtils.AIPlatoonSquadAttackVectorSorian( aiBrain, self, bAggro )
                stuckCount = 0
            # if we've been stuck and unable to reach next marker? Ignore nearby stuff and pick another target  
            elseif self.LastPosition and VDist2Sq(self.LastPosition[1], self.LastPosition[3], pos[1], pos[3]) < ( self.PlatoonData.StuckDistance or 8) then
                stuckCount = stuckCount + 1
                if stuckCount >= 2 then
                    self:StopAttack()
					self.LastAttackDestination = nil
                    cmdQ = AIAttackUtils.AIPlatoonSquadAttackVectorSorian( aiBrain, self, bAggro )
                    stuckCount = 0
                end
            else
                stuckCount = 0
            end
            
            self.LastPosition = pos
            
            if table.getn(cmdQ) == 0 then #and mySurfaceThreat < 4 then
                # if we have a low threat value, then go and defend an engineer or a base
                if mySurfaceThreat < platoonThreatTable[platoonTechLevel]
                    and mySurfaceThreat > 0 and not self.PlatoonData.NeverGuard 
                    and not (self.PlatoonData.NeverGuardEngineers and self.PlatoonData.NeverGuardBases) then
                    #LOG('*DEBUG: Trying to guard')
					if platoonTechLevel > 1 then
						return self:GuardExperimentalSorian(self.AttackForceAISorian)
					else
						return self:GuardEngineer(self.AttackForceAISorian)
					end
                end
                
                # we have nothing to do, so find the nearest base and disband
                if not self.PlatoonData.NeverMerge then
                    return self:ReturnToBaseAISorian()
                end
                WaitSeconds(5)
            else
                # wait a little longer if we're stuck so that we have a better chance to move
#				if quickReset then
#					quickReset = false
#					WaitSeconds(6)
#				else
				WaitSeconds(Random(5,11) + 2 * stuckCount)
#				end
            end
        end
    end,
	
    ReturnToBaseAISorian = function(self)
        local aiBrain = self:GetBrain()
        
        if not aiBrain:PlatoonExists(self) or not self:GetPlatoonPosition() then
            return
        end
        
        local bestBase = false
        local bestBaseName = ""
        local bestDistSq = 999999999
        local platPos = self:GetPlatoonPosition()

        for baseName, base in aiBrain.BuilderManagers do
            local distSq = VDist2Sq(platPos[1], platPos[3], base.Position[1], base.Position[3])

            if distSq < bestDistSq then
                bestBase = base
                bestBaseName = baseName
                bestDistSq = distSq    
            end
        end

        if bestBase then
            AIAttackUtils.GetMostRestrictiveLayer(self)
            local path, reason = AIAttackUtils.PlatoonGenerateSafePathTo(aiBrain, self.MovementLayer, self:GetPlatoonPosition(), bestBase.Position, 200)
            IssueClearCommands(self)
            
            if path then
                local pathLength = table.getn(path)
                for i=1, pathLength-1 do
                    self:MoveToLocation(path[i], false)
                end 
            end
            self:MoveToLocation(bestBase.Position, false)  

            local oldDistSq = 0
            while aiBrain:PlatoonExists(self) do
                WaitSeconds(10)
                platPos = self:GetPlatoonPosition()
                local distSq = VDist2Sq(platPos[1], platPos[3], bestBase.Position[1], bestBase.Position[3])
                if distSq < 10 then
                    self:PlatoonDisband()
                    return
                end
                # if we haven't moved in 10 seconds... go back to attacking
                if (distSq - oldDistSq) < 5 then
                    break
                end
                oldDistSq = distSq      
            end
        end
        # default to returning to attacking    
        return self:AttackForceAISorian()
    end,
	
    StrikeForceAISorian = function(self)
        local aiBrain = self:GetBrain()
        local armyIndex = aiBrain:GetArmyIndex()
        local data = self.PlatoonData
        local categoryList = {}
        local atkPri = {}
        if data.PrioritizedCategories then
            for k,v in data.PrioritizedCategories do
                table.insert( atkPri, v )
                table.insert( categoryList, ParseEntityCategory( v ) )
            end
        end
        table.insert( atkPri, 'ALLUNITS' )
        table.insert( categoryList, categories.ALLUNITS )
        self:SetPrioritizedTargetList( 'Attack', categoryList )
        local target = false
		local oldTarget = false
        local blip = false
        local maxRadius = data.SearchRadius or 50
        local movingToScout = false
		AIAttackUtils.GetMostRestrictiveLayer(self)
        while aiBrain:PlatoonExists(self) do
			if target then
				local targetCheck = true
				for k,v in atkPri do
					local category = ParseEntityCategory( v )
					if EntityCategoryContains(category, target) and v != 'ALLUNITS' then
						targetCheck = false
						break
					end
				end  
				if targetCheck then
					target = false
				end
			end
            if not target or target:IsDead() then
                if aiBrain:GetCurrentEnemy() and aiBrain:GetCurrentEnemy():IsDefeated() then
                    aiBrain:PickEnemyLogicSorian()
                end
                local mult = { 1,10,25 }
                for _,i in mult do
                    target = AIUtils.AIFindBrainTargetInRange( aiBrain, self, 'Attack', maxRadius * i, atkPri, aiBrain:GetCurrentEnemy() )
                    if target then
                        break
                    end
                    WaitSeconds(3)
                    if not aiBrain:PlatoonExists(self) then
                        return
                    end
                end
				local newtarget
				if AIAttackUtils.GetSurfaceThreatOfUnits(self) > 0 and (aiBrain.T4ThreatFound['Land'] or aiBrain.T4ThreatFound['Naval'] or aiBrain.T4ThreatFound['Structure']) then
					newtarget = self:FindClosestUnit('Attack', 'Enemy', true, categories.EXPERIMENTAL * (categories.LAND + categories.NAVAL + categories.STRUCTURE + categories.ARTILLERY))
				elseif AIAttackUtils.GetAirThreatOfUnits(self) > 0 and aiBrain.T4ThreatFound['Air'] then
					newtarget = self:FindClosestUnit('Attack', 'Enemy', true, categories.EXPERIMENTAL * categories.AIR)
				end
				if newtarget then
					target = newtarget
				end
				if target and (target != oldTarget or movingToScout) then
					oldTarget = target
					local path, reason = AIAttackUtils.PlatoonGenerateSafePathTo(aiBrain, self.MovementLayer, self:GetPlatoonPosition(), target:GetPosition(), 10 )
					self:Stop()
					if not path then
						if reason == 'NoStartNode' or reason == 'NoEndNode' then				
							if not data.UseMoveOrder then
								self:AttackTarget( target )
							else
								self:MoveToLocation( table.copy( target:GetPosition() ), false)
							end
						end
					else
						local pathSize = table.getn(path)
						for wpidx,waypointPath in path do
							if wpidx == pathSize and not data.UseMoveOrder then
								self:AttackTarget( target )
							else
								self:MoveToLocation(waypointPath, false)
							end
						end   
					end
					movingToScout = false
				elseif not movingToScout and not target and self.MovementLayer != 'Water' then
					movingToScout = true
					self:Stop()
					for k,v in AIUtils.AIGetSortedMassLocations(aiBrain, 10, nil, nil, nil, nil, self:GetPlatoonPosition()) do
						if v[1] < 0 or v[3] < 0 or v[1] > ScenarioInfo.size[1] or v[3] > ScenarioInfo.size[2] then
							#LOG('*AI DEBUG: STRIKE FORCE SENDING UNITS TO WRONG LOCATION - ' .. v[1] .. ', ' .. v[3] )
						end
						self:MoveToLocation( v, false )
					end
				elseif not movingToScout and not target and self.MovementLayer == 'Water' then
					movingToScout = true
					self:Stop()
					local scoutPath = {}
					scoutPath = AIUtils.AIGetSortedNavalLocations(self:GetBrain())
					for k, v in scoutPath do
						self:Patrol(v)
					end
				end
			end
			WaitSeconds( 7 )
		end
	end,
	
    #-----------------------------------------------------
    #   Function: EngineerBuildAI
    #   Args:
    #       self - the single-engineer platoon to run the AI on
    #   Description:
    #       a single-unit platoon made up of an engineer, this AI will determine
    #       what needs to be built (based on platoon data set by the calling
    #       abstraction, and then issue the build commands to the engineer
    #   Returns:  
    #       nil (tail calls into a behavior function)
    #-----------------------------------------------------
    EngineerBuildAISorian = function(self)
        self:Stop()
        local aiBrain = self:GetBrain()
        local cons = self.PlatoonData.Construction
		
		if cons.T4 and not aiBrain.T4Building then
			aiBrain.T4Building = true
			ForkThread(SUtils.T4Timeout, aiBrain)
		end
		
        local platoonUnits = self:GetPlatoonUnits()
        local armyIndex = aiBrain:GetArmyIndex()
        local x,z = aiBrain:GetArmyStartPos()
        local buildingTmpl, buildingTmplFile, baseTmpl, baseTmplFile
        
        local factionIndex = cons.FactionIndex or self:GetFactionIndex()
        
        buildingTmplFile = import(cons.BuildingTemplateFile or '/lua/BuildingTemplates.lua')
        baseTmplFile = import(cons.BaseTemplateFile or '/lua/BaseTemplates.lua')
        buildingTmpl = buildingTmplFile[(cons.BuildingTemplate or 'BuildingTemplates')][factionIndex]
        baseTmpl = baseTmplFile[(cons.BaseTemplate or 'BaseTemplates')][factionIndex]

        local eng
        for k, v in platoonUnits do
            if not v:IsDead() and EntityCategoryContains(categories.CONSTRUCTION, v ) then
                if not eng then
                    eng = v
                else
                    IssueClearCommands( {v} )
                    IssueGuard({v}, eng)
                end
            end
        end

        if not eng or eng:IsDead() then
            WaitTicks(1)
            self:PlatoonDisband()
            return
        end

        if self.PlatoonData.NeedGuard then
            eng.NeedGuard = true
        end

        #### CHOOSE APPROPRIATE BUILD FUNCTION AND SETUP BUILD VARIABLES ####
        local reference = false
        local refName = false
        local buildFunction
        local closeToBuilder
        local relative
        local baseTmplList = {}
        
        # if we have nothing to build, disband!
        if not cons.BuildStructures then
            WaitTicks(1)
            self:PlatoonDisband()
            return
        end
        
        if cons.NearUnitCategory then
            self:SetPrioritizedTargetList('support', {ParseEntityCategory(cons.NearUnitCategory)})
            local unitNearBy = self:FindPrioritizedUnit('support', 'Ally', false, self:GetPlatoonPosition(), cons.NearUnitRadius or 50)
            #LOG("ENGINEER BUILD: " .. cons.BuildStructures[1] .." attempt near: ", cons.NearUnitCategory)
            if unitNearBy then
                reference = table.copy( unitNearBy:GetPosition() )
                # get commander home position
                #LOG("ENGINEER BUILD: " .. cons.BuildStructures[1] .." Near unit: ", cons.NearUnitCategory)
                if cons.NearUnitCategory == 'COMMAND' and unitNearBy.CDRHome then
                    reference = unitNearBy.CDRHome
                end
            else
                reference = table.copy( eng:GetPosition() )
            end
            relative = false
            buildFunction = AIBuildStructures.AIExecuteBuildStructure
            table.insert( baseTmplList, AIBuildStructures.AIBuildBaseTemplateFromLocation( baseTmpl, reference ) )
        elseif cons.Wall then
            local pos = aiBrain:PBMGetLocationCoords(cons.LocationType) or cons.Position or self:GetPlatoonPosition()
            local radius = cons.LocationRadius or aiBrain:PBMGetLocationRadius(cons.LocationType) or 100
            relative = false
            reference = AIUtils.GetLocationNeedingWalls( aiBrain, 200, 5, 'DEFENSE', cons.ThreatMin, cons.ThreatMax, cons.ThreatRings )
            table.insert( baseTmplList, 'Blank' )
            buildFunction = AIBuildStructures.WallBuilder
        elseif cons.NearBasePatrolPoints then
            relative = false
            reference = AIUtils.GetBasePatrolPointsSorian(aiBrain, cons.Location or 'MAIN', cons.Radius or 100)
            baseTmpl = baseTmplFile['ExpansionBaseTemplates'][factionIndex]
            for k,v in reference do
                table.insert( baseTmplList, AIBuildStructures.AIBuildBaseTemplateFromLocation( baseTmpl, v ) )
            end
            # Must use BuildBaseOrdered to start at the marker; otherwise it builds closest to the eng
            buildFunction = AIBuildStructures.AIBuildBaseTemplateOrdered
        elseif cons.NearMarkerType and cons.ExpansionBase then
            local pos = aiBrain:PBMGetLocationCoords(cons.LocationType) or cons.Position or self:GetPlatoonPosition()
            local radius = cons.LocationRadius or aiBrain:PBMGetLocationRadius(cons.LocationType) or 100
            
            if cons.FireBase and cons.FireBaseRange then
                reference, refName = AIUtils.AIFindFirebaseLocationSorian(aiBrain, cons.LocationType, cons.FireBaseRange, cons.NearMarkerType,
                                                    cons.ThreatMin, cons.ThreatMax, cons.ThreatRings, cons.ThreatType, 
                                                    cons.MarkerUnitCount, cons.MarkerUnitCategory, cons.MarkerRadius)
                if not reference or not refName then
                    self:PlatoonDisband()
                end
            elseif cons.NearMarkerType == 'Expansion Area' then
                reference, refName = AIUtils.AIFindExpansionAreaNeedsEngineer( aiBrain, cons.LocationType, 
                        (cons.LocationRadius or 100), cons.ThreatMin, cons.ThreatMax, cons.ThreatRings, cons.ThreatType )
                # didn't find a location to build at
                if not reference or not refName then
                    self:PlatoonDisband()
                end
            elseif cons.NearMarkerType == 'Naval Area' then
                reference, refName = AIUtils.AIFindNavalAreaNeedsEngineer( aiBrain, cons.LocationType, 
                        (cons.LocationRadius or 100), cons.ThreatMin, cons.ThreatMax, cons.ThreatRings, cons.ThreatType )
                # didn't find a location to build at
                if not reference or not refName then
                    self:PlatoonDisband()
                end
            else
                reference, refName = AIUtils.AIFindStartLocationNeedsEngineerSorian( aiBrain, cons.LocationType, 
                        (cons.LocationRadius or 100), cons.ThreatMin, cons.ThreatMax, cons.ThreatRings, cons.ThreatType )
                # didn't find a location to build at
                if not reference or not refName then
                    self:PlatoonDisband()
                end
            end
            
            # If moving far from base, tell the assisting platoons to not go with
            if cons.FireBase or cons.ExpansionBase then
                local guards = eng:GetGuards()
                for k,v in guards do
                    if not v:IsDead() and v.PlatoonHandle and EntityCategoryContains(categories.CONSTRUCTION, v ) then
                        v.PlatoonHandle:PlatoonDisband()
                    end
                end
            end
                    
            if not cons.BaseTemplate and ( cons.NearMarkerType == 'Naval Area' or cons.NearMarkerType == 'Defensive Point' or cons.NearMarkerType == 'Expansion Area' ) then
                baseTmpl = baseTmplFile['ExpansionBaseTemplates'][factionIndex]
            end
            if cons.ExpansionBase and refName then
                AIBuildStructures.AINewExpansionBase( aiBrain, refName, reference, eng, cons)
            end
            relative = false
            if reference and aiBrain:GetThreatAtPosition( reference , 1, true, 'AntiSurface' ) > 0 then
                #aiBrain:ExpansionHelp( eng, reference )
            end
            table.insert( baseTmplList, AIBuildStructures.AIBuildBaseTemplateFromLocation( baseTmpl, reference ) )
            # Must use BuildBaseOrdered to start at the marker; otherwise it builds closest to the eng
            #buildFunction = AIBuildStructures.AIBuildBaseTemplateOrdered
            buildFunction = AIBuildStructures.AIBuildBaseTemplate
        elseif cons.NearMarkerType and cons.FireBase and cons.FireBaseRange then
		    baseTmpl = baseTmplFile['ExpansionBaseTemplates'][factionIndex]
			
			relative = false
            local pos = self:GetPlatoonPosition()
            reference, refName = AIUtils.AIFindFirebaseLocationSorian(aiBrain, cons.LocationType, cons.FireBaseRange, cons.NearMarkerType,
                                                cons.ThreatMin, cons.ThreatMax, cons.ThreatRings, cons.ThreatType, 
                                                cons.MarkerUnitCount, cons.MarkerUnitCategory, cons.MarkerRadius)

			table.insert( baseTmplList, AIBuildStructures.AIBuildBaseTemplateFromLocation( baseTmpl, reference ) )
			
			buildFunction = AIBuildStructures.AIExecuteBuildStructure
        elseif cons.NearMarkerType and cons.NearMarkerType == 'Defensive Point' then
            baseTmpl = baseTmplFile['ExpansionBaseTemplates'][factionIndex]

            relative = false
            local pos = self:GetPlatoonPosition()
            reference, refName = AIUtils.AIFindDefensivePointNeedsStructureSorian( aiBrain, cons.LocationType, (cons.LocationRadius or 100), 
                            cons.MarkerUnitCategory, cons.MarkerRadius, cons.MarkerUnitCount, (cons.ThreatMin or 0), (cons.ThreatMax or 1), 
                            (cons.ThreatRings or 1), (cons.ThreatType or 'AntiSurface') )

            table.insert( baseTmplList, AIBuildStructures.AIBuildBaseTemplateFromLocation( baseTmpl, reference ) )

            buildFunction = AIBuildStructures.AIExecuteBuildStructure
        elseif cons.NearMarkerType and cons.NearMarkerType == 'Naval Defensive Point' then
            baseTmpl = baseTmplFile['ExpansionBaseTemplates'][factionIndex]

            relative = false
            local pos = self:GetPlatoonPosition()
            reference, refName = AIUtils.AIFindNavalDefensivePointNeedsStructure( aiBrain, cons.LocationType, (cons.LocationRadius or 100), 
                            cons.MarkerUnitCategory, cons.MarkerRadius, cons.MarkerUnitCount, (cons.ThreatMin or 0), (cons.ThreatMax or 1), 
                            (cons.ThreatRings or 1), (cons.ThreatType or 'AntiSurface') )

            table.insert( baseTmplList, AIBuildStructures.AIBuildBaseTemplateFromLocation( baseTmpl, reference ) )

            buildFunction = AIBuildStructures.AIExecuteBuildStructure
        elseif cons.NearMarkerType and cons.NearMarkerType == 'Expansion Area' then
            baseTmpl = baseTmplFile['ExpansionBaseTemplates'][factionIndex]

            relative = false
            local pos = self:GetPlatoonPosition()
            reference, refName = AIUtils.AIFindExpansionPointNeedsStructure( aiBrain, cons.LocationType, (cons.LocationRadius or 100), 
                            cons.MarkerUnitCategory, cons.MarkerRadius, cons.MarkerUnitCount, (cons.ThreatMin or 0), (cons.ThreatMax or 1), 
                            (cons.ThreatRings or 1), (cons.ThreatType or 'AntiSurface') )

            table.insert( baseTmplList, AIBuildStructures.AIBuildBaseTemplateFromLocation( baseTmpl, reference ) )

            buildFunction = AIBuildStructures.AIExecuteBuildStructure
        elseif cons.NearMarkerType then
            #WARN('*Data weird for builder named - ' .. self.BuilderName )
            if not cons.ThreatMin or not cons.ThreatMax or not cons.ThreatRings then
                cons.ThreatMin = -1000000
                cons.ThreatMax = 1000000
                cons.ThreatRings = 0
            end
            if not cons.BaseTemplate and ( cons.NearMarkerType == 'Defensive Point' or cons.NearMarkerType == 'Expansion Area' ) then
                baseTmpl = baseTmplFile['ExpansionBaseTemplates'][factionIndex]
            end
            relative = false
            local pos = self:GetPlatoonPosition()
            reference, refName = AIUtils.AIGetClosestThreatMarkerLoc(aiBrain, cons.NearMarkerType, pos[1], pos[3],
                                                            cons.ThreatMin, cons.ThreatMax, cons.ThreatRings)
            if cons.ExpansionBase and refName then
                AIBuildStructures.AINewExpansionBase( aiBrain, refName, reference, (cons.ExpansionRadius or 100), cons.ExpansionTypes, nil, cons )
            end
            if reference and aiBrain:GetThreatAtPosition( reference, 1, true ) > 0 then
                #aiBrain:ExpansionHelp( eng, reference )
            end
            table.insert( baseTmplList, AIBuildStructures.AIBuildBaseTemplateFromLocation( baseTmpl, reference ) )
            buildFunction = AIBuildStructures.AIExecuteBuildStructure
        elseif cons.AvoidCategory then
            relative = false
            local pos = aiBrain.BuilderManagers[eng.BuilderManagerData.LocationType].EngineerManager:GetLocationCoords()
            local cat = ParseEntityCategory(cons.AdjacencyCategory)
			local avoidCat = ParseEntityCategory(cons.AvoidCategory)
            local radius = ( cons.AdjacencyDistance or 50 )
            if not pos or not pos then
                WaitTicks(1)
                self:PlatoonDisband()
                return
            end
            reference  = AIUtils.FindUnclutteredArea( aiBrain, cat, pos, radius, cons.maxUnits, cons.maxRadius, avoidCat)
            buildFunction = AIBuildStructures.AIBuildAdjacency
            table.insert( baseTmplList, baseTmpl )
        elseif cons.AdjacencyCategory then
            relative = false
            local pos = aiBrain.BuilderManagers[eng.BuilderManagerData.LocationType].EngineerManager:GetLocationCoords()
            local cat = ParseEntityCategory(cons.AdjacencyCategory)
            local radius = ( cons.AdjacencyDistance or 50 )
            if not pos or not pos then
                WaitTicks(1)
                self:PlatoonDisband()
                return
            end
            reference  = AIUtils.GetOwnUnitsAroundPointSorian( aiBrain, cat, pos, radius, cons.ThreatMin,
                                                        cons.ThreatMax, cons.ThreatRings, 'Overall', cons.MinRadius or 0)
            buildFunction = AIBuildStructures.AIBuildAdjacency
            table.insert( baseTmplList, baseTmpl )
        else
            table.insert( baseTmplList, baseTmpl )
            relative = true
            reference = true
            buildFunction = AIBuildStructures.AIExecuteBuildStructure
        end
        if cons.BuildClose then
            closeToBuilder = eng
        end
        if cons.BuildStructures[1] == 'T1Resource' or cons.BuildStructures[1] == 'T2Resource' or cons.BuildStructures[1] == 'T3Resource' then
            relative = true
            closeToBuilder = eng
            local guards = eng:GetGuards()
            for k,v in guards do
                if not v:IsDead() and v.PlatoonHandle and aiBrain:PlatoonExists(v.PlatoonHandle) and EntityCategoryContains(categories.CONSTRUCTION, v ) then
                    #WaitTicks(1)
                    v.PlatoonHandle:PlatoonDisband()
                end
            end
        end                   

        #LOG("*AI DEBUG: Setting up Callbacks for " .. eng.Sync.id)
        self.SetupEngineerCallbacksSorian(eng)
              
        #### BUILD BUILDINGS HERE ####
        for baseNum, baseListData in baseTmplList do
            for k, v in cons.BuildStructures do
                if aiBrain:PlatoonExists(self) then
                    if not eng:IsDead() then
                        buildFunction(aiBrain, eng, v, closeToBuilder, relative, buildingTmpl, baseListData, reference, cons.NearMarkerType)
                    else
                        if aiBrain:PlatoonExists(self) then
                            WaitTicks(1)
                            self:PlatoonDisband()
                            return
                        end
                    end
                end
            end
        end
        
        # wait in case we're still on a base
        if not eng:IsDead() then
            local count = 0
            while eng:IsUnitState( 'Attached' ) and count < 2 do
                WaitSeconds(6)
                count = count + 1
            end
        end

        if not eng:IsUnitState('Building') then
            return self.ProcessBuildCommandSorian(eng, false)
        end
    end,
	
    SetupEngineerCallbacksSorian = function(eng)
        if eng and not eng:IsDead() and not eng.BuildDoneCallbackSet and eng.PlatoonHandle and eng:GetAIBrain():PlatoonExists(eng.PlatoonHandle) then                
            import('/lua/ScenarioTriggers.lua').CreateUnitBuiltTrigger(eng.PlatoonHandle.EngineerBuildDoneSorian, eng, categories.ALLUNITS)
            eng.BuildDoneCallbackSet = true
        end
        if eng and not eng:IsDead() and not eng.CaptureDoneCallbackSet and eng.PlatoonHandle and eng:GetAIBrain():PlatoonExists(eng.PlatoonHandle) then
            import('/lua/ScenarioTriggers.lua').CreateUnitStopCaptureTrigger(eng.PlatoonHandle.EngineerCaptureDoneSorian, eng )
            eng.CaptureDoneCallbackSet = true
        end
        if eng and not eng:IsDead() and not eng.ReclaimDoneCallbackSet and eng.PlatoonHandle and eng:GetAIBrain():PlatoonExists(eng.PlatoonHandle) then
            import('/lua/ScenarioTriggers.lua').CreateUnitStopReclaimTrigger(eng.PlatoonHandle.EngineerReclaimDoneSorian, eng )
            eng.ReclaimDoneCallbackSet = true
        end
        if eng and not eng:IsDead() and not eng.FailedToBuildCallbackSet and eng.PlatoonHandle and eng:GetAIBrain():PlatoonExists(eng.PlatoonHandle) then
            import('/lua/ScenarioTriggers.lua').CreateOnFailedToBuildTrigger(eng.PlatoonHandle.EngineerFailedToBuildSorian, eng )
            eng.FailedToBuildCallbackSet = true
        end      
    end,
    
    # Callback functions for EngineerBuildAI
    EngineerBuildDoneSorian = function(unit, params)
        if not unit.PlatoonHandle then return end
        if not unit.PlatoonHandle.PlanName == 'EngineerBuildAISorian' then return end
        #LOG("*AI DEBUG: Build done " .. unit.Sync.id)
        if not unit.ProcessBuild then
            unit.ProcessBuild = unit:ForkThread(unit.PlatoonHandle.ProcessBuildCommandSorian, true)
            unit.ProcessBuildDone = true
        end
    end,
    EngineerCaptureDoneSorian = function(unit, params)
        if not unit.PlatoonHandle then return end
        if not unit.PlatoonHandle.PlanName == 'EngineerBuildAISorian' then return end
        #LOG("*AI DEBUG: Capture done" .. unit.Sync.id)
        if not unit.ProcessBuild then
            unit.ProcessBuild = unit:ForkThread(unit.PlatoonHandle.ProcessBuildCommandSorian, false)
        end
    end,
    EngineerReclaimDoneSorian = function(unit, params)
        if not unit.PlatoonHandle then return end
        if not unit.PlatoonHandle.PlanName == 'EngineerBuildAISorian' then return end
        #LOG("*AI DEBUG: Reclaim done" .. unit.Sync.id)
        if not unit.ProcessBuild then
            unit.ProcessBuild = unit:ForkThread(unit.PlatoonHandle.ProcessBuildCommandSorian, false)
        end
    end,
    EngineerFailedToBuildSorian = function(unit, params)
        if not unit.PlatoonHandle then return end
        if not unit.PlatoonHandle.PlanName == 'EngineerBuildAISorian' then return end
        if unit.ProcessBuildDone and unit.ProcessBuild then
            KillThread(unit.ProcessBuild)
            unit.ProcessBuild = nil
        end
        if not unit.ProcessBuild then
            unit.ProcessBuild = unit:ForkThread(unit.PlatoonHandle.ProcessBuildCommandSorian, false)
        end   
    end,

    #-----------------------------------------------------
    #   Function: WatchForNotBuildingSorian
    #   Args:
    #       eng - the engineer that's gone through EngineerBuildAI
    #   Description:
    #       After we try to build something, watch the engineer to
    #       make sure that the build goes through.  If not,
    #       try the next thing in the queue
    #   Returns:  
    #       nil
    #-----------------------------------------------------
    WatchForNotBuildingSorian = function(eng)
        WaitTicks(5)
        local aiBrain = eng:GetAIBrain()
        while not eng:IsDead() and (eng.GoingHome or eng.Upgrading or eng.Fighting or eng:IsUnitState("Building") or 
                  eng:IsUnitState("Attacking") or eng:IsUnitState("Repairing") or eng:IsUnitState("WaitingForTransport") or
                  eng:IsUnitState("Reclaiming") or eng:IsUnitState("Capturing") or eng:IsUnitState("Moving") or eng:IsUnitState("Upgrading") or eng.ProcessBuild != nil 
				  or eng.UnitBeingBuiltBehavior) do
                  
            WaitSeconds(3)
            #if eng.CDRHome then eng:PrintCommandQueue() end
        end
        eng.NotBuildingThread = nil
        if not eng:IsDead() and eng:IsIdleState() and table.getn(eng.EngineerBuildQueue) != 0 and eng.PlatoonHandle then
            eng.PlatoonHandle.SetupEngineerCallbacksSorian(eng)
            if not eng.ProcessBuild then
                eng.ProcessBuild = eng:ForkThread(eng.PlatoonHandle.ProcessBuildCommandSorian, true)
            end
        end  
    end,
    
    #-----------------------------------------------------
    #   Function: ProcessBuildCommandSorian
    #   Args:
    #       eng - the engineer that's gone through EngineerBuildAI
    #   Description:
    #       Run after every build order is complete/fails.  Sets up the next
    #       build order in queue, and if the engineer has nothing left to do
    #       will return the engineer back to the army pool by disbanding the
    #       the platoon.  Support function for EngineerBuildAI
    #   Returns:  
    #       nil (tail calls into a behavior function)
    #-----------------------------------------------------
    ProcessBuildCommandSorian = function(eng, removeLastBuild)	
		if not eng or eng:IsDead() or not eng.PlatoonHandle or eng:IsUnitState("Upgrading") or eng.Upgrading or eng.GoingHome or eng.Fighting or eng.UnitBeingBuiltBehavior then
            if eng then eng.ProcessBuild = nil end
            return
        end
		local aiBrain = eng.PlatoonHandle:GetBrain()
        
        if not aiBrain or eng:IsDead() or not eng.EngineerBuildQueue or table.getn(eng.EngineerBuildQueue) == 0 then
            if aiBrain:PlatoonExists(eng.PlatoonHandle) then
                #LOG("*AI DEBUG: Disbanding Engineer Platoon in ProcessBuildCommand " .. eng.Sync.id)
				#if EntityCategoryContains( categories.COMMAND, eng ) then
				#	LOG("*AI DEBUG: Commander Platoon Disbanded in ProcessBuildCommand")
				#end
                eng.PlatoonHandle:PlatoonDisband()
            end
            if eng then eng.ProcessBuild = nil end
            return
        end
         
        # it wasn't a failed build, so we just finished something
        if removeLastBuild then
            table.remove(eng.EngineerBuildQueue, 1)
        end
        
        function BuildToNormalLocation(location)
            return {location[1], 0, location[2]}
        end
        
        function NormalToBuildLocation(location)
            return {location[1], location[3], 0}
        end
        
        eng.ProcessBuildDone = false  
        IssueClearCommands({eng}) 
        local commandDone = false
        while not eng:IsDead() and not commandDone and table.getn(eng.EngineerBuildQueue) > 0 do
            local whatToBuild = eng.EngineerBuildQueue[1][1]
            local buildLocation = BuildToNormalLocation(eng.EngineerBuildQueue[1][2])
            local buildRelative = eng.EngineerBuildQueue[1][3]
			local threadStarted = false
            # see if we can move there first        
            if AIUtils.EngineerMoveWithSafePathSorian(aiBrain, eng, buildLocation) then
                if not eng or eng:IsDead() or not eng.PlatoonHandle or not aiBrain:PlatoonExists(eng.PlatoonHandle) then
                    if eng then eng.ProcessBuild = nil end
                    return
                end
                # check to see if we need to reclaim or capture...
                if not AIUtils.EngineerTryReclaimCaptureAreaSorian(aiBrain, eng, buildLocation) then
                    # check to see if we can repair
                    if not AIUtils.EngineerTryRepairSorian(aiBrain, eng, whatToBuild, buildLocation) then
                        # otherwise, go ahead and build the next structure there
                        aiBrain:BuildStructure( eng, whatToBuild, NormalToBuildLocation(buildLocation), buildRelative )
                        if not eng.NotBuildingThread then
							threadStarted = true
                            eng.NotBuildingThread = eng:ForkThread(eng.PlatoonHandle.WatchForNotBuildingSorian)
                        end
                    end
                end
				if not threadStarted and not eng.NotBuildingThread then
					eng.NotBuildingThread = eng:ForkThread(eng.PlatoonHandle.WatchForNotBuildingSorian)
				end
                commandDone = true             
            else
                # we can't move there, so remove it from our build queue
                table.remove(eng.EngineerBuildQueue, 1)
            end
        end
        
        # final check for if we should disband
        if not eng or eng:IsDead() or table.getn(eng.EngineerBuildQueue) == 0 then
            if eng.PlatoonHandle and aiBrain:PlatoonExists(eng.PlatoonHandle) then
                #LOG("*AI DEBUG: Disbanding Engineer Platoon in ProcessBuildCommand " .. eng.Sync.id)
				#if EntityCategoryContains( categories.COMMAND, eng ) then
				#	LOG("*AI DEBUG: Commander Platoon Disbanded in ProcessBuildCommand")
				#end
                eng.PlatoonHandle:PlatoonDisband()
            end
            if eng then eng.ProcessBuild = nil end
            return
        end
        if eng then eng.ProcessBuild = nil end       
    end,
	
    MergeWithNearbyPlatoonsSorian = function(self, planName, radius, fullrestart)
        # check to see we're not near an ally base

        local aiBrain = self:GetBrain()
        if not aiBrain then
            return
        end
        
        if self.UsingTransport then 
            return 
        end
        
        local platPos = self:GetPlatoonPosition()
        if not platPos then
            return
        end
        
        local radiusSq = radius*radius
        # if we're too close to a base, forget it
        if aiBrain.BuilderManagers then
            for baseName, base in aiBrain.BuilderManagers do
				local baseRadius = base.FactoryManager:GetLocationRadius()
                if VDist2Sq(platPos[1], platPos[3], base.Position[1], base.Position[3]) <= (baseRadius * baseRadius) + (3 * radiusSq) then
                    return
                end    
            end
        end
        
        AlliedPlatoons = aiBrain:GetPlatoonsList()
        local bMergedPlatoons = false
        for _,aPlat in AlliedPlatoons do
            if aPlat:GetPlan() != planName then
                continue
            end
            if aPlat == self then
                continue
            end
            if aPlat.UsingTransport then
                continue
            end
            
            local allyPlatPos = aPlat:GetPlatoonPosition()
            if not allyPlatPos or not aiBrain:PlatoonExists(aPlat) then
                continue
            end
            
            AIAttackUtils.GetMostRestrictiveLayer(self)
            AIAttackUtils.GetMostRestrictiveLayer(aPlat)
            
            # make sure we're the same movement layer type to avoid hamstringing air of amphibious
            if self.MovementLayer != aPlat.MovementLayer then
                continue
            end
            
            if VDist2Sq(platPos[1], platPos[3], allyPlatPos[1], allyPlatPos[3]) <= radiusSq then
                local units = aPlat:GetPlatoonUnits()
                local validUnits = {}
                local bValidUnits = false
                for _,u in units do
                    if not u:IsDead() and not u:IsUnitState( 'Attached' ) then
                        table.insert(validUnits, u)
                        bValidUnits = true
                    end
                end
                if not bValidUnits then
                    continue
                end
				#LOG("*AI DEBUG: Merging platoons " .. self.BuilderName .. ": (" .. platPos[1] .. ", " .. platPos[3] .. ") and " .. aPlat.BuilderName .. ": (" .. allyPlatPos[1] .. ", " .. allyPlatPos[3] .. ")")
                aiBrain:AssignUnitsToPlatoon( self, validUnits, 'Attack', 'GrowthFormation' )
                bMergedPlatoons = true
            end
        end
        if bMergedPlatoons then
			if fullrestart then
				self:Stop()
				self:SetAIPlan(planName)
			else
				self:StopAttack()
			end
        end
    end,
	
    NameUnitsSorian = function(self)
        local units = self:GetPlatoonUnits()
		local AINames = import('/lua/AI/sorianlang.lua').AINames
        if units and table.getn(units) > 0 then
            for k, v in units do
                local ID = v:GetUnitId()
                if AINames[ID] then
                    local num = Random(1, table.getn(AINames[ID]))
                    v:SetCustomName(AINames[ID][num])
                end
            end
        end
    end,
}

end
