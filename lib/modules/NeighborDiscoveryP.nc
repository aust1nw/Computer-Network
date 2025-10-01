#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channels.h"

generic module NeighborDiscoveryP(){
    provides interface NeighborDiscovery;

    uses interface Timer<TMilli> as NeighborTimer;
    uses interface Random;

    uses interface Packet;
    uses interface Receive as NeighborReceive;

    uses interface SimpleSend as Sender;

    //uses interface Pool<sendInfo> as Pool;
    //uses interface Queue<sendInfo*> as Queue;
}

implementation{
    uint16_t neighborList[20];
    uint8_t neighborCount = 0;

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
        for(i = 0; i <= neighborCount; i++){
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
        pack sendPacket;
        uint16_t destination = AM_BROADCAST_ADDR;
        uint8_t *payload = 0;
        uint16_t HELLO = 100;
        uint16_t nTTL = 1;
        uint16_t nSeq = 0;
        
        makePack(&sendPacket, TOS_NODE_ID, destination, nTTL, HELLO, nSeq, payload, PACKET_MAX_PAYLOAD_SIZE);
        call Sender.send(sendPacket, destination);
        dbg(NEIGHBOR_CHANNEL, "Sent neighbor discovery packet from %u to %u\n", TOS_NODE_ID, destination);

        call NeighborTimer.startPeriodic(1000 + (uint16_t)(call Random.rand16()%1000));
    }

    event void NeighborTimer.fired(){
        post findNeighbors();
    }

    command void NeighborDiscovery.printNeighbors(){    
        uint8_t i;
        for(i = 0; i < neighborCount; i++){
            dbg(NEIGHBOR_CHANNEL, "Neighbor %u: %u\n", i, neighborList[i]);
        }
    }

    event message_t* NeighborReceive.receive(message_t* msg, void* payload, uint8_t len){
        if(len==sizeof(pack)){
            pack* myMsg=(pack*) payload;
            call NeighborDiscovery.receiveNeighbors(myMsg->protocol, myMsg->src, &neighborCount);
            return msg;
        }
        return msg;
    }

    command void NeighborDiscovery.receiveNeighbors(uint16_t protocol, uint16_t src, uint8_t* idx){
        pack returnPacket;
        uint16_t REPLY = 101;
        uint8_t *payload = 0;
        uint16_t repTTL = 1;
        uint16_t repSeq = 0;

        if(src == TOS_NODE_ID){
            return;
        }

        if(protocol == 101){  
            if(!isNeighbor(src) && *idx < 20){
                neighborList[*idx] = src;
                (*idx)++;
                dbg(NEIGHBOR_CHANNEL, "Discovered new neighbor: %u\n", src);
            }
        }
        else if(protocol == 100){ 
            if(!isNeighbor(src) && *idx < 20){
                neighborList[*idx] = src;
                (*idx)++;
                dbg(NEIGHBOR_CHANNEL, "Discovered new neighbor: %u\n", src);
                makePack(&returnPacket, TOS_NODE_ID, src, repTTL, REPLY, repSeq, payload, PACKET_MAX_PAYLOAD_SIZE);
                call Sender.send(returnPacket, src);
                dbg(NEIGHBOR_CHANNEL, "Replied to neighbor discovery from %u to %u\n", TOS_NODE_ID, src);
            }
        }
        else{
            dbg(NEIGHBOR_CHANNEL, "Unknown protocol %u from %u\n", protocol, src);
            return;
        }
    }

    command uint8_t NeighborDiscovery.getCount(){
        dbg(FLOODING_CHANNEL, "returning %u\n", neighborCount);
        return neighborCount;
    }
    command uint32_t NeighborDiscovery.getList(uint8_t count){
        if(count < neighborCount){
            return neighborList[count];
        }
        return 0;
    }
}