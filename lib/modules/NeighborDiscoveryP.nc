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

    task void findNeighbors(uint16_t destination){
        if(!isNeighbor(destination)){
            sendInfo* search = call Pool.get();
            if(search == NULL){
                return;
            }

            search->dest = destination;
            search->src = TOS_NODE_ID;
            search->packet.protocol = AM_HELLO;
            search->packet.TTL = 1;
        
            call Queue.enqueue(search);
            call Sender.send(TOS_NODE_ID, destination);
        }
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

    // command void NeighborDiscovery.receiveNeighbors(uint16_t packet, uint16_t src){
    //     if(packet == AM_HELLO){
    //         sendInfo* respond = call Pool.get();
    //         if(respond != NULL){
    //             return;
    //         }
    //         respond->dest = src;
    //         respond->src = dest;
    //         respond->packet = AM_REPLY;
    //         respond->TTL = 1;
    //         call Queue.enqueue(respond);
    //         call Sender.send(TOS_NODE_ID, src);
    //     }
    //     else if(packet == AM_REPLY){
    //         if(!isNeighbor(src) && neighborCount < 20){
    //             neighborList[neighborCount++] = src;
    //         }
    //     }
    // }
}