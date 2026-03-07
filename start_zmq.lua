-- start_zmq.lua
-- Force le démarrage du ZeroMQ remote API server et la simulation au lancement

function sysCall_init()
    print("[START_ZMQ] Tentative de démarrage manuel du ZeroMQ remote API server...")
    
    local addonHandle = sim.getScript(sim.scripttype_addonscript, -1, "ZeroMQ remote API server")
    if addonHandle ~= -1 then
        sim.callScriptFunction("sysCall_init", addonHandle)
        print("[START_ZMQ] ZeroMQ remote API server add-on initialisé avec succès")
    else
        print("[START_ZMQ] ERREUR : add-on 'ZeroMQ remote API server' non trouvé")
    end
    
    -- Optionnel : forcer le port si besoin
    -- sim.setNamedStringParam("zmqRemoteApi.rpcPort", "23000")
    
    print("[START_ZMQ] Démarrage de la simulation...")
    sim.startSimulation()
    print("[START_ZMQ] Simulation démarrée avec succès")
end

function sysCall_cleanup()
    print("[START_ZMQ] Arrêt de la simulation...")
    sim.stopSimulation()
end
