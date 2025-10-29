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

    components new TimerMilliC() as CostTimer;
    NeighborD.CostTimer -> CostTimer;

    components RandomC as Random;
    NeighborD.Random -> Random;

    components ActiveMessageC;
    NeighborD.Packet -> ActiveMessageC;

    components new AMReceiverC(AM_FLOODING) as NeighborReceive;
    NeighborD.NeighborReceive -> NeighborReceive;

    components new SimpleSendC(AM_FLOODING) as Sender;
    NeighborD.Sender -> Sender;
}
