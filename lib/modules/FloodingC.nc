#include <Timer.h>
#include "../../includes/channels.h"

generic configuration FloodingC(){
    provides interface Flooding:

}
implementation{
    components new FloodingP();

    Flooding = FloodingP.Flooding;

    components new TimerMilliC() as FloodTimer;
    components RandomC as Random;
    
    FloodingP.FloodTimer -> FloodTimer;
    FloodingP.Random -> Random;

    components ActiveMessageC;
    FloodingP.Packet -> ActiveMessageC;

    components new HashmapC(uint16_t node, uint16_t size);
    FloodingP.Hashmap -> HashmapC;

    components new SimpleSendC(AM_PACK) as Send;
    FloodingP.Send -> Send;
}
