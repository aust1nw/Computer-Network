#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/LSA.h"
#include "../../includes/route_entry.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channels.h"

#define INF 0xFFFF

generic module LSRoutingP(){
    provides interface LSRouting;
    
    uses interface NeighborDiscovery as ND;
    uses interface Flooding;
    uses interface Timer<TMilli> as LSATimer;
    uses interface Timer<TMilli> as computeTimer;
    uses interface Random;
    uses interface Hashmap<route_entry> as RoutingTable;
    uses interface Graph;

    uses interface Queue<LSA*> as LSAQueue;
    uses interface Pool<LSA> as LSAPool;
}

implementation{
    uint16_t mySeq = 0;
    LSA LSDB[MAX_NODES];
    uint16_t lsaCache[MAX_NODES];
    bool initialized = FALSE;
    uint32_t lsaTimeStamps[MAX_NODES];

    command void LSRouting.start(){
        uint8_t i;
        // dbg(ROUTING_CHANNEL, "Node %u: Starting LS Routing module\n", TOS_NODE_ID);
        for(i = 0; i < MAX_NODES; i++){
            lsaCache[i] = 0;
            LSDB[i].nodeID = i;
            LSDB[i].seq = 0;
            LSDB[i].numNeighbors = 0;
        }
        mySeq = 0;
        
        call Graph.clearGraph();
        
        initialized = TRUE;
        // dbg(ROUTING_CHANNEL, "Node %u: LS Routing initialized\n", TOS_NODE_ID);

        call ND.start();
        call Flooding.start();
        
        call LSATimer.startOneShot(5000 + (uint16_t)(call Random.rand16() % 1000));
    }

    task void sendLSA(){
        LSA packet;
        uint8_t i;
        uint8_t numNeighbors;
        uint16_t* neighborList;
        uint32_t* costList;
        
        // dbg(ROUTING_CHANNEL, "Node %u: Preparing to send LSA\n", TOS_NODE_ID);
        if(!initialized){
            return;
        }
        
        numNeighbors = call ND.getCount();
        call Graph.clearNodeEdges(TOS_NODE_ID);

        // if(numNeighbors == 0){
        //     dbg(ROUTING_CHANNEL, "Node %u: No neighbors, not sending LSA\n", TOS_NODE_ID);
        //     return;
        // }
        
        neighborList = call ND.getNeighborList();
        costList = call ND.getCostList();

        packet.nodeID = TOS_NODE_ID;
        packet.seq = ++mySeq;
        packet.numNeighbors = numNeighbors;
        
        for(i = 0; i < numNeighbors && i < MAX_NEIGHBORS; i++){
            packet.neighbors[i] = neighborList[i];
            packet.costs[i] = costList[i];
        }

        // sdbg(ROUTING_CHANNEL, "Node %u: Sending LSA (seq=%u, neighbors=%u)\n", TOS_NODE_ID, packet.seq, packet.numNeighbors);
        
        LSDB[TOS_NODE_ID] = packet;
        lsaCache[TOS_NODE_ID] = packet.seq;
        
        for(i = 0; i < packet.numNeighbors; i++){
            uint16_t n = packet.neighbors[i];
            uint16_t c = (uint16_t)packet.costs[i];

            call Graph.addEdge(TOS_NODE_ID, n, c);
            // call Graph.addEdge(n, TOS_NODE_ID, c);
        }

        call computeTimer.startOneShot(500);

        if(!call Flooding.isReady()){
            // dbg(ROUTING_CHANNEL, "Node %u: Flooding module not ready, not sending LSA\n", TOS_NODE_ID);
            return;
        }

        // dbg(ROUTING_CHANNEL, "Flooding now\n");
        call Flooding.floodLSA((uint8_t*)&packet, sizeof(LSA));
    }

    task void computeRoutes(){
        uint16_t i, j, u, v;
        uint16_t source = TOS_NODE_ID;
        uint32_t dist[MAX_NODES];
        uint16_t prev[MAX_NODES]; 
        bool visited[MAX_NODES];
        uint32_t minDist; // Correct, as this tracks the total path cost
        uint32_t* oldKeys = call RoutingTable.getKeys();
        uint16_t oldSize = call RoutingTable.size();
        
        for(j = 0; j < oldSize; j++) {
            call RoutingTable.remove(oldKeys[j]);
        }

        // Initialize Dijkstra arrays
        for(i = 0; i < MAX_NODES; i++){
            dist[i] = INF;
            prev[i] = 0xFFFF; 
            visited[i] = FALSE;
        }
        dist[source] = 0;

        // Simple Dijkstra - find SINGLE shortest path
        for(i = 0; i < MAX_NODES; i++){
            // Find unvisited node with minimum distance
            minDist = INF;
            u = 0xFFFF;
            
            for(v = 0; v < MAX_NODES; v++){
                if(!visited[v] && dist[v] < minDist){
                    minDist = dist[v];
                    u = v;
                }
            }
            
            if(u == 0xFFFF || minDist == INF) break;
            
            visited[u] = TRUE;
            
            for(v = 0; v < MAX_NODES; v++){
                uint16_t linkCost = call Graph.getCost(u, v); 
                
                if(dist[u] != INF && linkCost != 0xFFFF){  
                    uint32_t newDist = dist[u] + (uint32_t)linkCost;
                    
                    if(newDist < dist[v]){
                        dist[v] = newDist;
                        prev[v] = u;
                    }
                }
            }
        }

        // Store routes in routing table (Path Tracing)
        for(i = 0; i < MAX_NODES; i++){
            uint16_t nextHop = i;
            route_entry r;
            
            // Special case: destination is myself
            if(i == source) {
                r.primaryNextHop = source;
                r.primaryCost = 0;
                call RoutingTable.insert(i, r);
                continue;
            }
            
            // If unreachable
            if(prev[i] == 0xFFFF || dist[i] == INF) {
                call RoutingTable.remove(i);
                continue;
            }
            
            // Walk back to find first hop from source
            while (prev[nextHop] != source && prev[nextHop] != 0xFFFF) {
                nextHop = prev[nextHop];
            }
            
            if(prev[nextHop] == 0xFFFF) {
                // Somehow chain died – treat as unreachable
                call RoutingTable.remove(i);
                continue;
            }

            if(dist[i] > INF) dist[i] = INF;

            // Install route
            r.primaryNextHop = nextHop;
            r.primaryCost = (uint16_t)dist[i];
            call RoutingTable.insert(i, r);
        }
    }

    task void processLSAQueueTask() {
        uint8_t processed = 0;
        while (!call LSAQueue.empty() && processed < 5) {
            LSA* lsa = call LSAQueue.head(); 
            uint8_t i;

            lsaTimeStamps[lsa->nodeID] = call LSATimer.getNow();
            
            if(lsaCache[lsa->nodeID] == 0 || lsa->seq > lsaCache[lsa->nodeID]){
                call Graph.clearNodeEdges(lsa->nodeID);
                
                for(i = 0; i < lsa->numNeighbors; i++){
                    uint16_t u = lsa->nodeID;
                    uint16_t v = lsa->neighbors[i];
                    uint16_t c = lsa->costs[i];

                    call Graph.addEdge(u, v, c);
                }

                lsaCache[lsa->nodeID] = lsa->seq;
                LSDB[lsa->nodeID] = *lsa;

                // dbg(ROUTING_CHANNEL, "Node %u: Updated LSDB entry for node %u (seq=%u)\n", TOS_NODE_ID, lsa->nodeID, lsa->seq);
                
                call computeTimer.startOneShot(200);
            } 
            else {
                // dbg(ROUTING_CHANNEL, "Node %u: Ignoring old/duplicate LSA from node %u\n", TOS_NODE_ID, lsa->nodeID);
            }
            
            call LSAQueue.dequeue();
            call LSAPool.put(lsa);
            processed++;
        }

        if(!call LSAQueue.empty()){
            post processLSAQueueTask();
        }
    }

    command uint16_t LSRouting.getCost(uint16_t dest){
        return call LSRouting.getRouteCost(dest, 0);
    }

    command uint16_t LSRouting.getRouteCost(uint16_t dest, uint8_t routeIndex){
        route_entry route;
        uint32_t key = (uint32_t)dest;
        
        if (dest >= MAX_NODES || dest == 0 || !call RoutingTable.contains(key)){
            return INF;
        }
        
        route = call RoutingTable.get(key);
        
        switch(routeIndex) {
            case 0: return route.primaryCost;
            default: return INF;
        }
    }

    command uint16_t LSRouting.getBestNextHop(uint16_t dest) {
        route_entry route;
        uint32_t key = (uint32_t)dest;
        // dbg(GENERAL_CHANNEL, "Node %u: LSRouting.getBestNextHop(%u) INTERFACE CALLED\n", TOS_NODE_ID, dest);
        
        // if(dest >= MAX_NODES || dest == TOS_NODE_ID || !call RoutingTable.contains(key)){
        //     dbg(GENERAL_CHANNEL,
        //     "Node %u: getBestNextHop(%u) → NO ROUTE\n",
        //     TOS_NODE_ID, dest);
        //     return 0;
        // }
        
        route = call RoutingTable.get(key);
        //  dbg(GENERAL_CHANNEL,
        // "Node %u: getBestNextHop(%u) → %u (cost=%u)\n",
        // TOS_NODE_ID, dest, route.primaryNextHop, route.primaryCost);

        if(route.primaryCost != INF){
            return route.primaryNextHop;
        }
        
        return 0;
    }

    command void LSRouting.printRouteTable(){
        uint16_t i;
        route_entry route;
        uint32_t* keys = call RoutingTable.getKeys();
        uint16_t numKeys = call RoutingTable.size();
        uint32_t key;
        
        dbg(GENERAL_CHANNEL, "Node %u Routing Table:\n", TOS_NODE_ID);
        
        for(i = 0; i < numKeys; i++){
            uint16_t destID = (uint16_t)keys[i];
            key = keys[i];
            route = call RoutingTable.get(key);
            
            if(key == 0 || route.primaryCost == INF){
                continue;
            }
            
            dbg(GENERAL_CHANNEL, "  Destination %u:\n", destID);
            dbg(GENERAL_CHANNEL, "    Primary Hop: %u; Cost: %u\n", route.primaryNextHop, route.primaryCost);
        }
    }

    event void LSATimer.fired(){
        // dbg(ROUTING_CHANNEL, "Node %u: Periodic LSA timer fired\n", TOS_NODE_ID);
        post sendLSA();
    }

    event void ND.neighborsChanged(){
        // uint32_t* keys = call RoutingTable.getKeys();
        // uint16_t numKeys = call RoutingTable.size();
        // uint16_t i;

        // dbg(GENERAL_CHANNEL, "Node %u: *** ND.neighborsChanged() EVENT RECEIVED ***\n", TOS_NODE_ID);
        // dbg(GENERAL_CHANNEL, "Node %u: Neighbor list changed, clearing ALL routes and recomputing\n", TOS_NODE_ID);
        
        // for(i = 0; i < numKeys; i++) {
        //     call RoutingTable.remove(keys[i]);
        // }
        
        // mySeq++;

        // dbg(GENERAL_CHANNEL, "Node %u: Triggering LSA broadcast after neighbor change\n", TOS_NODE_ID);
        
        post sendLSA();
    }

    event void computeTimer.fired(){
        post computeRoutes();
    }

    event void Flooding.receivedLSA(uint16_t src, uint8_t* lsaData){
        LSA* lsaBuf = NULL;
        
        if (!call LSAPool.empty()) {
            lsaBuf = call LSAPool.get();
        }
            
        if (lsaBuf != NULL) {
            *lsaBuf = *(LSA*)lsaData; 
            
            if (call LSAQueue.enqueue(lsaBuf) == SUCCESS) {
                post processLSAQueueTask(); 
            } else {
                call LSAPool.put(lsaBuf);
            }
        }
    }
}