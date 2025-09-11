#include <Timer.h>
#include "../../includes/channel.h"

generic configuration NeighborDiscoveryC(){
    provides interface NeighborDiscovery;
}

implementation{
    components new NeighborDiscoveryP();
    
    NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;

    components new SimpleSendC(AM_HELLO);
    
    NeighborDiscoveryP.Sender -> SimpleSendC;

    components new AMReceiverC(AM_REPLY) as PingReceive;
    components ActiveMessageC;

    NeighborDiscoveryP.Receive -> PingReceive;
    NeighborDiscoveryP.AMControl -> ActiveMessageC;

    components new TimerMilliC() as Timer0;
    components RandomC as Random;
    
    NeighborDiscoveryP.Timer0 -> Timer0;
    NeighborDiscoveryP.Random -> Random;

    // is list better?
    components new PoolC(sendInfo, 20);
    components new QueueC(sendInfo*, 20);

    NeighborDiscoveryP.Pool -> PoolC;
    NeighborDiscoveryP.Queue -> QueueC;
}