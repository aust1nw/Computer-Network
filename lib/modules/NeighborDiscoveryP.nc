#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channels.h"

#define INF 9999

generic module NeighborDiscoveryP() {
    provides interface NeighborDiscovery;

    uses interface Timer<TMilli> as NeighborTimer;
    uses interface Timer<TMilli> as CostTimer;
    uses interface Random;

    uses interface Packet;
    uses interface Receive as NeighborReceive;

    uses interface SimpleSend as Sender;
}

implementation {
    uint16_t neighborList[20];
    uint16_t previousNeighborList[20];
    uint16_t linkCosts[20] = {0}; 
    uint8_t neighborCount = 0;
    uint8_t previousNeighborCount = 0;
    
    // RTT measurement variables
    uint32_t pingStartTime = 0;
    uint16_t currentSeq = 0;
    bool discoveryInProgress = FALSE;

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t *payload, uint8_t length){
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;

        if(payload != NULL && length > 0){
            memcpy(Package->payload, payload, length);
        }
    }

    bool isNeighbor(uint16_t nodeID){
        uint8_t i;
        for(i = 0; i < neighborCount; i++){
            if(neighborList[i] == nodeID){
                return TRUE;
            }
        }
        return FALSE;
    }
    
    uint8_t getNeighborIndex(uint16_t nodeID){
        uint8_t i;
        for(i = 0; i < neighborCount; i++){
            if(neighborList[i] == nodeID){
                return i;
            }
        }
        return 0xFF;
    }
    
    uint8_t addNeighbor(uint16_t nodeID, uint16_t cost){
        if(!isNeighbor(nodeID) && neighborCount < 20){
            neighborList[neighborCount] = nodeID;
            linkCosts[neighborCount] = cost;
            neighborCount++;
            return neighborCount - 1;
        }
        return getNeighborIndex(nodeID);
    }
    
    bool neighborsHaveChanged(){
        uint8_t i, j;
        
        if(neighborCount != previousNeighborCount){
            return TRUE;
        }
        
        for(i = 0; i < neighborCount; i++){
            bool found = FALSE;
            for(j = 0; j < previousNeighborCount; j++){
                if(neighborList[i] == previousNeighborList[j]){
                    found = TRUE;
                    break;
                }
            }
            if(!found){
                return TRUE;
            }
        }
        return FALSE;
    }

    command void NeighborDiscovery.start(){
        uint8_t i;
        for(i = 0; i < 20; i++){
            linkCosts[i] = INF;
        }
        call NeighborTimer.startOneShot(1000 + (uint16_t)(call Random.rand16() % 1000));
    }

    task void findNeighbors(){
        pack sendPacket;
        uint16_t destination = AM_BROADCAST_ADDR;
        uint8_t *payload = 0;
        uint16_t nTTL = 1;
        
        memcpy(previousNeighborList, neighborList, sizeof(neighborList));
        previousNeighborCount = neighborCount;
        currentSeq++;
        discoveryInProgress = TRUE;
        pingStartTime = call NeighborTimer.getNow();
        
        makePack(&sendPacket, TOS_NODE_ID, destination, nTTL, PROTOCOL_NEIGHBORPING, currentSeq, payload, 0);
        call Sender.send(sendPacket, destination);

        call NeighborTimer.startPeriodic(10000 + (uint16_t)(call Random.rand16() % 1000));
        
        call CostTimer.startOneShot(2000);
    }

    event void NeighborTimer.fired(){
        post findNeighbors();
    }
    
    event void CostTimer.fired(){
        discoveryInProgress = FALSE;
        
        if(neighborsHaveChanged()){
            dbg(NEIGHBOR_CHANNEL, "Node %u: Neighbors changed! Signaling...\n", TOS_NODE_ID);
            signal NeighborDiscovery.neighborsChanged();
        }
    }

    command void NeighborDiscovery.printNeighbors(){    
        uint8_t i;
        dbg(NEIGHBOR_CHANNEL, "Node %u Neighbors (%u):\n", TOS_NODE_ID, neighborCount);
        for(i = 0; i < neighborCount; i++){
            dbg(NEIGHBOR_CHANNEL, "  Neighbor %u: Node %u (Cost: %u)\n", i, neighborList[i], linkCosts[i]);
        }
    }

    event message_t* NeighborReceive.receive(message_t* msg, void* payload, uint8_t len){
        if(len == sizeof(pack)){
            pack* myMsg = (pack*) payload;
            call NeighborDiscovery.receiveNeighbors(myMsg->protocol, myMsg->src, &neighborCount);
            return msg;
        }
        return msg;
    }

    command void NeighborDiscovery.receiveNeighbors(uint16_t protocol, uint16_t src, uint8_t* idx){
        pack returnPacket;
        uint8_t *payload = 0;
        uint16_t repTTL = 1;
        uint32_t now;
        uint32_t rtt;
        uint16_t cost;
        uint8_t neighborIdx;

        if(src == TOS_NODE_ID){
            return;
        }

        if(protocol == PROTOCOL_NEIGHBORREPLY){  
            // Calculate RTT and cost
            if(discoveryInProgress) {
                now = call NeighborTimer.getNow();
        
                // Handle timer wrap-around with reasonable bounds
                if(now >= pingStartTime) {
                    rtt = now - pingStartTime;
                } else {
                    // Timer wrapped around - use maximum reasonable RTT
                    rtt = 5000; // 5 seconds maximum reasonable RTT
                }
                
                // Convert RTT to cost with reasonable bounds
                cost = (rtt / 10); // Scale down RTT to get reasonable costs
                if(cost < 1){
                    cost = 1;
                }
                if(cost > 100){
                    cost = 100; // Max reasonable cost
                } 
                
                dbg(NEIGHBOR_CHANNEL, "Node %u: RTT=%u, cost=%u\n", TOS_NODE_ID, rtt, cost);
                
                neighborIdx = getNeighborIndex(src);
                if(neighborIdx != 0xFF){
                    // Update existing neighbor cost
                    linkCosts[neighborIdx] = cost;
                } 
                else if(*idx < 20){
                    // Add new neighbor
                    neighborList[*idx] = src;
                    linkCosts[*idx] = cost;
                    (*idx)++;
                }
            }
        }
        else if(protocol == PROTOCOL_NEIGHBORPING){ 
            if(!isNeighbor(src) && *idx < 20){
                neighborList[*idx] = src;
                linkCosts[*idx] = 1;  // Default cost
                (*idx)++;
            }
            
            makePack(&returnPacket, TOS_NODE_ID, src, repTTL, PROTOCOL_NEIGHBORREPLY, currentSeq, payload, 0);
            call Sender.send(returnPacket, src);
        }
    }

    command uint8_t NeighborDiscovery.getCount(){
        return neighborCount;
    }
    
    command uint32_t NeighborDiscovery.getList(uint8_t count){
        if(count < neighborCount){
            return neighborList[count];
        }
        return 0;
    }
    
    command uint16_t NeighborDiscovery.getLinkCost(uint16_t neighborId){
        uint8_t idx = getNeighborIndex(neighborId);
        if(idx != 0xFF){
            return linkCosts[idx];
        }
        return 0xFFFF;
    }
    
    command uint16_t* NeighborDiscovery.getNeighborList(){
        return neighborList;
    }
    
    command uint16_t* NeighborDiscovery.getCostList(){
        return linkCosts;
    }
}