#include <Timer.h>
#include "../../includes/channels.h"
#include "../../includes/neighborEntry.h"

generic configuration FloodingC(){
    provides interface Flooding;
}

implementation{
    components new FloodingP() as Flood;
    Flooding = Flood.Flooding;

    components new TimerMilliC() as FloodingTimer;
    Flood.FloodingTimer -> FloodingTimer;

    components RandomC as Random;
    Flood.Random -> Random;

    components ActiveMessageC;
    Flood.Packet -> ActiveMessageC;

    components new AMReceiverC(AM_FLOODING) as FloodReceive;
    Flood.FloodReceive -> FloodReceive;

    components new HashmapC(NeighborEntry, 20) as NeighborTable;
    Flood.NeighborTable -> NeighborTable;

    components new SimpleSendC(AM_FLOODING) as Send;
    Flood.Send -> Send;

    components new NeighborDiscoveryC() as NeighborDiscovery;
    Flood.NeighborDiscovery -> NeighborDiscovery;
}
