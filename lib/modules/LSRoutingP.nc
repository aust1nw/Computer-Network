#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/LSA.h"
#include "../../includes/route_entry.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channels.h"

#define INF 9999

generic module LSRoutingP(){
    provides interface LSRouting;
    
    uses interface NeighborDiscovery as ND;
    uses interface Flooding;
    uses interface Timer<TMilli> as LSATimer;
    uses interface Hashmap<route_entry> as RoutingTable;
    uses interface Graph;
}

implementation{
    uint16_t mySeq = 0;
    LSA LSDB[MAX_NODES];
    uint16_t lsaCache[MAX_NODES];
    
    uint16_t dist[MAX_NODES];
    bool visited[MAX_NODES];
    int prevNode[MAX_NODES];
    
    bool initialized = FALSE;

    uint16_t getNextHopFromPath(uint16_t dest, uint16_t* preNode, uint16_t source){
        uint16_t next = dest;
        if(dest == source || preNode[dest] == dest){
            return dest;
        }
        while(preNode[next] != source && preNode[next] != next){
            next = preNode[next];
        }
        return next;
    }

    // Check if path would be too similar to previous paths
    bool isSamePath(uint16_t u, uint16_t v, uint16_t preNode[3][MAX_NODES], uint8_t k, uint16_t source){
        uint16_t currentNextHop = getNextHopFromPath(v, preNode[k], source);
        uint8_t i;
        
        for(i = 0; i < k; i++){
            uint16_t prevNextHop = getNextHopFromPath(v, preNode[i], source);
            if(currentNextHop == prevNextHop){
                return TRUE;
            }
        }
        return FALSE;
    }

    command void LSRouting.start(){
        uint8_t i;
        dbg(ROUTING_CHANNEL, "Node %u: Starting LS Routing module\n", TOS_NODE_ID);
        for(i = 0; i < MAX_NODES; i++){
            lsaCache[i] = 0;
            LSDB[i].nodeID = i;
            LSDB[i].seq = 0;
            LSDB[i].numNeighbors = 0;
        }
        mySeq = 0;
        
        call Graph.clearGraph();
        
        initialized = TRUE;
        dbg(ROUTING_CHANNEL, "Node %u: LS Routing initialized\n", TOS_NODE_ID);

        call Flooding.start();
        
        call LSATimer.startPeriodic(10000);
    }

    command void LSRouting.sendLSA(){
        LSA packet;
        uint8_t i;
        uint8_t numNeighbors;
        uint16_t* neighborList;
        uint16_t* costList;
        
        dbg(ROUTING_CHANNEL, "Node %u: Preparing to send LSA\n", TOS_NODE_ID);
        if(!initialized){
            return;
        }
        
        numNeighbors = call ND.getCount();
        
        if(numNeighbors == 0){
            dbg(ROUTING_CHANNEL, "Node %u: No neighbors, not sending LSA\n", TOS_NODE_ID);
            return;
        }

        if(!call Flooding.isReady()){
            dbg(ROUTING_CHANNEL, "Node %u: Flooding module not ready, not sending LSA\n", TOS_NODE_ID);
            return;
        }
        
        packet.nodeID = TOS_NODE_ID;
        packet.seq = ++mySeq;
        packet.numNeighbors = numNeighbors;

        neighborList = call ND.getNeighborList();
        costList = call ND.getCostList();
        
        for (i = 0; i < numNeighbors && i < MAX_NEIGHBORS; i++) {
            packet.neighbors[i] = neighborList[i];
            packet.costs[i] = costList[i];
        }

        dbg(ROUTING_CHANNEL, "Node %u: Sending LSA (seq=%u, neighbors=%u)\n", TOS_NODE_ID, packet.seq, packet.numNeighbors);
        
        LSDB[TOS_NODE_ID] = packet;
        lsaCache[TOS_NODE_ID] = packet.seq;
        
        for(i = 0; i < packet.numNeighbors; i++){
            call Graph.addEdge(TOS_NODE_ID, packet.neighbors[i], packet.costs[i]);
        }
        dbg(ROUTING_CHANNEL, "Flooding now\n");
        call Flooding.floodLSA((uint8_t*)&packet, sizeof(LSA));
    }

    command void LSRouting.handleLSA(uint16_t src, uint8_t* lsaData){
        LSA* lsa;
        uint8_t i;
        
        lsa = (LSA*)lsaData;
        
        dbg(ROUTING_CHANNEL, "Node %u: Received LSA from node %u (seq=%u)\n", TOS_NODE_ID, lsa->nodeID, lsa->seq);
        
        if(lsaCache[lsa->nodeID] == 0 || lsa->seq > lsaCache[lsa->nodeID]){
            lsaCache[lsa->nodeID] = lsa->seq;
            LSDB[lsa->nodeID] = *lsa;

            dbg(ROUTING_CHANNEL, "Node %u: Updated LSDB entry for node %u (seq=%u, neighbors=%u)\n", TOS_NODE_ID, lsa->nodeID, lsa->seq, lsa->numNeighbors);
            
            for(i = 0; i < lsa->numNeighbors; i++){
                call Graph.addEdge(lsa->nodeID, lsa->neighbors[i], lsa->costs[i]);
                dbg(ROUTING_CHANNEL, "  Added edge: %u -> %u (cost %u)\n", lsa->nodeID, lsa->neighbors[i], lsa->costs[i]);
            }
            call LSRouting.computeRoutes();
        } 
        else {
            dbg(ROUTING_CHANNEL, "Node %u: Ignoring old/duplicate LSA from node %u (seq=%u <= cached %u)\n", TOS_NODE_ID, lsa->nodeID, lsa->seq, lsaCache[lsa->nodeID]);
        }
    }

    command void LSRouting.computeRoutes(){
    uint16_t i, j, k, u, v, minDist;
    uint16_t source = TOS_NODE_ID;
    
    // Arrays for three shortest paths
    uint16_t distance[3][MAX_NODES];
    uint16_t preNode[3][MAX_NODES];
    bool visit[MAX_NODES];
    
    dbg(ROUTING_CHANNEL, "Node %u: Computing primary + 2 backup routes...\n", TOS_NODE_ID);

    // Initialize ALL paths to INF
    for(k = 0; k < 3; k++){
        for(i = 0; i < MAX_NODES; i++){
            distance[k][i] = INF;
            preNode[k][i] = i;  // Initialize to self
        }
        distance[k][source] = 0;  // Distance to self is 0
    }
    
    // Compute primary path (standard Dijkstra)
    for(k = 0; k < 3; k++){
        // Reset visited array for this path
        for(i = 0; i < MAX_NODES; i++){
            visit[i] = FALSE;
        }
        
        // Standard Dijkstra for k-th path
        for(i = 0; i < MAX_NODES; i++){
            // Find unvisited node with minimum distance
            uint16_t neighborCount;
            uint16_t* neighbors;
            minDist = INF;
            u = MAX_NODES;
            
            for(j = 0; j < MAX_NODES; j++){
                if(!visit[j] && distance[k][j] < minDist){
                    minDist = distance[k][j];
                    u = j;
                }
            }
            
            if(u == MAX_NODES || minDist == INF){
                break;
            }

            visit[u] = TRUE;
            neighborCount = call Graph.getNeighborCount(u);

            if(neighborCount == 0){
                continue;
            }
            
            neighbors = call Graph.getNeighbors(u);

            if(neighbors == NULL){
                continue;
            }
            
            // Update distances to neighbors
            for(j = 0; j < neighborCount; j++){
                uint16_t edgeCost;
                uint32_t newDist;
                v = neighbors[j];
                if(visit[v]){
                    continue;
                }
                
                edgeCost = call Graph.getCost(u, v);
                if(edgeCost == 0xFFFF){
                    continue;
                }
                
                newDist = distance[k][u] + edgeCost;
                
                // For backup paths, check if this path is too similar to previous ones
                if(k > 0){
                    // Check if using this edge would create the same next hop
                    uint16_t potentialNextHop = getNextHopFromPath(v, preNode[k], source);
                    bool skipEdge = FALSE;
                    uint8_t prevK;
                    
                    for(prevK = 0; prevK < k; prevK++){
                        uint16_t existingNextHop = getNextHopFromPath(v, preNode[prevK], source);
                        if (potentialNextHop == existingNextHop) {
                            skipEdge = TRUE;
                            break;
                        }
                    }
                    
                    if(skipEdge){
                        continue;
                    }
                }
                
                if(newDist < distance[k][v]){
                    distance[k][v] = newDist;
                    preNode[k][v] = u;
                }
            }
        }
    }

        // Store routes in routing table
        for(i = 0; i < MAX_NODES; i++){
            uint32_t key = (uint32_t)i;
            route_entry newRoute;

            if(i == 0 || i == source){
                continue;
            }
            
            newRoute.dest = i;
            
            // Primary route
            newRoute.primaryCost = distance[0][i];
            newRoute.primaryNextHop = getNextHopFromPath(i, preNode[0], source);
            
            // First backup route
            newRoute.backup1Cost = distance[1][i];
            newRoute.backup1NextHop = getNextHopFromPath(i, preNode[1], source);
            
            // Second backup route  
            newRoute.backup2Cost = distance[2][i];
            newRoute.backup2NextHop = getNextHopFromPath(i, preNode[2], source);
            
            // Count available routes
            newRoute.routeCount = 0;
            if(distance[0][i] != INF){
                newRoute.routeCount++;
            }
            if(distance[1][i] != INF && newRoute.backup1NextHop != newRoute.primaryNextHop){
                newRoute.routeCount++;
            }
            if(distance[2][i] != INF && newRoute.backup2NextHop != newRoute.primaryNextHop && newRoute.backup2NextHop != newRoute.backup1NextHop){
                newRoute.routeCount++;
            }
            
            call RoutingTable.insert(key, newRoute);
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
            case 1: return route.backup1Cost;
            case 2: return route.backup2Cost;
            default: return INF;
        }
    }

    bool isRouteAlive(uint16_t nextHop){
        uint8_t neighborCount;
        uint8_t i;
        if(nextHop == TOS_NODE_ID){
            return TRUE;
        }
        neighborCount = call ND.getCount();
        for(i = 0; i < neighborCount; i++){
            if(call ND.getList(i) == nextHop){
                return TRUE;
            }
        }
        return FALSE;
    }

    // Get best available route (automatically falls back to backups)
    command uint16_t LSRouting.getBestNextHop(uint16_t dest) {
        route_entry route;
        uint32_t key = (uint32_t)dest;
        dbg(GENERAL_CHANNEL, "Node %u: LSRouting.getBestNextHop(%u) INTERFACE CALLED\n", TOS_NODE_ID, dest);
        
        if(dest >= MAX_NODES || dest == 0 || !call RoutingTable.contains(key)){
            return 0;
        }
        
        route = call RoutingTable.get(key);
        
        // Check routes in order: primary -> backup1 -> backup2
        if(route.primaryCost != INF && isRouteAlive(route.primaryNextHop)){
            return route.primaryNextHop;
        } 
        else if(route.backup1Cost != INF && isRouteAlive(route.backup1NextHop)){
            return route.backup1NextHop;
        } 
        else if(route.backup2Cost != INF && isRouteAlive(route.backup2NextHop)){
            return route.backup2NextHop;
        }
        
        return 0;
    }

    // Mark a route as failed and get the next best
    command uint16_t LSRouting.routeFailed(uint16_t dest, uint16_t failedNextHop){
        route_entry route;
        uint32_t key = (uint32_t)dest;
        
        if(!call RoutingTable.contains(key)){
            return 0;
        }
        
        route = call RoutingTable.get(key);
        
        dbg(ROUTING_CHANNEL, "Node %u: Route to %u via %u failed, switching...\n", TOS_NODE_ID, dest, failedNextHop);
        
        // Return the best available route that's not the failed one
        if(route.primaryNextHop != failedNextHop && route.primaryCost != INF && isRouteAlive(route.primaryNextHop)){
            return route.primaryNextHop;
        } 
        else if(route.backup1NextHop != failedNextHop && route.backup1Cost != INF && isRouteAlive(route.backup1NextHop)){
            return route.backup1NextHop;
        } 
        else if(route.backup2NextHop != failedNextHop && route.backup2Cost != INF && isRouteAlive(route.backup2NextHop)){
            return route.backup2NextHop;
        }
        
        return 0;
    }

    // Get route information
    command uint8_t LSRouting.getRouteCount(uint16_t dest){
        route_entry route;
        uint32_t key = (uint32_t)dest;
        
        if(!call RoutingTable.contains(key)){
            return 0;
        }
        
        route = call RoutingTable.get(key);
        return route.routeCount;
    }

    command void LSRouting.printRouteTable(){
        uint16_t i;
        route_entry route;
        uint32_t* keyList;
        uint16_t numKeys;
        uint32_t key;
        
        dbg(GENERAL_CHANNEL, "Node %u Routing Table (Primary + 2 Backups):\n", TOS_NODE_ID);
        
        keyList = call RoutingTable.getKeys();
        numKeys = call RoutingTable.size();
        
        for(i = 0; i < numKeys; i++){
            key = keyList[i];
            route = call RoutingTable.get(key);
            
            if(key == 0 || route.primaryCost == INF){
                continue;
            }
            
            dbg(GENERAL_CHANNEL, "  Destination %u:\n", route.dest);
            dbg(GENERAL_CHANNEL, "    Primary Hop: %u; Cost: %u\n", route.primaryNextHop, route.primaryCost);
            
            if(route.backup1Cost != INF){
                dbg(GENERAL_CHANNEL, "    Backup1 Hop: %u; Cost: %u\n", route.backup1NextHop, route.backup1Cost);
            }
            
            if(route.backup2Cost != INF){
                dbg(GENERAL_CHANNEL, "    Backup2 Hop: %u; Cost: %u\n", route.backup2NextHop, route.backup2Cost);
            }
        }
    }

    command void LSRouting.printLinkState() {
        uint16_t i, j;
        
        dbg(ROUTING_CHANNEL, "Node %u Link State Database:\n", TOS_NODE_ID);
        dbg(ROUTING_CHANNEL, "=============================\n");
        
        for (i = 0; i < MAX_NODES; i++) {
            // Skip nodes that we have no information about
            if(lsaCache[i] == 0){
                continue;
            }
            dbg(ROUTING_CHANNEL, "Node %u (LSA seq=%u):\n", LSDB[i].nodeID, LSDB[i].seq);
            
            if (LSDB[i].numNeighbors == 0) {
                dbg(ROUTING_CHANNEL, "  No neighbors\n");
            } else {
                for (j = 0; j < LSDB[i].numNeighbors && j < MAX_NEIGHBORS; j++) {
                    dbg(ROUTING_CHANNEL, "  -> Node %u (cost %u)\n", 
                        LSDB[i].neighbors[j], LSDB[i].costs[j]);
                }
            }
            dbg(ROUTING_CHANNEL, "\n");
        }
    }

    event void LSATimer.fired(){
        dbg(ROUTING_CHANNEL, "Node %u: Periodic LSA timer fired\n", TOS_NODE_ID);
        call LSRouting.sendLSA();
    }

    event void ND.neighborsChanged(){
        dbg(ROUTING_CHANNEL, "Node %u: Neighbor list changed, triggering LSA\n", TOS_NODE_ID);
        call LSRouting.sendLSA();
    }

    event void Flooding.receivedLSA(uint16_t src, uint8_t* lsaData){
        dbg(ROUTING_CHANNEL, "Node %u: Flooding module reported received LSA from %u\n", TOS_NODE_ID, src);
        call LSRouting.handleLSA(src, lsaData);
    }
}