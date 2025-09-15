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
    uses interface SplitControl as AMControl;
    uses interface Receive as Receive;

    uses interface Packet;
    uses interface AMPacket;
    uses interface AMSend;
}

implementation{
    uint16_t neighborList[20];
    uint8_t neighborCount = 0;

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
        if(isNeighbor(destination)){
            return;
        }
        sendInfo* info = call Pool.get();
        if(info == NULL){
            dbg("NeighborDiscovery", "No sendInfo available\n");
            return;
        }
        pack* pkt = (pack*) call Packet.getPayload(&info->msg, sizeof(pack));
        if(pkt == NULL){
            dbg("NeighborDiscovery", "No payload available\n");
            call Pool.put(info);
            return;
        }
        pkt->protocol = 0;
        pkt->src = TOS_NODE_ID;
        pkt->dest = destination;
        pkt->seq = 0;
        pkt->TTL = 1;

        info->dest = destination;
        info->len = sizeof(CommandMsg);
        info->retries = 0;
        info->msgType = AM_PACK;
        

        call NeighborTimer.startPeriodic(1000 + (uint16_t)(call Random.rand16()%1000));
    }

    event void NeighborTimer.fired(){
        post findNeighbors();
    }

    command void NeighborDiscovery.printNeighbors(){    
        uint8_t i;
        for (i = 0; i < neighborCount; i++) {
            dbg("NeighborDiscovery", "Neighbor %u: %u\n", i, neighborList[i]);
        }

    }

    command void NeighborDiscovery.receiveNeighbors(uint16_t packet, uint16_t src){
    
    }
}