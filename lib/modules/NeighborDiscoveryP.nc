#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channel.h"

module NeighborDiscoveryP(){
    provides interface NeighborDiscovery;

    uses interface Timer<TMilli> as Timer0;
    uses interface Random;
    uses interface SimpleSend;
}

implementation{
    command void NeighborDiscovery.start(){
        call neighborTimer.startOneShot(1000 + (uint16_t)(call Random.rand16()%1000));
    }
    task void findNeighbor(){
        

        call neighborTimer.startPeriodic(1000 + (uint16_t)(call Random.rand16()%1000));
    }
    event void neighborTimer.fired(){

    }
    command void NeighborDiscovery.printNeighbors(){

    }
}