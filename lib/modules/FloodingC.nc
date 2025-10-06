#include <Timer.h>
#include "../../includes/channels.h"
#include "../../includes/neighborEntry.h"

generic configuration FloodingC(){
    provides interface Flooding;
}

implementation{
    components new FloodingP() as Flood;
    Flooding = Flood.Flooding;

    components new TimerMilliC() as FloodingTimer1;
    Flood.FloodingTimer1 -> FloodingTimer1;

    // components new TimerMilliC() as FloodingTimer2;
    // Flood.FloodingTimer2 -> FloodingTimer2;

    components RandomC as Random;
    Flood.Random -> Random;

    components ActiveMessageC;
    Flood.Packet -> ActiveMessageC;

    // components new AMReceiverC(AM_FLOODING) as FloodReceive;
    // Flood.FloodReceive -> FloodReceive;

    components new HashmapC(NeighborEntry, 20) as NeighborTable;
    Flood.NeighborTable -> NeighborTable;

    components new SimpleSendC(AM_PACK) as Send;
    Flood.Send -> Send;

    components new NeighborDiscoveryC();
    Flood.NeighborDiscovery -> NeighborDiscoveryC;
}
