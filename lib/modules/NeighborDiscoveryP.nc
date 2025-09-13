#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channel.h"

generic module NeighborDiscoveryP(){
    provides interface NeighborDiscovery;

    uses interface SimpleSend as Sender;
    
    uses interface SplitControl as AMControl;
    uses interface Receive;
    
    uses interface Timer<TMilli> as Timer0;
    uses interface Random;

    uses interface Pool<sendInfo>;
    uses interface Queue<sendInfo*>;
}

implementation{

    uint16_t neighborList[20];
    uint8_t neighborCount = 0;

    bool isNeighbor(uint16_t nodeID){
        for(uint8_t i = 0; i < neighborCount; i++){
            if(neighborList[i] == nodeID){
                return TRUE;
            }
        }
        return FALSE;
    }

    command void NeighborDiscovery.start(){
        call neighborTimer.startOneShot(1000 + (uint16_t)(call Random.rand16()%1000));
    }
    task void findNeighbors(){
        sendInfo* input = call Pool.get();
        if(input == NULL){
            return;
        }

        input->dest = TOS_BROADCAST_ADDR;
        input->src = TOS_NODE_ID;
        input->packet = AM_HELLO;
        input->TTL = 1;
        
        call Queue.enqueue(input);
        post Sender.sendBufferTask();
        call neighborTimer.startPeriodic(1000 + (uint16_t)(call Random.rand16()%1000));
    }
    event void neighborTimer.fired(){
        post findNeighbors();
    }
    command void NeighborDiscovery.printNeighbors(){    
        for(uint8_t i = 0; i < neighborCount; i++){
            dbg("NeighborDiscovery", "Neighbor %d: %d\n", i, neighborList[i]);
        }

    }

    command void NeighborDiscovery.receiveNeighbors(uint16_t packet, uint16_t src){
        if(packet == AM_HELLO){
            sendInfo* buf = call Pool.get();
            if(buf != NULL){
                return;
            }
            buf->dest = src;
            buf->src = TOS_NODE_ID;
            buf->packet = AM_REPLY;
            buf->TTL = 1;
            call Queue.enqueue(input);
            post Sender.sendBufferTask();
        }
        else if(packet == AM_REPLY){
            if(!isNeighbor(src) && neighborCount < 20){
                neighborList[neighborCount++] = src;
            }
        }
    }
}