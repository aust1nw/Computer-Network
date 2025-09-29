#include <Timer.h>
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"

generic configuration NeighborDiscoveryC() {
  provides interface NeighborDiscovery;
}

implementation {
    components new NeighborDiscoveryP() as NeighborD;
    NeighborDiscovery = NeighborD.NeighborDiscovery;

    components new TimerMilliC() as NeighborTimer;
    NeighborD.NeighborTimer -> NeighborTimer;

    components RandomC as Random;
    NeighborD.Random -> Random;

    components ActiveMessageC;
    NeighborD.Packet -> ActiveMessageC;

    components new AMReceiverC(AM_PACK) as NeighborReceive;
    NeighborD.NeighborReceive -> NeighborReceive;

    components new SimpleSendC(AM_PACK) as Sender;
    NeighborD.Sender -> Sender;
    

    //components new PoolC(sendInfo, 20) as Pool;
    //components new QueueC(sendInfo*, 20) as Queue;
    //NeighborD.Pool -> Pool;
    //NeighborD.Queue -> Queue;
}
