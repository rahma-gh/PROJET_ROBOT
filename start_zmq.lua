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
    
    -- Try to find and initialize ZMQ addon
    print("[START_ZMQ] Attempting to start ZeroMQ remote API server...")
    
    -- Method 1: Try by name
    local addonHandle = sim.getScript(sim.scripttype_addonscript, -1, "ZeroMQ remote API server")
    if addonHandle ~= -1 then
        print("[START_ZMQ] Found ZeroMQ addon with handle: " .. addonHandle)
        local result = sim.callScriptFunction("sysCall_init", addonHandle)
        print("[START_ZMQ] Initialization result: " .. tostring(result))
        print("[START_ZMQ] ✅ ZeroMQ remote API server initialized successfully via name")
    else
        print("[START_ZMQ] ❌ Addon 'ZeroMQ remote API server' not found by name")
        
        -- Method 2: Try by index (sometimes it's just called "zmq")
        local zmqHandle = sim.getScript(sim.scripttype_addonscript, -1, "zmq")
        if zmqHandle ~= -1 then
            print("[START_ZMQ] Found 'zmq' addon with handle: " .. zmqHandle)
            local result = sim.callScriptFunction("sysCall_init", zmqHandle)
            print("[START_ZMQ] Initialization result: " .. tostring(result))
            print("[START_ZMQ] ✅ ZMQ addon initialized successfully via 'zmq'")
        else
            print("[START_ZMQ] ❌ Addon 'zmq' not found")
            
            -- Method 3: Try to find any addon with ZMQ in name
            if addons then
                for i, addon in ipairs(addons) do
                    if string.find(string.lower(tostring(addon)), "zmq") or 
                       string.find(string.lower(tostring(addon)), "zeromq") then
                        print("[START_ZMQ] Found potential ZMQ addon: " .. tostring(addon))
                        -- Try to get handle by name
                        local handle = sim.getScript(sim.scripttype_addonscript, -1, addon)
                        if handle ~= -1 then
                            local result = sim.callScriptFunction("sysCall_init", handle)
                            print("[START_ZMQ] Initialization result: " .. tostring(result))
                        end
                    end
                end
            end
        end
    end
    
    -- Force port configuration
    print("[START_ZMQ] Configuring ZMQ ports...")
    sim.setNamedStringParam("zmqRemoteApi.rpcPort", "23000")
    sim.setNamedStringParam("zmqRemoteApi.cntPort", "23001")
    
    -- Verify ports are set
    local rpcPort = sim.getNamedStringParam("zmqRemoteApi.rpcPort")
    local cntPort = sim.getNamedStringParam("zmqRemoteApi.cntPort")
    print("[START_ZMQ] RPC Port configured as: " .. (rpcPort or "not set"))
    print("[START_ZMQ] Cnt Port configured as: " .. (cntPort or "not set"))
    
    -- Try to start ZMQ addon via system function if available
    print("[START_ZMQ] Attempting to start via system function...")
    local success, result = pcall(function()
        return sim.startZmqRemoteApiServer()
    end)
    
    if success then
        print("[START_ZMQ] sim.startZmqRemoteApiServer() result: " .. tostring(result))
    else
        print("[START_ZMQ] sim.startZmqRemoteApiServer() not available or error: " .. tostring(result))
    end
    
    print("==========================================")
    print("[START_ZMQ] Initialization complete")
    print("==========================================")
    
    -- Return non-zero to keep script running
    return 0
end

function sysCall_actuation()
    -- Keep the script alive
end

function sysCall_sensing()
    -- Optional: Check if ZMQ is still running
    -- This runs periodically
end
