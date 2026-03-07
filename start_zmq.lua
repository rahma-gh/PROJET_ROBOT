-- start_zmq.lua
-- Ensure ZeroMQ remote API server is properly initialized

function sysCall_init()
    print("[START_ZMQ] Verifying ZeroMQ remote API server addon...")
    
    local addonHandle = sim.getScript(sim.scripttype_addonscript, -1, "ZeroMQ remote API server")
    if addonHandle ~= -1 then
        print("[START_ZMQ] ✓ ZeroMQ remote API server addon is loaded")
    else
        print("[START_ZMQ] WARNING: ZeroMQ remote API server addon not found in scene")
        print("[START_ZMQ] Make sure the addon is enabled in your .ttt file")
    end
end
