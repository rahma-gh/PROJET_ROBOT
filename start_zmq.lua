-- Force le démarrage du ZeroMQ remote API server au lancement
-- With improved debugging and error handling

function sysCall_init()
    print("==========================================")
    print("[START_ZMQ] Initializing ZMQ remote API server")
    print("==========================================")
    
    -- List all available addons for debugging
    print("[START_ZMQ] Listing available addons:")
    local addons = sim.getAddOns()
    if addons then
        for i, addon in ipairs(addons) do
            print("[START_ZMQ]   Addon " .. i .. ": " .. tostring(addon))
        end
    else
        print("[START_ZMQ] No addons found or unable to list addons")
    end
    
    -- Force port configuration before starting
    print("[START_ZMQ] Configuring ZMQ ports...")
    sim.setNamedStringParam("zmqRemoteApi.rpcPort", "23000")
    sim.setNamedStringParam("zmqRemoteApi.cntPort", "23001")
    sim.setNamedStringParam("zmqRemoteApi.rpcAddress", "0.0.0.0")
    
    -- Verify ports are set
    local rpcPort = sim.getNamedStringParam("zmqRemoteApi.rpcPort")
    local cntPort = sim.getNamedStringParam("zmqRemoteApi.cntPort")
    local rpcAddress = sim.getNamedStringParam("zmqRemoteApi.rpcAddress")
    print("[START_ZMQ] RPC Port configured as: " .. (rpcPort or "not set"))
    print("[START_ZMQ] Cnt Port configured as: " .. (cntPort or "not set"))
    print("[START_ZMQ] RPC Address configured as: " .. (rpcAddress or "not set"))
    
    -- Try to start ZMQ addon via system function (CoppeliaSim 4.6+)
    print("[START_ZMQ] Attempting to start via sim.startZmqRemoteApiServer()...")
    local success, result = pcall(function()
        return sim.startZmqRemoteApiServer()
    end)
    
    if success then
        print("[START_ZMQ] ✅ sim.startZmqRemoteApiServer() succeeded: " .. tostring(result))
    else
        print("[START_ZMQ] ⚠️ sim.startZmqRemoteApiServer() not available or error: " .. tostring(result))
        
        -- Fallback: try to find and initialize the addon
        print("[START_ZMQ] Attempting fallback method...")
        
        -- Try to find by name
        local addonHandle = sim.getScript(sim.scripttype_addonscript, -1, "ZeroMQ remote API server")
        if addonHandle ~= -1 then
            print("[START_ZMQ] Found ZeroMQ addon with handle: " .. addonHandle)
            local result = sim.callScriptFunction("sysCall_init", addonHandle)
            print("[START_ZMQ] Initialization result: " .. tostring(result))
            print("[START_ZMQ] ✅ ZeroMQ remote API server initialized successfully")
        else
            print("[START_ZMQ] ❌ Could not find ZeroMQ addon")
        end
    end
    
    -- Additional delay to ensure ports are bound
    print("[START_ZMQ] Waiting for ports to bind...")
    sim.wait(2)  -- Wait 2 seconds
    
    print("==========================================")
    print("[START_ZMQ] Initialization complete")
    print("==========================================")
    
    return 0
end

function sysCall_actuation()
    -- Keep the script alive
end

function sysCall_sensing()
    -- Optional: Check if ZMQ is still running periodically
    -- This runs every simulation step
end
