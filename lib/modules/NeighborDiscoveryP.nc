#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channels.h"

generic module NeighborDiscoveryP(){
    provides interface NeighborDiscovery;

    uses interface Pool<sendInfo> as Pool;
    uses interface Queue<sendInfo*> as Queue;

    uses interface Timer<TMilli> as NeighborTimer;
    uses interface Random;

    uses interface SimpleSend as Sender;

    uses interface Packet;
}

implementation{
    uint16_t neighborList[20];
    uint8_t neighborCount = 0;
    pack sendPackage;
    pack returnPackage;
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t *payload, uint8_t length);

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t *payload, uint8_t length){
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
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

    command void NeighborDiscovery.start(){
        call NeighborTimer.startOneShot(1000 + (uint16_t)(call Random.rand16()%1000));
    }

    task void findNeighbors(){
        uint16_t destination = AM_BROADCAST_ADDR;
        uint8_t *payload = 0;
        uint16_t HELLO = 100;
        if(isNeighbor(destination)){
            return;
        }
        else{
            makePack(&sendPackage, TOS_NODE_ID, destination, 0, HELLO, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
            call Sender.send(sendPackage, destination);
            dbg(NEIGHBOR_CHANNEL, "Sent neighbor discovery packet from %u to %u\n", TOS_NODE_ID, destination);
        }

        call NeighborTimer.startPeriodic(1000 + (uint16_t)(call Random.rand16()%1000));
    }

    event void NeighborTimer.fired(){
        post findNeighbors();
    }

    command void NeighborDiscovery.printNeighbors(){    
        uint8_t i;
        for (i = 0; i < neighborCount; i++) {
            dbg(NEIGHBOR_CHANNEL, "Neighbor %u: %u\n", i, neighborList[i]);
        }

    }

    command void NeighborDiscovery.receiveNeighbors(uint16_t protocol, uint16_t src){
        uint16_t REPLY = 101;
        uint8_t *payload = 0;
        if(protocol == 101){
            if(!isNeighbor(src) && neighborCount < 20){
                neighborList[neighborCount] = src;
                neighborCount++;
                dbg(NEIGHBOR_CHANNEL, "Discovered new neighbor: %u\n", src);
            }
        }
        else if(protocol == 100){
            makePack(&returnPackage, TOS_NODE_ID, src, 0, REPLY, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
            call Sender.send(returnPackage, src);
            dbg(NEIGHBOR_CHANNEL, "Replied to neighbor discovery from %u to %u\n", TOS_NODE_ID, src);
        }
    }
}