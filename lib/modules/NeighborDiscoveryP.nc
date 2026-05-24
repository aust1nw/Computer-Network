#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channels.h"

#define INF 0xFFFF
#define MAX_NEIGHBORS 20
#define NEIGHBOR_TIMEOUT 60000
#define ALPHA_NUM 4
#define ALPHA_DEN 10 

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
    uint16_t neighborList[MAX_NEIGHBORS];
    uint32_t linkCosts[MAX_NEIGHBORS];
    uint32_t lastSeen[MAX_NEIGHBORS];
    bool neighborActive[MAX_NEIGHBORS];
    uint8_t neighborCount = 0;

    // RTT tracking
    uint32_t rttStartTime[MAX_NEIGHBORS];
    uint32_t rttEWMA[MAX_NEIGHBORS];
    bool waitingForRTT[MAX_NEIGHBORS];
    uint16_t currentSeq = 0;

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
    
    uint8_t addOrUpdateNeighbor(uint16_t id) {
        uint8_t idx = getNeighborIndex(id);

        if(idx != 0xFF) {
            // existing neighbor
            lastSeen[idx] = call NeighborTimer.getNow();
            neighborActive[idx] = TRUE;
            return idx;
        }

        if(neighborCount >= MAX_NEIGHBORS)
            return 0xFF;

        // Add new neighbor
        idx = neighborCount++;
        neighborList[idx] = id;
        neighborActive[idx] = TRUE;
        lastSeen[idx] = call NeighborTimer.getNow();

        // Initialize RTT estimates
        rttEWMA[idx] = 150;  // default
        waitingForRTT[idx] = FALSE;
        linkCosts[idx] = rttEWMA[idx];

        return idx;
    }

    void checkNeighborTimeouts() {
        uint32_t now = call NeighborTimer.getNow();
        bool changed = FALSE;
        uint16_t newList[MAX_NEIGHBORS];
        uint32_t newCosts[MAX_NEIGHBORS];
        uint32_t newSeen[MAX_NEIGHBORS];
        bool newActive[MAX_NEIGHBORS];
        uint8_t newCount = 0;
        uint8_t i;

        for(i = 0; i < neighborCount; i++) {
            if(neighborActive[i] &&
               (now - lastSeen[i]) <= NEIGHBOR_TIMEOUT)
            {
                newList[newCount]  = neighborList[i];
                newCosts[newCount] = linkCosts[i];
                newSeen[newCount]  = lastSeen[i];
                newActive[newCount] = TRUE;
                newCount++;
            }
            else if(neighborActive[i]) {
                dbg(NEIGHBOR_CHANNEL,
                    "Node %u: Neighbor %u timed out\n",
                    TOS_NODE_ID, neighborList[i]);
                changed = TRUE;
            }
        }

        if(newCount != neighborCount || changed) {
            memcpy(neighborList, newList, sizeof(uint16_t)*newCount);
            memcpy(linkCosts, newCosts, sizeof(uint32_t)*newCount);
            memcpy(lastSeen, newSeen, sizeof(uint32_t)*newCount);
            memcpy(neighborActive, newActive, sizeof(bool)*newCount);

            neighborCount = newCount;

            signal NeighborDiscovery.neighborsChanged();
        }
    }


    command void NeighborDiscovery.start(){
        uint8_t i;
        for(i = 0; i < 20; i++){
            linkCosts[i] = INF;
            rttEWMA[i] = 150;
            waitingForRTT[i] = FALSE;
            neighborActive[i] = FALSE;
            lastSeen[i] = 0;
        }
        call NeighborTimer.startOneShot(1000 + (uint16_t)(call Random.rand16() % 1000));
    }

    task void findNeighbors(){
        pack pkt;
        uint8_t i;
        uint32_t now;
        currentSeq++;

        
        makePack(&pkt, TOS_NODE_ID, AM_BROADCAST_ADDR, 1, PROTOCOL_NEIGHBORPING, currentSeq, NULL, 0);
        call Sender.send(pkt, AM_BROADCAST_ADDR);

        now = call NeighborTimer.getNow();
        for(i = 0; i < neighborCount; i++) {
            rttStartTime[i] = now;
            waitingForRTT[i] = TRUE;

            makePack(&pkt, TOS_NODE_ID, neighborList[i],1, PROTOCOL_NEIGHBORPING, currentSeq, NULL, 0);

            call Sender.send(pkt, neighborList[i]);
        }

        call CostTimer.startOneShot(1500);
    }

    event void NeighborTimer.fired(){
        checkNeighborTimeouts();
        post findNeighbors();
    }

    command void NeighborDiscovery.printNeighbors(){    
        uint8_t i;
        // dbg(GENERAL_CHANNEL, "Node %u Neighbors (%u):\n", TOS_NODE_ID, neighborCount);
        for(i = 0; i < neighborCount; i++){
            // dbg(GENERAL_CHANNEL, "  Neighbor %u: Node %u (Cost: %u)\n", i, neighborList[i], linkCosts[i]);
        }
    }

    event message_t* NeighborReceive.receive(message_t* msg, void* payload, uint8_t len){
        pack* p = (pack*)payload;

        if(len < sizeof(pack))
            return msg;


        if(p->src == TOS_NODE_ID)
            return msg;

        // Handle neighbor update and RTT updates
        call NeighborDiscovery.receiveNeighbors(p->protocol, p->src, NULL);

        return msg;
    }

    command void NeighborDiscovery.receiveNeighbors(uint16_t protocol, uint16_t src, uint8_t* unused) {
        pack reply;
        uint8_t idx = addOrUpdateNeighbor(src);
        if(idx == 0xFF) return;

        lastSeen[idx] = call NeighborTimer.getNow();

        if(protocol == PROTOCOL_NEIGHBORREPLY) {
            if(waitingForRTT[idx]) {
                uint32_t now = call NeighborTimer.getNow();
                uint32_t sample = now - rttStartTime[idx];

                waitingForRTT[idx] = FALSE;

                if(sample >= 2 && sample <= 2000) {
                    uint32_t old = rttEWMA[idx];
                    uint32_t smoothed = (ALPHA_NUM * sample + (ALPHA_DEN - ALPHA_NUM) * old)/ ALPHA_DEN;
                    uint32_t scaled_cost;

                    if(smoothed < 1000) {  // Less than 1ms = excellent
                        scaled_cost = 1;
                    } else if(smoothed < 10000) {  // 1-10ms = good
                        scaled_cost = smoothed / 1000;  // 1-10
                    } else if(smoothed < 60000) {  // 10-60ms = okay
                        scaled_cost = 10 + (smoothed / 10000);  // 10-16
                    } else {  // >60ms = poor
                        scaled_cost = 50;  // High but not infinite
                    }
                    
                    // Cap at reasonable max
                    if(scaled_cost > 100) scaled_cost = 100;
    
                    rttEWMA[idx] = smoothed;
                    linkCosts[idx] = scaled_cost;

                    dbg(NEIGHBOR_CHANNEL,
                        "Node %u: RTT %u → EWMA %u for neighbor %u\n",
                        TOS_NODE_ID, sample, smoothed, src);

                    signal NeighborDiscovery.neighborsChanged();
                }
            }
        }
        else if(protocol == PROTOCOL_NEIGHBORPING) {
            // Respond with unicast reply
            makePack(&reply, TOS_NODE_ID, src,
                     1, PROTOCOL_NEIGHBORREPLY, currentSeq,
                     NULL, 0);

            call Sender.send(reply, src);
        }
    }

    event void CostTimer.fired(){
        signal NeighborDiscovery.neighborsChanged();
        call CostTimer.startOneShot(2000);
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
    
    command uint32_t* NeighborDiscovery.getCostList(){
        return linkCosts;
    }

    command bool NeighborDiscovery.isNeighbor(uint16_t neighborId) {
        return getNeighborIndex(neighborId) != 0xFF;
    }
}