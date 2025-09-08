#include <Timer.h>
#include "../../includes/channel.h"

configuration NeighborDiscoveryC(){
    provides interface NeighborDiscovery;
}

implementation{
    components new NeighborDiscoveryP();
    NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;

    components new TimerMilliC() as Timer0;
    components RandomC as Random;
    components new SimpleSendC(HELLO_PING) as SimpleSend;
    
    NeighborDiscoveryP.Timer0 -> Timer0;
    NeighborDiscoveryP.Random -> Random;
    NeighborDiscoveryP.SimpleSend -> SimpleSend;
}