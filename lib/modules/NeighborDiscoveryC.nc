#include <Timer.h>
#include "../../includes/channel.h"

configuration NeighborDiscoveryC(){
    provides interface NeighborDiscovery;
}

implementation{
    components new NeighborDiscoveryP();
    NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;

    components new SimpleSendC(AM_HELLO) as SimpleSend;
    NeighborDiscoveryP.Sender -> SimpleSend;

    components new AMReceiverC(AM_REPLY) as PingReceive;
    NeighborDiscoveryP.Receive -> PingReceive;

    components ActiveMessageC;
    NeighborDiscoveryP.AMControl -> ActiveMessageC;
    
    components new TimerMilliC() as Timer0;
    components RandomC as Random;
    
    NeighborDiscoveryP.Timer0 -> Timer0;
    NeighborDiscoveryP.Random -> Random;
}